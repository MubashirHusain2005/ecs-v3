#!/bin/bash
set -euxo pipefail

exec > /var/log/user-data.log 2>&1

#######################
# Install Docker
#######################
dnf install -y docker
systemctl enable docker
systemctl start docker

#######################
# Install Prometheus
#######################
useradd --no-create-home --shell /bin/false prometheus || true

cd /tmp
curl -LO https://github.com/prometheus/prometheus/releases/download/v2.50.1/prometheus-2.50.1.linux-amd64.tar.gz
tar xvf prometheus-2.50.1.linux-amd64.tar.gz

mv prometheus-2.50.1.linux-amd64/prometheus /usr/local/bin/
mv prometheus-2.50.1.linux-amd64/promtool /usr/local/bin/

mkdir -p /etc/prometheus /var/lib/prometheus
chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool

cat <<EOF >/etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "cloudwatch"
    static_configs:
      - targets: ["localhost:5000"]
EOF

cat <<EOF >/etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
After=network-online.target

[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus

[Install]
WantedBy=multi-user.target
EOF

###############################
# Prometheus Alert Rules
###############################
mkdir -p /etc/prometheus/rules
chown -R prometheus:prometheus /etc/prometheus/rules

cat << 'EOF' >/etc/prometheus/rules/ecs-alb-alerts.yml
${ecs_alb_alerts}
EOF

# Ensure Prometheus loads alert rules
if ! grep -q "rule_files:" /etc/prometheus/prometheus.yml; then
cat << 'EOR' >> /etc/prometheus/prometheus.yml

rule_files:
  - "/etc/prometheus/rules/*.yml"
EOR
fi

systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus

###############################
# Configure YACE via Docker
###############################
mkdir -p /etc/yace

cat << 'EOY' >/etc/yace/config.yml
apiVersion: v1alpha1
discovery:
  jobs:
    - type: AWS/ECS
      regions:
        - us-east-1
      metrics:
        - name: CPUUtilization
          statistics: ["Average"]
        - name: MemoryUtilization
          statistics: ["Average"]
        - name: RunningTaskCount
          statistics: ["Average"]

    - type: AWS/ApplicationELB
      regions:
        - us-east-1
      metrics:
        - name: RequestCount
          statistics: ["Sum"]
        - name: HTTPCode_Target_5XX_Count
          statistics: ["Sum"]
        - name: TargetResponseTime
          statistics: ["Average"]
          dimensions:
            - TargetGroup

EOY


docker rm -f yace || true

docker pull prometheuscommunity/yet-another-cloudwatch-exporter-linux-amd64:v0.62.1

docker run -d \
  --name yace \
  --restart unless-stopped \
  --network host \
  -v /etc/yace/config.yml:/etc/yace/config.yml:ro \
  prometheuscommunity/yet-another-cloudwatch-exporter-linux-amd64:v0.62.1 \
  --config.file=/etc/yace/config.yml \
  --listen-address=":5000"