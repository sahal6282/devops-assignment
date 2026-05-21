#!/bin/bash
set -e

apt update -y
apt install -y git curl build-essential

# Node 20
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Install iii CLI
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
export PATH=$PATH:$HOME/.local/bin

# Clone repo
cd /home/ubuntu
git clone https://github.com/sahal6282/devops-assignment.git
cd devops-assignment/quickstart/workers/caller-worker

npm install

# IMPORTANT: connect to inference VM (private IP)
export III_URL="ws://<INFERENCE_PRIVATE_IP>:49134"

nohup npm run dev > caller.log 2>&1 &

echo "Caller VM setup complete"
