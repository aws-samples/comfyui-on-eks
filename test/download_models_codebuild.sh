#!/bin/bash

# Trigger CodeBuild to download models from HuggingFace to S3
# Usage: download_models_codebuild.sh <region> [profile] [tier]
# tier: "tier1" (essentials only) or "all" (default)

if [ -z "$1" ]; then
  echo "Usage: download_models_codebuild.sh <region> [profile] [tier]"
  exit 1
fi

REGION=$1
PROFILE=${2:-default}
MODEL_TIER=${3:-all}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile "$PROFILE")
S3_BUCKET="comfyui-models-${ACCOUNT_ID}-${REGION}"
S3_KEY="codebuild/comfyui-models-source.zip"

echo "Region: $REGION, Tier: $MODEL_TIER, Bucket: $S3_BUCKET"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_ZIP=$(mktemp /tmp/comfyui-models-build-XXXXXX)
rm -f "$TEMP_ZIP"
TEMP_ZIP="${TEMP_ZIP}.zip"
cd "$SCRIPT_DIR" && zip -r "$TEMP_ZIP" buildspec_models.yml

echo "Uploading buildspec to s3://${S3_BUCKET}/${S3_KEY}..."
aws s3 cp "$TEMP_ZIP" "s3://${S3_BUCKET}/${S3_KEY}" --region "$REGION" --profile "$PROFILE"
rm -f "$TEMP_ZIP"

echo "Starting CodeBuild model download (tier: $MODEL_TIER)..."
BUILD_ID=$(aws codebuild start-build \
  --project-name comfyui-model-download \
  --source-type-override S3 \
  --source-location-override "${S3_BUCKET}/${S3_KEY}" \
  --buildspec-override "buildspec_models.yml" \
  --environment-variables-override \
    "name=MODELS_BUCKET,value=${S3_BUCKET},type=PLAINTEXT" \
    "name=MODEL_TIER,value=${MODEL_TIER},type=PLAINTEXT" \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'build.id' --output text)

if [ $? -ne 0 ] || [ -z "$BUILD_ID" ]; then
  echo "Failed to start CodeBuild job"
  exit 1
fi

echo "Build started: $BUILD_ID"
echo "Waiting for build to complete..."

while true; do
  STATUS=$(aws codebuild batch-get-builds --ids "$BUILD_ID" \
    --region "$REGION" --profile "$PROFILE" \
    --query 'builds[0].buildStatus' --output text)

  if [ "$STATUS" = "SUCCEEDED" ]; then
    echo "Model download SUCCEEDED!"
    exit 0
  elif [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "FAULT" ] || [ "$STATUS" = "STOPPED" ] || [ "$STATUS" = "TIMED_OUT" ]; then
    echo "Model download FAILED with status: $STATUS"
    echo "Check logs: aws codebuild batch-get-builds --ids $BUILD_ID --region $REGION --profile $PROFILE"
    exit 1
  fi

  PHASE=$(aws codebuild batch-get-builds --ids "$BUILD_ID" \
    --region "$REGION" --profile "$PROFILE" \
    --query 'builds[0].currentPhase' --output text)
  echo "  Status: $STATUS, Phase: $PHASE"
  sleep 30
done
