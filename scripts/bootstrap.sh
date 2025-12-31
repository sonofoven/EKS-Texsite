#!/bin/sh

cd ..

echo "\n<< PROVISIONING DEPENDENCIES >>\n"

# Setup cluster & ecr
cd terraform
terraform init
terraform apply -auto-approve

ECR_REPOSITORY_URL=$(terraform output -raw ecr_repository_url)
AWS_REGION=$(terraform output -raw aws_region)
EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
EKS_ROLE_ARN=$(terraform output -raw eks_role_arn)
REPO_MONITOR_ROLE_ARN=$(terraform output -raw repo_monitor_role_arn)

# Building latex file
echo "\n<< CONVERTING LATEX RESUME TO HTML5 >>\n"
cd ../scripts
./resume2html.sh

# Push initial image to ecr
echo "\n<< BUILDING AND PUSHING IMAGE >>\n"
./pushImage.sh $ECR_REPOSITORY_URL $AWS_REGION
cd ..

# Configure kubectl
echo "\n<< UPDATING KUBECTL TO INTERACT W/ CLUSTER >>\n"
aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER_NAME --role-arn $EKS_ROLE_ARN

echo "\n<< INSTALLING FLUX >>\n"

GITHUB_INFO=$(gh repo view --json owner,name -q '.owner.login + "/" + .name')
GITHUB_OWNER=$(echo "$GITHUB_INFO" | cut -d '/' -f1)
GITHUB_REPO=$(echo "$GITHUB_INFO" | cut -d '/' -f2)

GITHUB_TOKEN=$(gh auth token) \
flux bootstrap github \
  --token-auth \
  --owner=$GITHUB_OWNER \
  --repository=$GITHUB_REPO \
  --branch=main \
  --path=./cluster/flux-system \
  --personal \
  --components-extra=image-reflector-controller,image-automation-controller

kubectl -n flux-system annotate serviceaccount image-reflector-controller \
        eks.amazonaws.com/role-arn=$(REPO_MONITOR_ROLE_ARN)
kubectl -n flux-system rollout restart deployment image-reflector-controller

cd cluster/apps

# Generate ecr source repository for use with flux image reflector
ECR_REPOSITORY_URL="$ECR_REPOSITORY_URL" \
envsubst < nginx-repo.yml.tmpl > nginx-repo.yml
ECR_REPOSITORY_URL="$ECR_REPOSITORY_URL" \
envsubst < nginx-deployment.yml.tmpl > nginx-deployment.yml


# Store bootstrap gh variables
echo "ECR_REPOSITORY_URL=$ECR_REPOSITORY_URL"
echo "AWS_REGION=$AWS_REGION"
echo "EKS_CLUSTER_NAME=$EKS_CLUSTER_NAME"
echo "EKS_ROLE_ARN=$EKS_ROLE_ARN"

echo "\n<< STORING BOOTSTRAP VARS >>\n"
gh variable set ECR_REPOSITORY --body "$ECR_REPOSITORY_URL"
gh variable set AWS_REGION --body "$AWS_REGION"
gh variable set EKS_CLUSTER_NAME --body "$EKS_CLUSTER_NAME"
gh variable set EKS_ROLE_ARN --body "$EKS_ROLE_ARN"
