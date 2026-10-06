#!/bin/bash
set -euxo pipefail
dnf install -y docker jq
systemctl enable --now docker
# Wait for the daemon socket to be ready before any docker command.
until docker info >/dev/null 2>&1; do sleep 2; done

aws ecr get-login-password --region ${region} | docker login --username AWS --password-stdin ${ecr_registry}

SECRET=$(aws secretsmanager get-secret-value --region ${region} --secret-id ${db_secret_arn} --query SecretString --output text)
DB_PASS=$(echo "$SECRET" | jq -r .password)

docker run -d --name shortlink --restart always -p 8080:8080 \
  -e PORT=8080 \
  -e BASE_URL=http://${alb_dns} \
  -e DB_HOST=${db_host} -e DB_USER=shortlink -e DB_NAME=shortlink -e DB_SSL=true \
  -e DB_PASSWORD="$DB_PASS" \
  -e REDIS_URL=redis://${redis_host}:6379 \
  ${image}
