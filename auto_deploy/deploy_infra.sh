#!/bin/bash

source ./env.sh

get_stacks_names() {
    echo "==== Start getting CloudFormation Stacks ===="
    all_stacks=$(cd $CDK_DIR && cdk list)
    export EKS_CLUSTER_STACK=$(echo $all_stacks|grep -o "Comfyui-Cluster[^ ]*")
    export LAMBDA_STACK=$(echo $all_stacks|grep -o "LambdaModelsSync[^ ]*")
    export S3_STACK=$(echo $all_stacks|grep -o "S3Storage[^ ]*")
    export ECR_STACK=$(echo $all_stacks|grep -o "ComfyuiEcrRepo[^ ]*")
    export CLOUDFRONT_STACK=$(echo $all_stacks|grep -o "CloudFrontEntry[^ ]*")
    # Print more pretty
    echo "EKS_CLUSTER_STACK : $EKS_CLUSTER_STACK"
    echo "LAMBDA_STACK      : $LAMBDA_STACK"
    echo "S3_STACK          : $S3_STACK"
    echo "ECR_STACK         : $ECR_STACK"
    echo "CLOUDFRONT_STACK  : $CLOUDFRONT_STACK"
    echo "==== Finish getting CloudFormation Stacks ===="
}

# Deploy EKS Cluster
cdk_deploy_eks_cluster() {
    echo "==== Start deploying EKS Cluster ===="
    cd $CDK_DIR && cdk deploy $EKS_CLUSTER_STACK --require-approval never
    if [ $? -eq 0 ]; then
        echo "EKS deploy completed successfully"
    else
        echo "CDK deploy failed"
        exit 1
    fi
    echo "==== Finish deploying EKS Cluster ===="
}

prepare_eks_env() {
    echo "==== Start preparing EKS environment ===="
    ComfyuiClusterConfigCommand=$(aws cloudformation describe-stacks --stack-name $EKS_CLUSTER_STACK --query "Stacks[0].Outputs[?starts_with(OutputKey, 'ComfyuiCluster') && contains(OutputKey, 'ConfigCommand')].OutputValue" --output text)
    eval $ComfyuiClusterConfigCommand
    kubectl get svc &> /dev/null
    if [ $? -eq 0 ]; then
        echo "EKS environment is ready"
    else
        echo "EKS environment is not ready"
        exit 1
    fi
    echo "==== Finish preparing EKS environment ===="
}

cdk_deploy_lambda() {
    echo "==== Start deploying LambdaModelsSync ===="

    if [ -z "$PROJECT_NAME" ]; then
        cluster_name="Comfyui-Cluster"
    else
        cluster_name="Comfyui-Cluster-${PROJECT_NAME}"
    fi

    sed -i "s/'Values': \['Comfyui-Cluster.*'\]/'Values': \['$cluster_name'\]/g" $CDK_DIR/lib/ComfyModelsSyncLambda/model_sync.py
    sed -i "s/s3:\/\/comfyui-models-.*%s-%s/s3:\/\/comfyui-models-$project_name-%s-%s/g" $CDK_DIR/lib/ComfyModelsSyncLambda/model_sync.py

    cd $CDK_DIR && cdk deploy $LAMBDA_STACK --require-approval never
    if [ $? -eq 0 ]; then
        echo "Lambda deploy completed successfully"
    else
        echo "Lambda deploy failed"
        exit 1
    fi
    echo "==== Finish deploying LambdaModelsSync ===="
}

cdk_deploy_s3() {
    echo "==== Start deploying S3Storage ===="
    cd $CDK_DIR && cdk deploy $S3_STACK --require-approval never
    if [ $? -eq 0 ]; then
        echo "S3 deploy completed successfully"
    else
        echo "S3 deploy failed"
        exit 1
    fi
    echo "==== Finish deploying S3Storage ===="
}

upload_models_to_s3() {
    echo "==== Start uploading models to S3 ===="
    cd $CDK_DIR/test && bash init_s3_for_models.sh $AWS_DEFAULT_REGION &
    echo "==== Finish uploading models to S3 ===="
}

cdk_deploy_ecr() {
    echo "==== Start deploying ComfyuiEcrRepo ===="
    cd $CDK_DIR && cdk deploy $ECR_STACK --require-approval never
    if [ $? -eq 0 ]; then
        echo "ECR deploy completed successfully"
    else
        echo "ECR deploy failed"
        exit 1
    fi
    echo "==== Finish deploying ComfyuiEcrRepo ===="
}

build_and_push_comfyui_image() {
    echo "==== Start building and pushing Comfyui image ===="
    cd $CDK_DIR/comfyui_image && bash build_and_push.sh $AWS_DEFAULT_REGION
    if [ $? -eq 0 ]; then
        echo "Comfyui image build and push completed successfully"
    else
        echo "Comfyui image build and push failed"
        exit 1
    fi
    echo "==== Finish building and pushing Comfyui image ===="
}

deploy_karpenter() {
    echo "==== Start deploying Karpenter ===="
    kubectl delete -f $CDK_DIR/manifests/Karpenter/karpenter_v1.yaml --ignore-not-found
    KarpenterInstanceNodeRole=$(aws cloudformation describe-stacks --stack-name $EKS_CLUSTER_STACK --query 'Stacks[0].Outputs[?OutputKey==`KarpenterInstanceNodeRole`].OutputValue' --output text)
    if [ -z "$PROJECT_NAME" ]; then
        sg_tag="eks-cluster-sg-Comfyui-Cluster*"
        subnet_tag="Comfyui-Cluster\/ComfyuiVPC\/private*"
        node_name="ComfyUI-EKS-GPU-Node"
        bucket_name="comfyui-models-${ACCOUNT_ID}-${AWS_DEFAULT_REGION}"
    else
        sg_tag="eks-cluster-sg-Comfyui-Cluster-${PROJECT_NAME}*"
        subnet_tag="Comfyui-Cluster-${PROJECT_NAME}\/ComfyuiVPC\/private*"
        node_name="ComfyUI-EKS-GPU-Node-${PROJECT_NAME}"
        bucket_name="comfyui-models-${project_name}-${ACCOUNT_ID}-${AWS_DEFAULT_REGION}"
    fi

    if [ x"$KarpenterInstanceNodeRole" != "x" ]
    then
        echo "KarpenterInstanceNodeRole            : $KarpenterInstanceNodeRole"
        echo "securityGroupSelectorTerms tags Name : $sg_tag"
        echo "subnetSelectorTerms tags Name        : $subnet_tag"
        echo "Deploying Karpenter..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sed -i "s/role: .*/role: $KarpenterInstanceNodeRole/g" $CDK_DIR/manifests/Karpenter/karpenter_v1.yaml
            sed -i "s/Name: eks-cluster-sg-Comfyui-Cluster.*/Name: $sg_tag/g" $CDK_DIR/manifests/Karpenter/karpenter_v1.yaml
            sed -i "s/Name: Comfyui-Cluster\/ComfyuiVPC\/private.*/Name: $subnet_tag/g" $CDK_DIR/manifests/Karpenter/karpenter_v1.yaml
            sed -i "s/Name: ComfyUI-EKS-GPU-Node/Name: $node_name/g" $CDK_DIR/manifests/Karpenter/karpenter_v1.yaml
            sed -i "s/s3:\/\/comfyui-models-.* /s3:\/\/$bucket_name /g" $CDK_DIR/manifests/Karpenter/karpenter_v1.yaml
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/role: .*/role: $KarpenterInstanceNodeRole/g" $CDK_DIR/manifests/Karpenter/karpenter_v1.yaml
            sed -i '' "s/Name: eks-cluster-sg-Comfyui-Cluster.*/Name: $sg_tag/g" $CDK_DIR/manifests/Karpenter/karpenter_v1.yaml
            sed -i '' "s/Name: Comfyui-Cluster\/ComfyuiVPC\/private.*/Name: $subnet_tag/g" $CDK_DIR/manifests/Karpenter/karpenter_v1.yaml
            sed -i '' "s/Name: ComfyUI-EKS-GPU-Node/Name: $node_name/g" $CDK_DIR/manifests/Karpenter/karpenter_v1.yaml
            sed -i '' "s/s3:\/\/comfyui-models-.* /s3:\/\/$bucket_name /g" $CDK_DIR/manifests/Karpenter/karpenter_v1.yaml
        else
            echo "Unsupported OS: $OSTYPE"
            exit 1
        fi
        kubectl apply -f $CDK_DIR/manifests/Karpenter/karpenter_v1.yaml
        aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess --role-name $KarpenterInstanceNodeRole
    else
        echo "KarpenterInstanceNodeRole is not set"
        exit 1
    fi
    echo "==== Finish deploying Karpenter ===="
}

deploy_s3_pv_pvc() {
    echo "==== Start deploying S3 PV/PVC ===="
    kubectl delete -f $CDK_DIR/manifests/PersistentVolume/ --ignore-not-found
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sed -i "s/region .*/region $AWS_DEFAULT_REGION/g" $CDK_DIR/manifests/PersistentVolume/sd-outputs-s3.yaml
        sed -i "s/region .*/region $AWS_DEFAULT_REGION/g" $CDK_DIR/manifests/PersistentVolume/sd-inputs-s3.yaml
        sed -i "s/bucketName: .*/bucketName: $output_bucket_name/g" $CDK_DIR/manifests/PersistentVolume/sd-outputs-s3.yaml
        sed -i "s/bucketName: .*/bucketName: $input_bucket_name/g" $CDK_DIR/manifests/PersistentVolume/sd-inputs-s3.yaml
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/region .*/region $AWS_DEFAULT_REGION/g" $CDK_DIR/manifests/PersistentVolume/sd-outputs-s3.yaml
        sed -i '' "s/region .*/region $AWS_DEFAULT_REGION/g" $CDK_DIR/manifests/PersistentVolume/sd-inputs-s3.yaml
        sed -i '' "s/bucketName: .*/bucketName: $output_bucket_name/g" $CDK_DIR/manifests/PersistentVolume/sd-outputs-s3.yaml
        sed -i '' "s/bucketName: .*/bucketName: $input_bucket_name/g" $CDK_DIR/manifests/PersistentVolume/sd-inputs-s3.yaml
    else
        echo "Unsupported OS: $OSTYPE"
        exit 1
    fi
    kubectl apply -f $CDK_DIR/manifests/PersistentVolume/
    if [ $? -eq 0 ]; then
        echo "S3 PV/PVC deploy completed successfully"
    else
        echo "S3 PV/PVC deploy failed"
        exit 1
    fi
    echo "==== Finish deploying S3 PV/PVC ===="
}

deploy_s3_csi_driver() {
    echo "==== Start deploying S3 CSI Driver ===="
    identity=$(aws sts get-caller-identity --query 'Arn' --output text --no-cli-pager)
    if [[ $identity == *"assumed-role"* ]]; then
        role_name=$(echo $identity | cut -d'/' -f2)
        account_id=$(echo $identity | cut -d':' -f5)
        identity="arn:aws:iam::$account_id:role/$role_name"
    fi

    authenticationMode=$(aws eks describe-cluster --name $EKS_CLUSTER_STACK --query 'cluster.accessConfig.authenticationMode' --output text)
    if [ "$authenticationMode" == "API_AND_CONFIG_MAP" ]; then
        echo "authenticationMode=API_AND_CONFIG_MAP is ready"
    else
        aws eks update-cluster-config --name $EKS_CLUSTER_STACK --access-config authenticationMode=API_AND_CONFIG_MAP
        echo "Waiting for authenticationMode=API_AND_CONFIG_MAP to be ready..."
    fi
    while [ "$authenticationMode" != "API_AND_CONFIG_MAP" ]; do
        echo "authenticationMode=$authenticationMode, sleep 5s..."
        sleep 5
        authenticationMode=$(aws eks describe-cluster --name $EKS_CLUSTER_STACK --query 'cluster.accessConfig.authenticationMode' --output text)
    done
    aws eks create-access-entry --cluster-name $EKS_CLUSTER_STACK --principal-arn $identity --type STANDARD --username comfyui-user
    aws eks associate-access-policy --cluster-name $EKS_CLUSTER_STACK --principal-arn $identity --access-scope type=cluster --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy
    aws eks list-access-entries --cluster-name $EKS_CLUSTER_STACK|grep $identity
    ROLE_NAME=EKS-S3-CSI-DriverRole-$ACCOUNT_ID-$AWS_DEFAULT_REGION
    POLICY_ARN=arn:aws:iam::aws:policy/AmazonS3FullAccess
    eksctl create iamserviceaccount \
        --name s3-csi-driver-sa \
        --namespace kube-system \
        --cluster $EKS_CLUSTER_STACK \
        --attach-policy-arn $POLICY_ARN \
        --approve \
        --role-name $ROLE_NAME \
        --region $AWS_DEFAULT_REGION
    eksctl create addon --name aws-mountpoint-s3-csi-driver --cluster $EKS_CLUSTER_STACK --service-account-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/EKS-S3-CSI-DriverRole-${ACCOUNT_ID}-${AWS_DEFAULT_REGION}" --force
    if [ $? -eq 0 ]; then
        echo "S3 CSI Driver deploy completed successfully"
    else
        echo "S3 CSI Driver deploy failed"
        exit 1
    fi
    echo "==== Finish deploying S3 CSI Driver ===="
}

fix_s3_csi_node() {
    # It's a temp workaround for the issue https://github.com/awslabs/mountpoint-s3-csi-driver/issues/284
    echo "==== Start fixing S3 CSI Node ===="
    kubectl get ds s3-csi-node -n kube-system -o yaml > s3-csi-node-ds.yaml
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sed -i "s/image: .*aws-s3-csi-driver.*/image: public.ecr.aws\/q4h1b4d0\/array-mountpoint-s3-csi-driver:20240724.10/g" s3-csi-node-ds.yaml
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/image: .*aws-s3-csi-driver.*/image: public.ecr.aws\/q4h1b4d0\/array-mountpoint-s3-csi-driver:20240724.10/g" s3-csi-node-ds.yaml
    else
        echo "Unsupported OS: $OSTYPE"
        exit 1
    fi
    kubectl apply -f s3-csi-node-ds.yaml
    if [ $? -eq 0 ]; then
        echo "S3 CSI Node fix completed successfully"
    else
        echo "S3 CSI Node fix failed"
        exit 1
    fi
    rm -rf s3-csi-node-ds.yaml
    i=0
    while [ "$(kubectl get pods -n kube-system | grep s3-csi-node | awk '{print $3}'| tail -1)" != "Running" ]; do
        echo "s3-csi-node pod is not ready, sleep 5s..."
        sleep 5
        i=$((i+1))
        if [ $i -gt 60 ]; then
            echo "s3-csi-node pod is not ready after 5min"
            exit 1
        fi
    done
    echo "==== Finish fixing S3 CSI Node ===="
}

deploy_comfyui() {
    echo "==== Start deploying ComfyUI ===="
    tag="latest"
    repo_name="comfyui-images${project_name:+-$project_name}"
    kubectl delete -f $CDK_DIR/manifests/ComfyUI/ --ignore-not-found
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sed -i "s/image: .*/image: ${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com\/$repo_name:$tag/g" $CDK_DIR/manifests/ComfyUI/comfyui_deployment.yaml
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/image: .*/image: ${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com\/$repo_name:$tag/g" $CDK_DIR/manifests/ComfyUI/comfyui_deployment.yaml
    else
        echo "Unsupported OS: $OSTYPE"
        exit 1
    fi
    kubectl apply -f $CDK_DIR/manifests/ComfyUI/
    if [ $? -eq 0 ]; then
        echo "ComfyUI deploy completed successfully"
    else
        echo "ComfyUI deploy failed"
        exit 1
    fi
    echo "==== Finish deploying ComfyUI ===="
}

test_comfyui() {
    echo "==== Start testing ComfyUI ===="
    ingress_addr=$(kubectl get ingress -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
    # Check if Ingress is ready
    i=0
    while [ x"$ingress_addr" == "x" ]; do
        if [ $i -gt 60 ]; then
            echo "Ingress address is not ready after 5min"
            exit 1
        fi
        echo "Ingress address is not ready, sleep 5s..."
        sleep 5
        ingress_addr=$(kubectl get ingress -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
        i=$((i+1))
    done

    echo "Ingress Address: http://$ingress_addr"

    # Check if ComfyUI is ready
    i=0
    while [ "$(kubectl get pods | grep comfyui | awk '{print $3}' | tail -1)" != "Running" ]; do
        if [ $i -gt 240 ]; then
            echo "ComfyUI pod is not ready after 20min"
            exit 1
        fi
        echo "ComfyUI pod is not ready, sleep 5s..."
        sleep 5
        i=$((i+1))
    done

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sed -i "s/SERVER_ADDRESS = .*/SERVER_ADDRESS = \"http:\/\/$ingress_addr\"/g" $CDK_DIR/test/invoke_comfyui_api.py
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/SERVER_ADDRESS = .*/SERVER_ADDRESS = \"http:\/\/$ingress_addr\"/g" $CDK_DIR/test/invoke_comfyui_api.py
    else
        echo "Unsupported OS: $OSTYPE"
        exit 1
    fi
    chmod +x $CDK_DIR/test/invoke_comfyui_api.py

    image_num_before_generate=$(aws s3 ls s3://$output_bucket_name/ | wc -l)
    echo "Number of images before generate: $image_num_before_generate"
    i=0
    $CDK_DIR/test/invoke_comfyui_api.py $CDK_DIR/test/test_workflows/sdxl_refiner_prompt_api.json
    while [ $? -ne 0 ]; do
        if [ $i -gt 60 ]; then
            echo "ComfyUI test failed after 5min"
            exit 1
        fi
        i=$((i+1))
        echo "ComfyUI test failed, sleep 5s and retry..."
        sleep 5
        $CDK_DIR/test/invoke_comfyui_api.py $CDK_DIR/test/test_workflows/sdxl_refiner_prompt_api.json
    done
    if [ $? -eq 0 ]; then
        image_num_after_generate=$(aws s3 ls s3://$output_bucket_name/ | wc -l)
        echo "Number of images after generate: $image_num_after_generate"
        if [ $image_num_after_generate -gt $image_num_before_generate ]; then
            echo "Comfyui test completed successfully"
        else
            echo "Comfyui test failed, image isn't written to s3."
            exit 1
        fi
    else
        echo "ComfyUI test failed"
        exit 1
    fi

}

# ====== Activate NVM & CDK ====== #
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# ====== General functions ====== #
start_time=$(date +%s)
get_stacks_names
cdk_deploy_eks_cluster
prepare_eks_env
cdk_deploy_lambda
cdk_deploy_s3
upload_models_to_s3
cdk_deploy_ecr
build_and_push_comfyui_image
deploy_karpenter
deploy_s3_pv_pvc
deploy_s3_csi_driver
fix_s3_csi_node
deploy_comfyui
test_comfyui
end_time=$(date +%s)
echo "Total time: $((end_time-start_time))s"

# ====== Debug functions ====== #
uninstall_s3_csi_driver() {
    echo "==== Start uninstalling S3 CSI Driver ===="
    eksctl delete addon --name aws-mountpoint-s3-csi-driver --cluster $EKS_CLUSTER_STACK
    eksctl delete iamserviceaccount --name s3-csi-driver-sa --namespace kube-system --cluster $EKS_CLUSTER_STACK
    aws eks delete-access-entry --cluster-name $EKS_CLUSTER_STACK --principal-arn $identity
    echo "==== Finish uninstalling S3 CSI Driver ===="
}
