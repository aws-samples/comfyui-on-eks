#!/bin/bash

# Build and push ComfyUI image to ECR

if [[ -z "$1" || -z "$2" ]]
then
    echo "Usage: build_and_push.sh <region> <Dockerfile>"
    exit 1
fi

TAG=latest
REGION=$1
Dockerfile=$2

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "AccountID: $ACCOUNT_ID, Region: $REGION"

docker build --platform="linux/amd64" -f $Dockerfile . -t comfyui-images --no-cache

docker tag comfyui-images:${TAG} ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/comfyui-images:${TAG}
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/comfyui-images:${TAG}

docker images|grep none|awk '{print $3}'|xargs -I {} docker rmi -f {}
