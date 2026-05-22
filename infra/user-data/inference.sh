#!/bin/bash
set -e

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "=== Starting Inference VM setup ==="

# ---------------------------
# BASE SYSTEM SETUP
# ---------------------------
apt update -y
apt install -y git curl unzip python3 python3-pip python3-venv build-essential

# ---------------------------
# SWAP (IMPORTANT FOR TORCH)
# ---------------------------
fallocate -l 2G /swapfile || true
chmod 600 /swapfile || true
mkswap /swapfile || true
swapon /swapfile || true
echo '/swapfile none swap sw 0 0' >> /etc/fstab || true

# ---------------------------
# WORKSPACE SETUP
# ---------------------------
mkdir -p /opt/app
cd /opt/app

# clone repo
git clone https://github.com/sahal6282/devops-assignment.git quickstart-repo

cd /opt/app/quickstart-repo/quickstart/workers/inference-worker

# fix permissions
chown -R ubuntu:ubuntu /opt/app/quickstart-repo

# ---------------------------
# PYTHON ENV (IMPORTANT FIX)
# ---------------------------
sudo -u ubuntu python3 -m venv venv

# install dependencies as ubuntu user (VERY IMPORTANT)
sudo -u ubuntu bash -c "
source venv/bin/activate &&
pip install --upgrade pip &&
pip install iii-sdk transformers accelerate torch
"

# ---------------------------
# ENV VARS
# ---------------------------
echo "export III_URL=ws://<API_PRIVATE_IP>:49134" >> /etc/environment

# ---------------------------
# RUN WORKER (background)
# ---------------------------
sudo -u ubuntu bash -c "
cd /opt/app/quickstart-repo/quickstart/workers/inference-worker &&
source venv/bin/activate &&
nohup python inference_worker.py > /var/log/inference-worker.log 2>&1 &
"

echo "=== Inference VM setup complete ==="
