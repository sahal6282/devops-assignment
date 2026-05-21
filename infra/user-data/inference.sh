#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -e

echo "Starting Python Inference Worker setup..."

# ==========================================
# CRITICAL FIX: Add 2GB Swap Space to prevent 
# t3.micro from crashing due to out-of-memory
# ==========================================
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
echo "Swap space configured successfully."
# ==========================================

apt update -y
apt install -y git curl unzip python3 python3-pip python3-venv

curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
cp /root/.local/bin/iii /usr/local/bin/iii

mkdir -p /opt/app
cd /opt/app
git clone https://github.com/sahal6282/devops-assignment.git quickstart-repo

cd /opt/app/quickstart-repo/quickstart/workers/inference-worker

python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

cat << EOF > /etc/systemd/system/inference-worker.service
[Unit]
Description=Python Inference RPC Worker
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app/quickstart-repo/quickstart/workers/inference-worker
Environment=III_URL="ws://${api_ip}:49134"
ExecStart=/opt/app/quickstart-repo/quickstart/workers/inference-worker/venv/bin/python inference_worker.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now inference-worker.service

echo "Python Inference VM setup complete"
