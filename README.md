# 🚀 Automated Deployment Bash Script — HNG13 Stage 1 (DevOps)

A Bash-based DevOps project that automates cloning, setup, and deployment of a Dockerized application to a remote Linux server with Nginx reverse proxy, full logging, and error handling.

It demonstrates practical **DevOps automation**, covering repository management, remote server provisioning, Docker deployment, Nginx configuration, logging, and cleanup.

---

## 📋 Features

- Collects and validates user input (Git repo, PAT, SSH details, port)
- Authenticates and clones repository automatically
- Installs Docker, Docker Compose, and Nginx on remote server
- Builds and runs Docker containers
- Configures Nginx as a reverse proxy
- Validates deployment and container health
- Logs every action with timestamps
- Supports safe cleanup and idempotent re-runs

---

## 🧰 Prerequisites

Before running the script, ensure you have:

- A **remote Ubuntu/Linux server** (e.g., AWS EC2)
- **SSH access** to the server (key-based authentication)
- A **GitHub Personal Access Token (PAT)** with repo access
- Locally installed:
  - `bash`
  - `git`
  - `ssh`
  - `rsync` or `scp`
  - Internet connection

---

## ⚙️ Setup & Usage

### 1. Clone this Repository
`git clone https://github.com/CloudFay/hng13-stage1-devops.git`

`cd hng13-stage1-devops`

### 2. Make Script Executable
`chmod +x deploy.sh`

### 3. Run the Script
`./deploy.sh`

You will be prompted for:
- Git Repository URL
- Personal Access Token (PAT)
- Branch name (optional; defaults to main)
- SSH Username
- Server IP Address
- SSH Key Path
- Application Port (internal container port)

---

## What Happens Under the Hood
- Collects Inputs: Gathers required deployment parameters
- Clones Repo: Uses your PAT to clone or pull latest changes
- Remote Setup: Installs Docker, Docker Compose, and Nginx
- Deploys App: Builds and runs Docker containers
- Nginx Proxy: Configures reverse proxy to container port
- Validation: Checks container and service status
- Logging: Saves output to deploy_YYYYMMDD.log
- Cleanup (optional): Removes containers, images, and configs safely

---

## Cleanup Command
To remove deployed resources and reset the environment:

`./deploy.sh --cleanup`

---

## 🪵 Logging
All actions are logged with timestamps in:

`logs/deploy_YYYYMMDD.log`

---

## 👨‍💻 Author: Faith Omobude
`DevOps Intern — HNG13 🚀`
