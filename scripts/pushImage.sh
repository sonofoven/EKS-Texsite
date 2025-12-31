#!/bin/sh

ECR_REPOSITORY_URL="$1"
AWS_REGION="$2"
ECR_REGISTRY_ID=$(echo "$ECR_REPOSITORY_URL" | cut -d '/' -f 1)

cd ../nginx

# Login to ECR registry
aws ecr get-login-password --region ${AWS_REGION} \
  | docker login \
      --username AWS \
      --password-stdin \
      "$ECR_REGISTRY_ID"

TIME_TAG=$(date -u +"%Y%m%d-%H%M%S")

# Build
docker buildx build --platform linux/amd64 \
  --provenance=false \
  -t "${ECR_REPOSITORY_URL}:${TIME_TAG}" \
  --push \
  .
