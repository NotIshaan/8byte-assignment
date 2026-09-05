#!/bin/bash
set -e

yum update -y
yum install -y docker amazon-cloudwatch-agent
systemctl start docker
systemctl enable docker

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/app.log",
            "log_group_name": "/${project_name}/app",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/${project_name}/system",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/${project_name}/access",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

aws ecr get-login-password --region ${region} | docker login --username AWS --password-stdin ${ecr_url}

SECRET=$(aws secretsmanager get-secret-value --secret-id ${secret_arn} --region ${region} --query SecretString --output text)

DB_HOST=$(echo $SECRET | python3 -c "import sys,json; print(json.load(sys.stdin)['host'])")
DB_USER=$(echo $SECRET | python3 -c "import sys,json; print(json.load(sys.stdin)['username'])")
DB_PASS=$(echo $SECRET | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")
DB_NAME=$(echo $SECRET | python3 -c "import sys,json; print(json.load(sys.stdin)['dbname'])")

docker pull ${ecr_url}:latest

docker run -d \
  --name app \
  --restart unless-stopped \
  -p 3000:3000 \
  -e DATABASE_URL="postgresql://$DB_USER:$DB_PASS@$DB_HOST:5432/$DB_NAME" \
  -e PORT=3000 \
  ${ecr_url}:latest
