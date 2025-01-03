#!/bin/bash

# Build and push ComfyUI image to ECR

if [ -z "$1" ]
  then
    echo "Usage: build_and_push.sh <region>"
    exit 1
fi

REGION=$1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
PROJECT_NAME=$(node -e "const { PROJECT_NAME } = require('../env.ts'); console.log(PROJECT_NAME);" 2> /dev/null)
project_name=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')
repo_name="comfyui-images${project_name:+-$project_name}"

TAG="latest"
echo "AccountID: $ACCOUNT_ID, Region: $REGION, Project: $project_name, Repo: $repo_name"

sudo docker build --platform="linux/amd64" . -t comfyui-images:$TAG
sudo docker tag comfyui-images:$TAG ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${repo_name}:$TAG
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com
sudo docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${repo_name}:$TAG

sudo docker images|grep none|awk '{print $3}'|xargs -I {} docker rmi -f {}