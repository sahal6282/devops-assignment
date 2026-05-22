#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

set -e

export HOME=/root
export PATH=$PATH:/root/.local/bin

apt update -y

apt install -y git curl

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -

apt install -y nodejs

mkdir -p /opt/app

cd /opt/app

git clone https://github.com/sahal6282/devops-assignment.git quickstart-repo

cd /opt/app/quickstart-repo/quickstart/workers/caller-worker

npm install

npm run build || true

export III_URL="ws://${api_ip}:49134"

nohup node dist/worker.js > /var/log/caller-worker.log 2>&1 &
