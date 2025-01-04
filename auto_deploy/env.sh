export AWS_DEFAULT_REGION="us-west-2"
export PROJECT_NAME=""
export project_name=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')
export ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
export identity=$(aws sts get-caller-identity --query 'Arn' --output text --no-cli-pager)

if [ -z "$project_name" ]; then
    export CDK_DIR="$HOME/comfyui-on-eks"
    export input_bucket_name="comfyui-inputs-$ACCOUNT_ID-$AWS_DEFAULT_REGION"
    export output_bucket_name="comfyui-outputs-$ACCOUNT_ID-$AWS_DEFAULT_REGION"
    export repo_name="comfyui-images"
else
    export CDK_DIR="$HOME/comfyui-on-eks-$project_name"
    export input_bucket_name="comfyui-inputs-$project_name-$ACCOUNT_ID-$AWS_DEFAULT_REGION"
    export output_bucket_name="comfyui-outputs-$project_name-$ACCOUNT_ID-$AWS_DEFAULT_REGION"
    export repo_name="comfyui-images-$project_name"
fi
