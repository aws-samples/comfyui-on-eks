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
    # Print more pretty
    echo "EKS_CLUSTER_STACK : $EKS_CLUSTER_STACK"
    echo "LAMBDA_STACK      : $LAMBDA_STACK"
    echo "S3_STACK          : $S3_STACK"
    echo "ECR_STACK         : $ECR_STACK"
    echo "CLOUDFRONT_STACK  : $CLOUDFRONT_STACK"
    echo "==== Finish getting CloudFormation Stacks ===="
}

delete_k8s_resources() {
    echo "=== Start deleting k8s resources ==="

    # Delete comfyui resources
    kubectl get deploy comfyui &> /dev/null
    if [ $? -ne 0 ]; then
        echo "comfyui deployment not found"
    else
        kubectl delete deploy comfyui
    fi
    kubectl get svc comfyui-service &> /dev/null
    if [ $? -ne 0 ]; then
        echo "comfyui-service service not found"
    else
        kubectl delete svc comfyui-service
    fi
    kubectl get ingress comfyui-ingress &> /dev/null
    if [ $? -ne 0 ]; then
        echo "comfyui-ingress ingress not found"
    else
        kubectl delete ingress comfyui-ingress
    fi

    # Delete pv & pvc resources
    kubectl get pvc &> /dev/null
    if [ $? -ne 0 ]; then
        echo "No pvc found"
    else
        kubectl get pvc|grep comfyui|awk '{print $1}'|xargs -I {} kubectl delete pvc {}
    fi
    kubectl get pv &> /dev/null
    if [ $? -ne 0 ]; then
        echo "No pv found"
    else
        kubectl get pv|grep comfyui|awk '{print $1}'|xargs -I {} kubectl delete pv {}
    fi

    # Delete karpenter resources

    echo "=== Finish deleting k8s resources ==="
    echo
}

terminate_karpenter_nodes() {
    echo "=== Start terminating Karpenter-provisioned nodes ==="
    CLUSTER_NAME="ComfyUI-on-EKS-Cluster"

    # Terminate all EC2 instances tagged with this EKS cluster (works even if kubectl is unavailable)
    INSTANCE_IDS=$(aws ec2 describe-instances \
        --filters "Name=tag:eks:eks-cluster-name,Values=$CLUSTER_NAME" \
                  "Name=instance-state-name,Values=running,stopped,pending" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text 2>/dev/null)

    if [ -z "$INSTANCE_IDS" ]; then
        echo "No Karpenter nodes found for cluster $CLUSTER_NAME"
    else
        echo "Terminating Karpenter instances: $INSTANCE_IDS"
        aws ec2 terminate-instances --instance-ids $INSTANCE_IDS
        echo "Waiting for instances to terminate (this may take a few minutes for GPU instances)..."
        aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS
        echo "All Karpenter nodes terminated"
    fi
    echo "=== Finish terminating Karpenter nodes ==="
    echo
}

delete_cluster_load_balancers() {
    echo "=== Start deleting cluster Load Balancers ==="
    CLUSTER_NAME="ComfyUI-on-EKS-Cluster"

    # Find ALBs/NLBs created by the AWS Load Balancer Controller for this cluster
    LB_ARNS=$(aws elbv2 describe-load-balancers \
        --query 'LoadBalancers[*].LoadBalancerArn' \
        --output text 2>/dev/null)

    for LB_ARN in $LB_ARNS; do
        [ -z "$LB_ARN" ] && continue
        # Check if this LB belongs to our cluster via tags
        CLUSTER_TAG=$(aws elbv2 describe-tags --resource-arns "$LB_ARN" \
            --query "TagDescriptions[0].Tags[?Key=='elbv2.k8s.aws/cluster' && Value=='$CLUSTER_NAME'].Value" \
            --output text 2>/dev/null)

        if [ ! -z "$CLUSTER_TAG" ]; then
            echo "Deleting Load Balancer: $LB_ARN"
            aws elbv2 delete-load-balancer --load-balancer-arn "$LB_ARN"
        fi
    done

    # Wait for LB ENIs to release before cleaning up target groups
    if [ ! -z "$CLUSTER_TAG" ]; then
        echo "Waiting for Load Balancer ENIs to release..."
        sleep 20
    fi

    # Delete orphaned target groups tagged with this cluster
    ALL_TG_ARNS=$(aws elbv2 describe-target-groups \
        --query 'TargetGroups[*].TargetGroupArn' --output text 2>/dev/null)
    for TG_ARN in $ALL_TG_ARNS; do
        [ -z "$TG_ARN" ] && continue
        TG_CLUSTER_TAG=$(aws elbv2 describe-tags --resource-arns "$TG_ARN" \
            --query "TagDescriptions[0].Tags[?Key=='elbv2.k8s.aws/cluster' && Value=='$CLUSTER_NAME'].Value" \
            --output text 2>/dev/null)
        if [ ! -z "$TG_CLUSTER_TAG" ]; then
            echo "Deleting Target Group: $TG_ARN"
            aws elbv2 delete-target-group --target-group-arn "$TG_ARN" 2>/dev/null
        fi
    done

    # Delete security groups created by the AWS LB Controller
    LB_SEC_GROUPS=$(aws ec2 describe-security-groups \
        --filters "Name=tag:elbv2.k8s.aws/cluster,Values=$CLUSTER_NAME" \
        --query 'SecurityGroups[*].GroupId' --output text 2>/dev/null)
    for SG in $LB_SEC_GROUPS; do
        [ -z "$SG" ] && continue
        echo "Deleting LB Controller Security Group: $SG"
        aws ec2 delete-security-group --group-id "$SG" 2>/dev/null
    done

    echo "=== Finish deleting cluster Load Balancers ==="
    echo
}

delete_ecr_repo() {
    echo "=== Start deleting ECR repo ==="
    aws ecr describe-repositories --repository-names $repo_name &> /dev/null
    if [ $? -ne 0 ]; then
        echo "$repo_name repository not found"
    else
        aws ecr delete-repository --repository-name $repo_name --force
    fi
    aws cloudformation describe-stacks --stack-name $ECR_STACK &> /dev/null
    if [ $? -ne 0 ]; then
        echo "$ECR_STACK stack not found"
    else
        cd $CDK_DIR && cdk destroy -f $ECR_STACK
    fi
    echo "=== Finish deleting ECR repo ==="
    echo
}

delete_cloudfront() {
    echo "=== Start deleting CloudFront ==="
    aws cloudformation describe-stacks --stack-name $CLOUDFRONT_STACK &> /dev/null
    if [ $? -ne 0 ]; then
        echo "$CLOUDFRONT_STACK stack not found"
    else
        cd $CDK_DIR && cdk destroy -f $CLOUDFRONT_STACK
    fi
    echo "=== Finish deleting CloudFront ==="
    echo
}

delete_s3() {
    echo "=== Start deleting S3 ==="
    aws cloudformation describe-stacks --stack-name $S3_STACK &> /dev/null
    if [ $? -ne 0 ]; then
        echo "$S3_STACK stack not found"
    else
        cd $CDK_DIR && cdk destroy -f $S3_STACK
    fi
    echo "=== Finish deleting S3 ==="
    echo
}

delete_lambda_sync() {
    echo "=== Start deleting LambdaModelsSync ==="
    aws cloudformation describe-stacks --stack-name $LAMBDA_STACK &> /dev/null
    if [ $? -ne 0 ]; then
        echo "$LAMBDA_STACK stack not found"
    else
        cd $CDK_DIR && cdk destroy -f $LAMBDA_STACK
    fi
    echo "=== Finish deleting LambdaModelsSync ==="
    echo
}

delete_comfyui_cluster() {
    echo "=== Start deleting Comfyui-Cluster ==="

    # Try 3 times
    while [[ $i -lt 3 ]]; do
        fix_comfyui_stack_deletion
        # Delete stack
        aws cloudformation describe-stacks --stack-name $EKS_CLUSTER_STACK &> /dev/null
        if [ $? -ne 0 ]; then
            echo "$EKS_CLUSTER_STACK stack not found"
            break
        else
            cd $CDK_DIR && cdk destroy -f $EKS_CLUSTER_STACK
            if [ $? -ne 0 ]; then
                echo "Failed to delete $EKS_CLUSTER_STACK stack, try again"
            else
                echo "$EKS_CLUSTER_STACK stack deleted"
                break
            fi
        fi
        i=$((i+1))
    done

    echo "=== Finish deleting Comfyui-Cluster ==="
    echo
}

fix_comfyui_stack_deletion() {
    echo "=== Start fixing comfyui stack deletion ==="

    # Remove KarpenterInstanceNodeRole from instance profile
    KarpenterInstanceNodeRole=$(aws cloudformation describe-stacks --stack-name $EKS_CLUSTER_STACK --query 'Stacks[0].Outputs[?OutputKey==`KarpenterInstanceNodeRole`].OutputValue' --output text 2>/dev/null)
    profiles=$(aws iam list-instance-profiles-for-role --role-name $KarpenterInstanceNodeRole | jq -r '.InstanceProfiles[].InstanceProfileName' 2>/dev/null)
    for profile in $profiles
    do
        echo "Removing role from instance profile $profile"
        aws iam remove-role-from-instance-profile --instance-profile-name $profile --role-name $KarpenterInstanceNodeRole
        echo "Deleting instance profile $profile"
        aws iam delete-instance-profile --instance-profile-name $profile
    done
    echo "All associated instance profiles have been removed and deleted."
    aws iam delete-role --role-name $KarpenterInstanceNodeRole --no-cli-pager

    # vpc deletion failed
    vpc_id=$(aws cloudformation describe-stack-events \
        --stack-name $EKS_CLUSTER_STACK \
        --query 'StackEvents[?ResourceStatus==`DELETE_FAILED` && ResourceType==`AWS::EC2::VPC`].{Reason:ResourceStatusReason}'| grep -o 'vpc-[a-z0-9]*'|tail -1)
    if [ -z $vpc_id ]; then
        subnet_id=$(aws cloudformation describe-stack-events \
            --stack-name $EKS_CLUSTER_STACK \
            --query 'StackEvents[?ResourceStatus==`DELETE_FAILED` && ResourceType==`AWS::EC2::Subnet`].{Reason:ResourceStatusReason}'| grep -o 'subnet-[a-z0-9]*'|tail -1)
        if [ -z $subnet_id ]; then
            echo "No subnet found in delete failed"
        else
            vpc_id=$(aws ec2 describe-subnets --subnet-ids $subnet_id --query 'Subnets[0].VpcId' --output text)
        fi
    fi
    if [ -z $vpc_id ]; then
        echo "No vpc found in delete failed"
    else
        echo "Force delete vpc: $vpc_id"
        force_delete_vpc $vpc_id
    fi

    echo "=== Finish fixing comfyui stack deletion ==="
    echo
}

force_delete_vpc() {
    VPC_ID=$1
    if [ -z $VPC_ID ]; then
        echo "VPC ID is empty"
        return
    fi
    # 1. Delete NAT Gateways
    echo "Deleting NAT Gateways..."
    NAT_GATEWAYS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --query 'NatGateways[*].NatGatewayId' --output text)
    for NAT_GW in $NAT_GATEWAYS; do
        echo "Deleting NAT Gateway: $NAT_GW"
        aws ec2 delete-nat-gateway --nat-gateway-id $NAT_GW
        echo "Waiting for NAT Gateway to be deleted..."
        aws ec2 wait nat-gateway-deleted --nat-gateway-ids $NAT_GW
    done

    # 2. Delete Internet Gateway
    echo "Deleting Internet Gateway..."
    IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[*].InternetGatewayId' --output text)
    if [ ! -z "$IGW_ID" ]; then
        aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
        aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID
    fi

    # 3. Delete ENIs (detach first if still in-use)
    echo "Deleting ENIs..."
    ENI_DATA=$(aws ec2 describe-network-interfaces \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'NetworkInterfaces[*].[NetworkInterfaceId,Attachment.AttachmentId,Status]' \
        --output text 2>/dev/null)
    if [ ! -z "$ENI_DATA" ]; then
        while IFS=$'\t' read -r ENI_ID ATTACH_ID STATUS; do
            [ -z "$ENI_ID" ] && continue
            if [ "$STATUS" == "in-use" ] && [ "$ATTACH_ID" != "None" ] && [ ! -z "$ATTACH_ID" ]; then
                echo "Force detaching ENI: $ENI_ID (attachment: $ATTACH_ID)"
                aws ec2 detach-network-interface --attachment-id "$ATTACH_ID" --force 2>/dev/null
            fi
        done <<< "$ENI_DATA"
        # Wait for detachments to complete
        echo "Waiting for ENI detachments to complete..."
        sleep 15
        # Now delete all ENIs
        ENI_IDS=$(aws ec2 describe-network-interfaces \
            --filters "Name=vpc-id,Values=$VPC_ID" \
            --query 'NetworkInterfaces[*].NetworkInterfaceId' \
            --output text 2>/dev/null)
        for ENI in $ENI_IDS; do
            echo "Deleting ENI: $ENI"
            aws ec2 delete-network-interface --network-interface-id "$ENI" 2>/dev/null
        done
    fi

    # 4. Delete Subnets
    echo "Deleting Subnets..."
    SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text)
    for SUBNET in $SUBNETS; do
        echo "Deleting Subnet: $SUBNET"
        aws ec2 delete-subnet --subnet-id $SUBNET
    done

    # 5. Delete Custom Security Groups (excluding default)
    echo "Deleting Security Groups..."
    SEC_GROUPS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
    for SG in $SEC_GROUPS; do
        echo "Deleting Security Group: $SG"
        aws ec2 delete-security-group --group-id $SG
    done

    # 6. Delete Custom Route Tables (excluding main route table)
    echo "Deleting Route Tables..."
    RT_IDS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[?Associations[?Main!=`true`]].RouteTableId' --output text)
    for RT in $RT_IDS; do
        echo "Deleting Route Table: $RT"
        aws ec2 delete-route-table --route-table-id $RT
    done

    # 7. Finally, delete the VPC
    echo "Deleting VPC..."
    aws ec2 delete-vpc --vpc-id $VPC_ID
}

# ====== Activate NVM & CDK ====== #
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

get_stacks_names
delete_k8s_resources
terminate_karpenter_nodes
delete_cluster_load_balancers
delete_ecr_repo
delete_cloudfront
delete_s3
delete_lambda_sync
delete_comfyui_cluster

echo "=== Destroy infra done! ==="
