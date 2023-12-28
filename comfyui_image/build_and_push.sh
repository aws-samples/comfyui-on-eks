#!/bin/bash

# Build and push ComfyUI image to ECR

if [ -z "$1" ]
  then
    echo "Usage: build_and_push.sh <region>"
    exit 1
fi

REGION=$1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "AccountID: $ACCOUNT_ID, Region: $REGION"

docker build --platform="linux/amd64" . -t comfyui-images
docker tag comfyui-images:latest ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/comfyui-images:latest
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/comfyui-images:latest

docker images|grep none|awk '{print $3}'|xargs -I {} docker rmi -f {}
