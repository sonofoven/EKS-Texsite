#!/bin/sh

ECR_REPOSITORY_URL="$1"
AWS_REGION="$2"
ECR_REGISTRY_ID=$(echo "$ECR_REPOSITORY_URL" | cut -d '/' -f 1)

cd ../pySrc

# Login to ECR registry
aws ecr get-login-password --region ${AWS_REGION} \
  | docker login \
      --username AWS \
      --password-stdin \
      "$ECR_REGISTRY_ID"

# Build
docker buildx build --platform linux/amd64 \
  --provenance=false \
  -t "${ECR_REPOSITORY_URL}:latest" \
  --push \
  .
