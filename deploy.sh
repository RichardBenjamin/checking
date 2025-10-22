
#  Setup for safety and error handling ---
set -e


#  Setup for logging  
Log_Dir="./logs"
mkdir -p "$Log_Dir"  

Log_File="$Log_Dir/deploy_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$Log_File") 2>&1
trap 'echo "Error occurred at line $LineNo. Check $Log_File for more details."' ERR

echo "Logs will be saved in: $Log_File"

# --- Utility Function for Timestamped Logs ---
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# ============================================
# SECTION 1: Collect User Inputs
# ============================================
log " Collecting inputs for deployment."

read -p "Enter your Git Repository URL: " Repo_Url
read -s -p "Enter your Personal Access Token (PAT): " PAT
read -p "Enter your branch name (default branch is main): " Branch
read -p "Enter your remote server username: " SSH_User
read -p "Enter your remote server IP address: " Server_Ip
read -p "Enter SSH key path: " SSH_Key
read -p "Enter your Application Port (internal container port): " App_Port

# To Main As Default Branch
Branch=${Branch:-main}

# Local variables
Repo_Dir=$(basename "$Repo_Url" .git)
Remote_Dir="/home/$SSH_User/app"
Nginx_Conf="/etc/nginx/sites-available/HNG_app"

# To Validate Inputs
if [[ -z "$Repo_Url" || -z "$PAT" || -z "$SSH_User" || -z "$Server_Ip" || -z "$SSH_Key" || -z "$App_Port" ]]; then
  log " Error: All fields are required for script to run."
  exit 1
fi

log "All User inputs collected."
log "Git Repository Url: $GIT_Url"
log "Remote Server: $SSH_User@$Server_Ip"
log "Application Port: $App_Port"

sleep 1


# Stage 2: Cloning of Repository
log "Cloning Repository ....."

# # Extract repo name from URL (e.g., https://github.com/user/app.git → app)
# REPO_DIR=$(basename "$GIT_URL" .git)

# Checking if repo already exists, to pull latest changes
if [ -d "$Repo_Dir" ]; then
  log " Repository '$Repo_Dir' already exists. Pulling latest changes..."
  cd "$Repo_Dir"
  git fetch origin "$Branch"
  git switch "$Branch"
  git pull origin "$Branch"
else
  log " Cloning $GIT_Url ..."
  git clone https://${PAT}@${Repo_Url#https://}
  cd "$Repo_Dir"
  git switch "$Branch"
fi

# To verify Docker configuration
if [[ -f "Dockerfile" ]]; then
  log " Dockerfile found."
elif [[ -f "docker-compose.yml" ]]; then
  log "docker-compose.yml found."
else
  log " No Dockerfile or docker-compose.yml found. Add Docker file to continue."
  exit 1
fi

log "Repository has been cloned successfully."

sleep 1

# ============================================
# SECTION 3: SSH and Remote Setup
# ============================================
log "🔗 Connecting to remote server: $SSH_User@$Server_Ip ..."

ssh -i "$SSH_Key" -o StrictHostKeyChecking=no "$SSH_User@$Server_Ip" << EOF
  set -e
  echo " Updating packages and installing dependencies..."
  sudo apt update -y
  sudo apt install -y docker.io docker-compose curl nginx
  sudo systemctl enable docker
  sudo systemctl start docker
  sudo usermod -aG docker \$USER

EOF

sleep 1

# ============================================
# SECTION 4: Deploy Dockerized Application
# ============================================
log " Copying project files to remote server via scp"
scp -i "$SSH_Key" -r $(ls -A | grep -v '.git') "$SSH_User@$Server_Ip:/home/$SSH_User/app"
log " Application is been deployed remotely."
ssh -i "$SSH_Key" "$SSH_User@$Server_Ip" << EOF
  set -e
  cd /home/$SSH_User/app

  # To stop old containers to ensure Idempotent redploy (idempotent redeploy)
  docker stop myapp || true
  docker rm myapp || true

  if [ -f "docker-compose.yml" ]; then
    echo "Using docker-compose for deployment."
    docker-compose down || true
    docker-compose up -d --build
  else
    echo "Using Dockerfile for deployment."
    docker build -t myapp .
    docker run -d -p ${APP_Port}:${APP_Port} --name myapp myapp
  fi

  echo "✅ Application deployed successfully!"
EOF

sleep 1

# ============================================
# SECTION 5: Configure Nginx Reverse Proxy
# ============================================
log "⚙️ Configuring Nginx reverse proxy..."
ssh -i "$SSH_Key" "$SSH_User@$Server_Ip" << EOF
  sudo bash -c 'cat > /etc/nginx/sites-available/myapp << NGINX_CONF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:${App_Port};
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
ssh -i "$SSH_Key" "$SSH_User@$Server_Ip" << EOF
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
  ssh -i "$SSH_Key" "$SSH_User@$Server_Ip" << EOF
    docker stop myapp || true
    docker rm myapp || true
    sudo rm -rf /home/$SSH_User/app
    sudo rm -f /etc/nginx/sites-enabled/myapp /etc/nginx/sites-available/myapp
    sudo systemctl reload nginx
    echo "🧼 Cleanup complete."
EOF
fi

log "🚀 Deployment process completed successfully!"
