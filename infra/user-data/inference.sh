#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

set -e

export HOME=/root
export PATH=$PATH:/root/.local/bin

# Add swap for t3.micro
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

echo '/swapfile none swap sw 0 0' >> /etc/fstab

apt update -y
apt install -y git curl unzip python3 python3-pip python3-venv

# Install iii
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh

cp $HOME/.local/bin/iii /usr/local/bin/iii

mkdir -p /opt/app
cd /opt/app

git clone https://github.com/sahal6282/devops-assignment.git quickstart-repo

cd /opt/app/quickstart-repo/quickstart/workers/inference-worker

python3 -m venv venv

source venv/bin/activate

pip install -r requirements.txt

export III_URL="ws://${api_ip}:49134"

nohup venv/bin/python inference_worker.py > /var/log/inference-worker.log 2>&1 &
