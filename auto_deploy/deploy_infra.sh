#!/bin/bash

source ./env.sh

get_stacks_names() {
    echo "==== Start getting CloudFormation Stacks ===="
    all_stacks=$(cd $CDK_DIR && cdk list)
    export EKS_CLUSTER_STACK=$(echo $all_stacks|grep -o "ComfyUI-on-EKS-Cluster[^ ]*")
    export LAMBDA_STACK=$(echo $all_stacks|grep -o "ComfyUI-on-EKS-Models[^ ]*")
    export S3_STACK=$(echo $all_stacks|grep -o "ComfyUI-on-EKS-S3[^ ]*")
    export ECR_STACK=$(echo $all_stacks|grep -o "ComfyUI-on-EKS-ECR[^ ]*")
    export CLOUDFRONT_STACK=$(echo $all_stacks|grep -o "ComfyUI-on-EKS-CloudFront[^ ]*")
    echo "EKS_CLUSTER_STACK : $EKS_CLUSTER_STACK"
    echo "LAMBDA_STACK      : $LAMBDA_STACK"
    echo "S3_STACK          : $S3_STACK"
    echo "ECR_STACK         : $ECR_STACK"
    echo "CLOUDFRONT_STACK  : $CLOUDFRONT_STACK"
    echo "==== Finish getting CloudFormation Stacks ===="
}

cdk_deploy_eks_cluster() {
    echo "==== Start deploying EKS Cluster ===="
    cd $CDK_DIR && cdk deploy $EKS_CLUSTER_STACK --require-approval never
    if [ $? -ne 0 ]; then
        echo "CDK deploy failed"
        exit 1
    fi
    echo "==== Finish deploying EKS Cluster ===="
}

prepare_eks_env() {
    echo "==== Start preparing EKS environment ===="

    # Configure kubectl
    ComfyuiClusterConfigCommand=$(aws cloudformation describe-stacks --stack-name $EKS_CLUSTER_STACK --query "Stacks[0].Outputs[?starts_with(OutputKey, 'ComfyuiCluster') && contains(OutputKey, 'ConfigCommand')].OutputValue" --output text)
    eval $ComfyuiClusterConfigCommand
    kubectl get svc &> /dev/null
    if [ $? -ne 0 ]; then
        echo "EKS environment is not ready via CDK admin role, configuring access entry..."
    fi

    # Enable API auth mode so we can add access entries
    authenticationMode=$(aws eks describe-cluster --name $EKS_CLUSTER_STACK --query 'cluster.accessConfig.authenticationMode' --output text)
    if [ "$authenticationMode" != "API_AND_CONFIG_MAP" ]; then
        echo "Updating authentication mode to API_AND_CONFIG_MAP..."
        aws eks update-cluster-config --name $EKS_CLUSTER_STACK --access-config authenticationMode=API_AND_CONFIG_MAP
        while [ "$authenticationMode" != "API_AND_CONFIG_MAP" ]; do
            echo "  Waiting for auth mode update... current: $authenticationMode"
            sleep 10
            authenticationMode=$(aws eks describe-cluster --name $EKS_CLUSTER_STACK --query 'cluster.accessConfig.authenticationMode' --output text)
        done
    fi
    echo "authenticationMode=API_AND_CONFIG_MAP is ready"

    # Add current caller as cluster admin
    identity=$(aws sts get-caller-identity --query 'Arn' --output text --no-cli-pager)
    if [[ $identity == *"assumed-role"* ]]; then
        role_name=$(echo $identity | cut -d'/' -f2)
        account_id=$(echo $identity | cut -d':' -f5)
        identity="arn:aws:iam::$account_id:role/$role_name"
    fi
    echo "Adding access entry for: $identity"
    aws eks create-access-entry --cluster-name $EKS_CLUSTER_STACK --principal-arn $identity --type STANDARD --username comfyui-user 2>/dev/null || true
    aws eks associate-access-policy --cluster-name $EKS_CLUSTER_STACK --principal-arn $identity --access-scope type=cluster --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy 2>/dev/null || true

    # Verify kubectl works
    kubectl get svc &> /dev/null
    if [ $? -eq 0 ]; then
        echo "EKS environment is ready"
    else
        echo "EKS environment is not ready after access entry creation"
        exit 1
    fi
    echo "==== Finish preparing EKS environment ===="
}

cdk_deploy_lambda() {
    echo "==== Start deploying Models (Lambda + S3) ===="
    cd $CDK_DIR && cdk deploy $LAMBDA_STACK --require-approval never
    if [ $? -ne 0 ]; then
        echo "Lambda deploy failed"
        exit 1
    fi
    echo "==== Finish deploying Models ===="
}

cdk_deploy_s3() {
    echo "==== Start deploying S3 Storage ===="
    cd $CDK_DIR && cdk deploy $S3_STACK --require-approval never
    if [ $? -ne 0 ]; then
        echo "S3 deploy failed"
        exit 1
    fi
    echo "==== Finish deploying S3 Storage ===="
}

upload_models_to_s3_tier1() {
    echo "==== Start downloading Tier 1 models via CodeBuild ===="
    cd $CDK_DIR/test && bash download_models_codebuild.sh $AWS_DEFAULT_REGION $AWS_PROFILE tier1
    if [ $? -ne 0 ]; then
        echo "Tier 1 model download failed - falling back to local download"
        cd $CDK_DIR/test && bash init_s3_for_models.sh $AWS_DEFAULT_REGION
    fi
    echo "==== Finish downloading Tier 1 models ===="
}

upload_models_to_s3_all() {
    echo "==== Start downloading all models via CodeBuild (background) ===="
    cd $CDK_DIR/test && bash download_models_codebuild.sh $AWS_DEFAULT_REGION $AWS_PROFILE all &
    echo "==== All models downloading in background ===="
}

cdk_deploy_ecr() {
    echo "==== Start deploying ECR + CodeBuild ===="
    cd $CDK_DIR && cdk deploy $ECR_STACK --require-approval never
    if [ $? -ne 0 ]; then
        echo "ECR deploy failed"
        exit 1
    fi
    echo "==== Finish deploying ECR + CodeBuild ===="
}

build_and_push_comfyui_image() {
    echo "==== Start building and pushing ComfyUI image ===="
    cd $CDK_DIR/comfyui_image && bash build_and_push.sh $AWS_DEFAULT_REGION $AWS_PROFILE
    if [ $? -ne 0 ]; then
        echo "ComfyUI image build and push failed"
        exit 1
    fi
    echo "==== Finish building and pushing ComfyUI image ===="
}

deploy_karpenter() {
    echo "==== Start deploying Karpenter ===="
    kubectl delete -f $CDK_DIR/manifests/Karpenter/karpenter_v1.yaml --ignore-not-found
    KarpenterInstanceNodeRole=$(aws cloudformation describe-stacks --stack-name $EKS_CLUSTER_STACK --query 'Stacks[0].Outputs[?OutputKey==`KarpenterInstanceNodeRole`].OutputValue' --output text)
    sg_tag="eks-cluster-sg-ComfyUI-on-EKS-Cluster*"
    subnet_tag="ComfyUI-on-EKS-Cluster\/ComfyuiVPC\/private*"

    if [ -z "$KarpenterInstanceNodeRole" ]; then
        echo "KarpenterInstanceNodeRole is not set"
        exit 1
    fi

    echo "KarpenterInstanceNodeRole            : $KarpenterInstanceNodeRole"
    echo "securityGroupSelectorTerms tags Name : $sg_tag"
    echo "subnetSelectorTerms tags Name        : $subnet_tag"

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sed -i "s/role: .*/role: $KarpenterInstanceNodeRole/g" $CDK_DIR/manifests/Karpenter/karpenter_v1.yaml
        sed -i "s/Name: eks-cluster-sg-ComfyUI-on-EKS-Cluster.*/Name: $sg_tag/g" $CDK_DIR/manifests/Karpenter/karpenter_v1.yaml
        sed -i "s/Name: ComfyUI-on-EKS-Cluster\/ComfyuiVPC\/private.*/Name: $subnet_tag/g" $CDK_DIR/manifests/Karpenter/karpenter_v1.yaml
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/role: .*/role: $KarpenterInstanceNodeRole/g" $CDK_DIR/manifests/Karpenter/karpenter_v1.yaml
        sed -i '' "s/Name: eks-cluster-sg-ComfyUI-on-EKS-Cluster.*/Name: $sg_tag/g" $CDK_DIR/manifests/Karpenter/karpenter_v1.yaml
        sed -i '' "s/Name: ComfyUI-on-EKS-Cluster\/ComfyuiVPC\/private.*/Name: $subnet_tag/g" $CDK_DIR/manifests/Karpenter/karpenter_v1.yaml
    else
        echo "Unsupported OS: $OSTYPE"
        exit 1
    fi

    kubectl apply -f $CDK_DIR/manifests/Karpenter/karpenter_v1.yaml
    aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess --role-name $KarpenterInstanceNodeRole
    aws iam put-role-policy --role-name $KarpenterInstanceNodeRole --policy-name BedrockInvokeAccess --policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Action": ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream", "bedrock:StartAsyncInvoke", "bedrock:GetAsyncInvoke"],
            "Resource": [
                "arn:aws:bedrock:*::foundation-model/*",
                "arn:aws:bedrock:*:*:inference-profile/*"
            ]
        }]
    }'
    echo "==== Finish deploying Karpenter ===="
}

deploy_s3_pv_pvc() {
    echo "==== Start deploying S3 PV/PVC ===="
    kubectl delete -f $CDK_DIR/manifests/PersistentVolume/ --ignore-not-found
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sed -i "s/REGION/$AWS_DEFAULT_REGION/g" $CDK_DIR/manifests/PersistentVolume/sd-outputs-s3.yaml
        sed -i "s/REGION/$AWS_DEFAULT_REGION/g" $CDK_DIR/manifests/PersistentVolume/sd-inputs-s3.yaml
        sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" $CDK_DIR/manifests/PersistentVolume/sd-outputs-s3.yaml
        sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" $CDK_DIR/manifests/PersistentVolume/sd-inputs-s3.yaml
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/REGION/$AWS_DEFAULT_REGION/g" $CDK_DIR/manifests/PersistentVolume/sd-outputs-s3.yaml
        sed -i '' "s/REGION/$AWS_DEFAULT_REGION/g" $CDK_DIR/manifests/PersistentVolume/sd-inputs-s3.yaml
        sed -i '' "s/ACCOUNT_ID/$ACCOUNT_ID/g" $CDK_DIR/manifests/PersistentVolume/sd-outputs-s3.yaml
        sed -i '' "s/ACCOUNT_ID/$ACCOUNT_ID/g" $CDK_DIR/manifests/PersistentVolume/sd-inputs-s3.yaml
    else
        echo "Unsupported OS: $OSTYPE"
        exit 1
    fi
    kubectl apply -f $CDK_DIR/manifests/PersistentVolume/
    if [ $? -ne 0 ]; then
        echo "S3 PV/PVC deploy failed"
        exit 1
    fi
    echo "==== Finish deploying S3 PV/PVC ===="
}

deploy_s3_csi_driver() {
    echo "==== Start deploying S3 CSI Driver ===="
    ROLE_NAME=EKS-S3-CSI-DriverRole-$ACCOUNT_ID-$AWS_DEFAULT_REGION
    POLICY_ARN=arn:aws:iam::aws:policy/AmazonS3FullAccess
    eksctl create iamserviceaccount \
        --name s3-csi-driver-sa \
        --namespace kube-system \
        --cluster $EKS_CLUSTER_STACK \
        --attach-policy-arn $POLICY_ARN \
        --approve \
        --role-name $ROLE_NAME \
        --region $AWS_DEFAULT_REGION \
        --override-existing-serviceaccounts
    eksctl create addon --name aws-mountpoint-s3-csi-driver --version v2.5.0-eksbuild.1 --cluster $EKS_CLUSTER_STACK --service-account-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/EKS-S3-CSI-DriverRole-${ACCOUNT_ID}-${AWS_DEFAULT_REGION}" --force
    if [ $? -ne 0 ]; then
        echo "S3 CSI Driver deploy failed"
        exit 1
    fi
    echo "==== Finish deploying S3 CSI Driver ===="
}

deploy_comfyui() {
    echo "==== Start deploying ComfyUI ===="
    kubectl delete -f $CDK_DIR/manifests/ComfyUI/ --ignore-not-found
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" $CDK_DIR/manifests/ComfyUI/comfyui_deployment.yaml
        sed -i "s/REGION/$AWS_DEFAULT_REGION/g" $CDK_DIR/manifests/ComfyUI/comfyui_deployment.yaml
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/ACCOUNT_ID/$ACCOUNT_ID/g" $CDK_DIR/manifests/ComfyUI/comfyui_deployment.yaml
        sed -i '' "s/REGION/$AWS_DEFAULT_REGION/g" $CDK_DIR/manifests/ComfyUI/comfyui_deployment.yaml
    else
        echo "Unsupported OS: $OSTYPE"
        exit 1
    fi
    kubectl apply -f $CDK_DIR/manifests/ComfyUI/
    if [ $? -ne 0 ]; then
        echo "ComfyUI deploy failed"
        exit 1
    fi
    echo "==== Finish deploying ComfyUI ===="
}

wait_for_comfyui_ready() {
    echo "==== Waiting for ComfyUI pod to be ready ===="
    i=0
    while [ "$(kubectl get pods -l app=comfyui -o jsonpath='{.items[0].status.phase}' 2>/dev/null)" != "Running" ]; do
        if [ $i -gt 360 ]; then
            echo "ComfyUI pod is not ready after 30min"
            exit 1
        fi
        echo "  ComfyUI pod not ready yet, waiting... (${i}s)"
        sleep 5
        i=$((i+5))
    done
    echo "ComfyUI pod is running"
    echo "==== ComfyUI is ready ===="
}

cdk_deploy_cloudfront() {
    echo "==== Start deploying CloudFront ===="
    cd $CDK_DIR && cdk deploy $CLOUDFRONT_STACK --require-approval never
    if [ $? -ne 0 ]; then
        echo "CloudFront deploy failed"
        exit 1
    fi
    CLOUDFRONT_URL=$(aws cloudformation describe-stacks --stack-name $CLOUDFRONT_STACK --query "Stacks[0].Outputs[?contains(OutputKey, 'DistributionDomain') || contains(OutputKey, 'CloudFront')].OutputValue" --output text 2>/dev/null)
    echo "CloudFront URL: https://$CLOUDFRONT_URL"
    echo "==== Finish deploying CloudFront ===="
}

# ====== Activate NVM & CDK ====== #
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# ====== Deploy all stacks in order ====== #
start_time=$(date +%s)
get_stacks_names
cdk_deploy_eks_cluster
prepare_eks_env
cdk_deploy_lambda
cdk_deploy_s3
cdk_deploy_ecr
upload_models_to_s3_tier1
upload_models_to_s3_all
build_and_push_comfyui_image
deploy_karpenter
deploy_s3_pv_pvc
deploy_s3_csi_driver
deploy_comfyui
wait_for_comfyui_ready
cdk_deploy_cloudfront
end_time=$(date +%s)
elapsed=$((end_time-start_time))
echo ""
echo "=========================================="
echo "  Deployment complete! (${elapsed}s)"
echo "=========================================="
echo ""
echo "Access ComfyUI via the CloudFront URL above."
echo "Note: Enable Bedrock model access in the console for the models you want to use."
