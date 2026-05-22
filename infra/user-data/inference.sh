#!/bin/bash
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

set -e

echo "Starting Python Inference Worker setup..."

# ==========================================================
# Add swap space for t3.micro stability
# ==========================================================

fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

grep -q "/swapfile" /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

echo "Swap configured"

# ==========================================================

apt update -y

apt install -y \
    git \
    curl \
    unzip \
    python3 \
    python3-pip \
    python3-venv

# Install iii CLI
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh

export PATH=$PATH:/root/.local/bin

cp /root/.local/bin/iii /usr/local/bin/iii

# Clone repository
mkdir -p /opt/app

cd /opt/app

git clone https://github.com/sahal6282/devops-assignment.git quickstart-repo

# Go to inference worker
cd /opt/app/quickstart-repo/quickstart/workers/inference-worker

# Create virtual environment
python3 -m venv venv

source venv/bin/activate

# Install dependencies
pip install --upgrade pip
pip install -r requirements.txt

# ==========================================================
# Create systemd service
# ==========================================================

cat << EOF > /etc/systemd/system/inference-worker.service
[Unit]
Description=Python Inference RPC Worker
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app/quickstart-repo/quickstart/workers/inference-worker

Environment=III_URL=ws://${api_ip}:49134
Environment=PATH=/opt/app/quickstart-repo/quickstart/workers/inference-worker/venv/bin:/usr/local/bin:/usr/bin:/bin

ExecStart=/opt/app/quickstart-repo/quickstart/workers/inference-worker/venv/bin/python inference_worker.py

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# ==========================================================
# Start service
# ==========================================================

systemctl daemon-reload

systemctl enable inference-worker.service
systemctl start inference-worker.service

echo "Inference VM setup complete"
