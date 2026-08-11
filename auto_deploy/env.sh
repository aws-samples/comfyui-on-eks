export AWS_PROFILE="${AWS_PROFILE:-default}"
export AWS_DEFAULT_REGION="us-west-2"
export ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text 2> /dev/null)
export identity=$(aws sts get-caller-identity --query 'Arn' --output text --no-cli-pager 2> /dev/null)
export PROJECT_TAG="comfyui-on-eks"

export CDK_DEFAULT_ACCOUNT="$ACCOUNT_ID"
export CDK_DEFAULT_REGION="$AWS_DEFAULT_REGION"

export CDK_DIR="$HOME/comfyui-on-eks"
export input_bucket_name="comfyui-inputs-$ACCOUNT_ID-$AWS_DEFAULT_REGION"
export output_bucket_name="comfyui-outputs-$ACCOUNT_ID-$AWS_DEFAULT_REGION"
export repo_name="comfyui-images"
