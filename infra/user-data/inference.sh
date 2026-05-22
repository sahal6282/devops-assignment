#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -e

echo "Starting Inference Worker setup..."

# 1. SWAP Space (Prevents Out-Of-Memory crashes)
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# 2. Base Install
apt update -y
apt install -y git curl unzip python3 python3-pip python3-venv build-essential

# 3. Clone Repo
mkdir -p /opt/app
cd /opt/app
git clone https://github.com/sahal6282/devops-assignment.git quickstart-repo
cd /opt/app/quickstart-repo/quickstart/workers/inference-worker

# 4. Clean Python VENV and Install Packages (Includes gguf)
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install iii transformers accelerate torch gguf

# 5. Create Systemd Service for Python Worker
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

echo "Inference VM setup complete"
