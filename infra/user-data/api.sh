#!/bin/bash
set -e

apt update -y
apt install -y git curl unzip

# Node (needed for some iii components)
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Install iii CLI
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
export PATH=$PATH:$HOME/.local/bin

# Clone repo
cd /home/ubuntu
git clone https://github.com/sahal6282/devops-assignment.git
cd devops-assignment/quickstart

# Start engine
nohup iii start config.yaml > engine.log 2>&1 &

echo "API VM setup complete"
