#!/bin/bash
set -euxo pipefail
exec > /var/log/user-data.log 2>&1

apt update -y
apt install -y docker.io docker-compose git

systemctl enable docker
systemctl start docker

mkdir -p /opt/observability
cd /opt/observability

cat <<EOF > docker-compose.yml
version: "3"

services:
  grafana:
    image: grafana/grafana
    volumes:
      - grafana-data:/var/lib/grafana
    ports:
      - "3000:3000"

volumes:
  grafana-data:
EOF

cd /opt/observability
sudo docker-compose up -d

echo "Grafana stack started successfully!"