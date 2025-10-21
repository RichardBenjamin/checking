#!/bin/bash
# ============================================
# Automated Deployment Script (deploy.sh)
# Author: Faith Omobude
# Description: Automates cloning, setup, and deployment of a Dockerized application to a remote Linux server with Nginx reverse proxy, full logging, and error handling.
# ============================================

# --- Safety & Error Handling ---
set -e
set -o pipefail
set -u

# --- Logging Setup ---
LOG_DIR="./logs"
mkdir -p "$LOG_DIR"   # Create logs directory if it doesn’t exist

LOG_FILE="$LOG_DIR/deploy_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo "❌ Error occurred at line $LINENO. Check $LOG_FILE for details."' ERR

echo "🗂 Logs will be saved in: $LOG_FILE"

# --- Utility Function for Timestamped Logs ---
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# ============================================
# SECTION 1: Collect User Inputs
# ============================================
log "🔧 Collecting deployment parameters..."

read -p "Enter Git Repository URL: " GIT_URL
read -s -p "Enter Personal Access Token (PAT): " PAT
echo ""
read -p "Enter Branch name (default: main): " BRANCH
BRANCH=${BRANCH:-main}
read -p "Enter Remote Server Username: " SSH_USER
read -p "Enter Remote Server IP Address: " SERVER_IP
read -p "Enter SSH Key Path (e.g., ~/.ssh/id_rsa): " SSH_KEY
read -p "Enter Application Port (internal container port): " APP_PORT

# --- Validate Inputs ---
if [[ -z "$GIT_URL" || -z "$PAT" || -z "$SSH_USER" || -z "$SERVER_IP" || -z "$SSH_KEY" || -z "$APP_PORT" ]]; then
  log "❌ Error: All fields are required. Please rerun the script and provide all values."
  exit 1
fi

log "✅ User input collected successfully."
log "Repository: $GIT_URL"
log "Remote Server: $SSH_USER@$SERVER_IP"
log "Port: $APP_PORT"

sleep 1

# ============================================
# SECTION 2: Clone Repository
# ============================================
log "�� Starting repository cloning process..."

# Extract repo name from URL (e.g., https://github.com/user/app.git → app)
REPO_DIR=$(basename "$GIT_URL" .git)

# If repo already exists, pull latest changes
if [ -d "$REPO_DIR" ]; then
  log "📂 Repository '$REPO_DIR' already exists. Pulling latest changes..."
  cd "$REPO_DIR"
  git fetch origin "$BRANCH"
  git checkout "$BRANCH"
  git pull origin "$BRANCH"
else
  log "📦 Cloning repository from $GIT_URL ..."
  git clone https://${PAT}@${GIT_URL#https://}
  cd "$REPO_DIR"
  git checkout "$BRANCH"
fi

# Validate Docker configuration
if [[ -f "Dockerfile" ]]; then
  log "🐳 Dockerfile found — OK."
elif [[ -f "docker-compose.yml" ]]; then
  log "🧱 docker-compose.yml found — OK."
else
  log "❌ No Dockerfile or docker-compose.yml found. Cannot proceed."
  exit 1
fi

log "✅ Repository cloned and verified successfully."

sleep 1

# ============================================
# SECTION 3: SSH and Remote Setup
# ============================================
log "🔗 Connecting to remote server: $SSH_USER@$SERVER_IP ..."

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" << EOF
  set -e
  echo "🧰 Updating packages and installing dependencies..."
  sudo apt update -y
  sudo apt install -y docker.io docker-compose nginx curl

  sudo systemctl enable docker
  sudo systemctl start docker
  sudo usermod -aG docker \$USER

  echo "✅ Remote environment setup complete."
EOF

sleep 1

# ============================================
# SECTION 4: Deploy Dockerized Application
# ============================================
log "📤 Transferring project files to remote server..."
scp -i "$SSH_KEY" -r $(ls -A | grep -v '.git') "$SSH_USER@$SERVER_IP:/home/$SSH_USER/app"
log "🚀 Deploying application remotely..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" << EOF
  set -e
  cd /home/$SSH_USER/app

  # Stop any old containers (idempotent redeploy)
  docker stop myapp || true
  docker rm myapp || true

  if [ -f "docker-compose.yml" ]; then
    echo "🧱 Using docker-compose for deployment..."
    docker-compose down || true
    docker-compose up -d --build
  else
    echo "🐳 Using Dockerfile for deployment..."
    docker build -t myapp .
    docker run -d -p ${APP_PORT}:${APP_PORT} --name myapp myapp
  fi

  echo "✅ Application deployed successfully!"
EOF

sleep 1

# ============================================
# SECTION 5: Configure Nginx Reverse Proxy
# ============================================
log "⚙️ Configuring Nginx reverse proxy..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" << EOF
  sudo bash -c 'cat > /etc/nginx/sites-available/myapp << NGINX_CONF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:${APP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
NGINX_CONF'

  sudo ln -sf /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled/
  sudo nginx -t
  sudo systemctl reload nginx
  echo "✅ Nginx proxy configured successfully."
EOF

sleep 1

# ============================================
# SECTION 6: Validate Deployment
# ============================================
log "🧪 Validating deployment..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" << EOF
  echo "🔍 Checking running containers..."
  docker ps
  echo "🌐 Testing application endpoint..."
  curl -I http://localhost || echo "⚠️ Warning: Application may not be responding locally."
EOF

log "✅ Deployment validation complete!"

# ============================================
# SECTION 7: Cleanup & Idempotency
# ============================================
if [[ "${1:-}" == "--cleanup" ]]; then
  log "🧹 Cleaning up deployment resources..."
  ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" << EOF
    docker stop myapp || true
    docker rm myapp || true
    sudo rm -rf /home/$SSH_USER/app
    sudo rm -f /etc/nginx/sites-enabled/myapp /etc/nginx/sites-available/myapp
    sudo systemctl reload nginx
    echo "🧼 Cleanup complete."
EOF
fi

log "🚀 Deployment process completed successfully!"
