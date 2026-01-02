#!/bin/sh

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "\n<< PROVISIONING DEPENDENCIES >>\n"

# Setup cluster & ecr
cd "$REPO_ROOT/terraform"
terraform init
terraform apply -auto-approve

ECR_REPOSITORY_URL=$(terraform output -raw ecr_repository_url)
AWS_REGION=$(terraform output -raw aws_region)
EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
EKS_ROLE_ARN=$(terraform output -raw eks_role_arn)
REPO_MONITOR_ROLE_ARN=$(terraform output -raw repo_monitor_role_arn)
ALB_ROLE_ARN=$(terraform output -raw alb_role_arn)
VPC_ID=$(terraform output -raw vpc_id)

ECR_REGISTRY_ID=$(echo "$ECR_REPOSITORY_URL" | cut -d '/' -f1)

# Building latex file
echo "\n<< CONVERTING LATEX RESUME TO HTML5 >>\n"
cd "$REPO_ROOT/scripts"
./resume2html.sh

# Push initial image to ecr
echo "\n<< BUILDING AND PUSHING IMAGE >>\n"

cd "$REPO_ROOT/nginx"

# Login to ECR registry
aws ecr get-login-password --region $AWS_REGION \
  | docker login \
      --username AWS \
      --password-stdin \
      "$ECR_REGISTRY_ID"

# Build
docker buildx build --platform linux/amd64 \
  --provenance=false \
  -t "${ECR_REPOSITORY_URL}:00000000-000000" \
  --push \
  .


cd "$REPO_ROOT"

# Configure kubectl
echo "\n<< UPDATING KUBECTL TO INTERACT W/ CLUSTER >>\n"
aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER_NAME --role-arn $EKS_ROLE_ARN

echo "\n<< INSTALLING FLUX >>\n"

GITHUB_INFO=$(gh repo view --json owner,name -q '.owner.login + "/" + .name')
GITHUB_OWNER=$(echo "$GITHUB_INFO" | cut -d '/' -f1)
GITHUB_REPO=$(echo "$GITHUB_INFO" | cut -d '/' -f2)

GITHUB_TOKEN=$(gh auth token) \

cd "$REPO_ROOT/cluster/apps/nginx/templates"

# Generate ecr source repository for use with flux image reflector
ECR_REPOSITORY_URL="$ECR_REPOSITORY_URL" \
envsubst < nginx-repo.yml.tmpl > ../nginx-repo.yml

ECR_REPOSITORY_URL="$ECR_REPOSITORY_URL" \
envsubst '${ECR_REPOSITORY_URL}' < nginx-deployment.yml.tmpl > ../nginx-deployment.yml

cd "$REPO_ROOT/cluster/infra/templates"
EKS_CLUSTER_NAME="$EKS_CLUSTER_NAME" \
AWS_REGION="$AWS_REGION" \
VPC_ID="$VPC_ID" \
envsubst < alb-controller.yml.tmpl > ../alb-controller.yml

ALB_ROLE_ARN="$ALB_ROLE_ARN" \
envsubst < alb-service-acc.yml.tmpl > ../alb-service-acc.yml

cd "$REPO_ROOT/cluster/flux-system/templates"
REPO_MONITOR_ROLE_ARN="$REPO_MONITOR_ROLE_ARN" \
envsubst < kustomization.yml.tmpl > ../kustomization.yaml

cd "$REPO_ROOT"

git pull
git add .
git commit -m "Bootstrapping"
git push origin main

flux bootstrap github \
  --token-auth \
  --owner=$GITHUB_OWNER \
  --repository=$GITHUB_REPO \
  --branch=main \
  --path=cluster \
  --personal \
  --components-extra=image-reflector-controller,image-automation-controller

kubectl -n flux-system annotate serviceaccount image-reflector-controller \
        eks.amazonaws.com/role-arn=${REPO_MONITOR_ROLE_ARN} \
        --overwrite
kubectl -n flux-system rollout restart deployment image-reflector-controller

echo "ECR_REPOSITORY_URL=$ECR_REPOSITORY_URL"
echo "AWS_REGION=$AWS_REGION"

echo "\n<< STORING BOOTSTRAP VARS >>\n"
gh variable set ECR_REPOSITORY --body "$ECR_REPOSITORY_URL"
gh variable set AWS_REGION --body "$AWS_REGION"
