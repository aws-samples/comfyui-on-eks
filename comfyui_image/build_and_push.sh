#!/bin/bash

# Build and push ComfyUI image to ECR using AWS CodeBuild

if [ -z "$1" ]; then
  echo "Usage: build_and_push.sh <region> [profile]"
  exit 1
fi

REGION=$1
PROFILE=${2:-default}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile "$PROFILE")
REPO_NAME="comfyui-images"
S3_BUCKET="comfyui-models-${ACCOUNT_ID}-${REGION}"
S3_KEY="codebuild/comfyui-build-source.zip"

echo "AccountID: $ACCOUNT_ID, Region: $REGION, Repo: $REPO_NAME"
echo "Building via AWS CodeBuild..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_ZIP=$(mktemp /tmp/comfyui-build-XXXXXX)
rm -f "$TEMP_ZIP"
TEMP_ZIP="${TEMP_ZIP}.zip"
cd "$SCRIPT_DIR" && zip -r "$TEMP_ZIP" Dockerfile buildspec.yml custom_nodes/ -x "*__pycache__*"
if [ ! -s "$TEMP_ZIP" ]; then
  echo "FATAL: source archive $TEMP_ZIP is missing or empty (is 'zip' installed?)."
  exit 1
fi

echo "Uploading source to s3://${S3_BUCKET}/${S3_KEY}..."
aws s3 cp "$TEMP_ZIP" "s3://${S3_BUCKET}/${S3_KEY}" --region "$REGION" --profile "$PROFILE"
rm -f "$TEMP_ZIP"

echo "Starting CodeBuild..."
BUILD_ID=$(aws codebuild start-build \
  --project-name comfyui-image-build \
  --source-type-override S3 \
  --source-location-override "${S3_BUCKET}/${S3_KEY}" \
  --environment-variables-override "name=IMAGE_REPO_NAME,value=${REPO_NAME},type=PLAINTEXT" "name=AWS_DEFAULT_REGION,value=${REGION},type=PLAINTEXT" "name=AWS_ACCOUNT_ID,value=${ACCOUNT_ID},type=PLAINTEXT" \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'build.id' --output text)

if [ -z "$BUILD_ID" ] || [ "$BUILD_ID" = "None" ]; then
  echo "FATAL: failed to start CodeBuild (empty build id) — check the project name and credentials."
  exit 1
fi

echo "Build started: $BUILD_ID"
echo "Waiting for build to complete..."

while true; do
  STATUS=$(aws codebuild batch-get-builds --ids "$BUILD_ID" \
    --region "$REGION" --profile "$PROFILE" \
    --query 'builds[0].buildStatus' --output text)

  if [ "$STATUS" = "SUCCEEDED" ]; then
    echo "Build SUCCEEDED! Image pushed to ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:latest"
    exit 0
  elif [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "FAULT" ] || [ "$STATUS" = "STOPPED" ] || [ "$STATUS" = "TIMED_OUT" ]; then
    echo "Build FAILED with status: $STATUS"
    echo "Check logs: aws codebuild batch-get-builds --ids $BUILD_ID --region $REGION --profile $PROFILE"
    exit 1
  fi

  PHASE=$(aws codebuild batch-get-builds --ids "$BUILD_ID" \
    --region "$REGION" --profile "$PROFILE" \
    --query 'builds[0].currentPhase' --output text)
  echo "  Status: $STATUS, Phase: $PHASE"
  sleep 30
done
