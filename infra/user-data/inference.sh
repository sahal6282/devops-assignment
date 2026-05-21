#!/bin/bash
set -e

apt update -y
apt install -y git curl nodejs npm

curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
export PATH=$PATH:$HOME/.local/bin

cd /home/ubuntu
git clone https://github.com/sahal6282/devops-assignment.git
cd devops-assignment/quickstart/workers/caller-worker

npm install

# 👇 injected by terraform
export III_URL="ws://%{inference_ip}:49134"

nohup npm run dev > caller.log 2>&1 &
