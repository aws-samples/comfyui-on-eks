#!/bin/bash

# Exit on any error
set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
RELEASE_NAME=""
DRY_RUN=false

# Function to display usage
usage() {
    echo -e "${BLUE}Usage: $0 -b <buckets-stack-name> -e <ecr-stack-name> -k <karpenter-stack-name> -v <values-file> [-c <chart-path>] [-r <release-name>] [-d]${NC}"
    echo -e "${CYAN}Options:${NC}"
    echo -e "  ${CYAN}-b${NC} : Buckets stack name"
    echo -e "  ${CYAN}-e${NC} : ECR stack name"
    echo -e "  ${CYAN}-k${NC} : Karpenter stack name"
    echo -e "  ${CYAN}-v${NC} : Path to values.yaml file"
    echo -e "  ${CYAN}-c${NC} : Path to Helm chart (required unless -d is specified)"
    echo -e "  ${CYAN}-r${NC} : Release name (optional, will use name from Chart.yaml if not specified)"
    echo -e "  ${CYAN}-d${NC} : Dry run - only update values.yaml without Helm installation"
    exit 1
}

# Parse command line arguments
while getopts "b:e:k:v:c:r:d" opt; do
    case $opt in
        b) BUCKETS_STACK_NAME="$OPTARG";;
        e) ECR_STACK_NAME="$OPTARG";;
        k) KARPENTER_STACK_NAME="$OPTARG";;
        v) VALUES_FILE="$OPTARG";;
        c) CHART_PATH="$OPTARG";;
        r) RELEASE_NAME="$OPTARG";;
        d) DRY_RUN=true;;
        ?) usage;;
    esac
done

# Validate required parameters
if [ -z "$BUCKETS_STACK_NAME" ] || [ -z "$ECR_STACK_NAME" ] || [ -z "$KARPENTER_STACK_NAME" ] || [ -z "$VALUES_FILE" ]; then
    echo -e "${RED}Error: Missing required parameters${NC}"
    usage
fi

# Validate chart path if not in dry-run mode
if [ "$DRY_RUN" = false ] && [ -z "$CHART_PATH" ]; then
    echo -e "${RED}Error: Chart path (-c) is required unless running in dry-run mode (-d)${NC}"
    usage
fi

# Function to get stack output value by key and stack name
get_stack_output() {
    local stack_name=$1
    local key=$2
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --query "Stacks[0].Outputs[?OutputKey=='$key'].OutputValue" \
        --output text
}

# Get bucket names from the buckets stack
echo -e "${BLUE}Retrieving configuration from CloudFormation stacks...${NC}"
INPUTS_BUCKET=$(get_stack_output "$BUCKETS_STACK_NAME" "InputsBucketName")
OUTPUTS_BUCKET=$(get_stack_output "$BUCKETS_STACK_NAME" "OutputsBucketName")
CUSTOM_NODES_BUCKET=$(get_stack_output "$BUCKETS_STACK_NAME" "CustomNodesBucketName")

# Get ECR repo URL from the ECR stack
ECR_REPO_URL=$(get_stack_output "$ECR_STACK_NAME" "RepositoryUrl")

# Get Karpenter node role from the Karpenter stack
KARPENTER_NODE_ROLE=$(get_stack_output "$KARPENTER_STACK_NAME" "KarpenterInstanceNodeRole")

# Check if all required values were retrieved
if [ -z "$INPUTS_BUCKET" ] || [ -z "$OUTPUTS_BUCKET" ] || [ -z "$CUSTOM_NODES_BUCKET" ]; then
    echo -e "${RED}Error: Failed to retrieve all bucket names from stack '$BUCKETS_STACK_NAME'${NC}"
    echo -e "Inputs bucket: ${YELLOW}$INPUTS_BUCKET${NC}"
    echo -e "Outputs bucket: ${YELLOW}$OUTPUTS_BUCKET${NC}"
    echo -e "Custom nodes bucket: ${YELLOW}$CUSTOM_NODES_BUCKET${NC}"
    exit 1
fi

if [ -z "$ECR_REPO_URL" ]; then
    echo -e "${RED}Error: Failed to retrieve ECR repository URL from stack '$ECR_STACK_NAME'${NC}"
    exit 1
fi

if [ -z "$KARPENTER_NODE_ROLE" ]; then
    echo -e "${RED}Error: Failed to retrieve Karpenter node role from stack '$KARPENTER_STACK_NAME'${NC}"
    exit 1
fi

# Check if chart path exists (only if not in dry-run mode)
if [ "$DRY_RUN" = false ] && [ ! -d "$CHART_PATH" ]; then
    echo -e "${RED}Error: Chart directory '$CHART_PATH' does not exist${NC}"
    exit 1
fi

echo -e "${BLUE}Updating values.yaml...${NC}"
# Update values.yaml using yq v4 syntax
yq -i ".volumes[] |= select(.name == \"inputs\").bucketName = \"$INPUTS_BUCKET\"" "$VALUES_FILE"
yq -i ".volumes[] |= select(.name == \"outputs\").bucketName = \"$OUTPUTS_BUCKET\"" "$VALUES_FILE"
yq -i ".volumes[] |= select(.name == \"custom-nodes\").bucketName = \"$CUSTOM_NODES_BUCKET\"" "$VALUES_FILE"
yq -i ".image.repository = \"$ECR_REPO_URL\"" "$VALUES_FILE"
yq -i ".karpenter.role = \"$KARPENTER_NODE_ROLE\"" "$VALUES_FILE"

echo -e "${GREEN}Successfully updated values in $VALUES_FILE:${NC}"
echo -e "${CYAN}Inputs bucket:${NC} $INPUTS_BUCKET"
echo -e "${CYAN}Outputs bucket:${NC} $OUTPUTS_BUCKET"
echo -e "${CYAN}Custom nodes bucket:${NC} $CUSTOM_NODES_BUCKET"
echo -e "${CYAN}ECR Repository URL:${NC} $ECR_REPO_URL"
echo -e "${CYAN}Karpenter Node Role:${NC} $KARPENTER_NODE_ROLE"

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}Dry run mode - values.yaml updated. Skipping Helm installation.${NC}"
    echo -e "${CYAN}Updated values.yaml content:${NC}"
    cat "$VALUES_FILE"
    exit 0
fi

# If no release name provided, get it from Chart.yaml
if [ -z "$RELEASE_NAME" ]; then
    echo -e "${BLUE}No release name provided, checking Chart.yaml...${NC}"
    CHART_YAML="$CHART_PATH/Chart.yaml"
    
    if [ ! -f "$CHART_YAML" ]; then
        echo -e "${RED}Error: Chart.yaml not found at $CHART_YAML${NC}"
        exit 1
    fi
    
    RELEASE_NAME=$(yq eval '.name' "$CHART_YAML")
    
    if [ -z "$RELEASE_NAME" ] || [ "$RELEASE_NAME" = "null" ]; then
        echo -e "${RED}Error: Could not find 'name' in Chart.yaml${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Using release name from Chart.yaml: $RELEASE_NAME${NC}"
fi

echo -e "${CYAN}Release name:${NC} $RELEASE_NAME"

# Validate the helm chart
echo -e "${BLUE}Validating Helm chart...${NC}"
helm lint "$CHART_PATH" -f "$VALUES_FILE"

# Install/upgrade the helm chart
echo -e "${BLUE}Installing/upgrading Helm chart with release name '$RELEASE_NAME'...${NC}"
helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" \
    -f "$VALUES_FILE" \
    --wait \
    --timeout 10m \
    --create-namespace \
    --debug

# Check the status of the release
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully installed/upgraded release '$RELEASE_NAME'${NC}"
    echo -e "${BLUE}Checking release status...${NC}"
    helm status "$RELEASE_NAME"
else
    echo -e "${RED}Failed to install/upgrade release '$RELEASE_NAME'${NC}"
    exit 1
fi


# You can now run the script in these ways:
# 1. With explicit release name (overrides Chart.yaml):

# ./helm_deploy.sh \
#     -b my-buckets-stack \
#     -e my-ecr-stack \
#     -k my-k8s-stack \
#     -v ./values.yaml \
#     -c ./chart \
#     -r comfyui

# 2. Without release name (uses name from Chart.yaml):
# ./helm_deploy.sh \
#     -b my-buckets-stack \
#     -e my-ecr-stack \
#     -k my-k8s-stack \
#     -v ./values.yaml \
#     -c ./chart

# 3. Dry run mode:
# ./helm_deploy.sh \
#     -b my-buckets-stack \
#     -e my-ecr-stack \
#     -k my-k8s-stack \
#     -v ./values.yaml \
#     -d

# ./helm_deploy.sh \
#     -b S3Storage \
#     -e ComfyuiEcrRepo \
#     -k Comfyui-Cluster \
#     -v ./chart/values.yaml \
#     -d

# ./helm_deploy.sh \
#     -b S3Storage \
#     -e ComfyuiEcrRepo \
#     -k Comfyui-Cluster \
#     -v ../chart/values.yaml \
#     -c ../chart