#!/bin/bash

source ./env.sh

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

delete_ecr_repo() {
    echo "=== Start deleting ECR repo ==="
    aws ecr describe-repositories --repository-names comfyui-images &> /dev/null
    if [ $? -ne 0 ]; then
        echo "comfyui-images repository not found"
    else
        aws ecr delete-repository --repository-name comfyui-images --force
    fi
    aws cloudformation describe-stacks --stack-name ComfyuiEcrRepo &> /dev/null
    if [ $? -ne 0 ]; then
        echo "ComfyuiEcrRepo stack not found"
    else
        cd $CDK_DIR && cdk destroy -f ComfyuiEcrRepo
    fi
    echo "=== Finish deleting ECR repo ==="
    echo
}

delete_cloudfront() {
    echo "=== Start deleting CloudFront ==="
    aws cloudformation describe-stacks --stack-name CloudFrontEntry &> /dev/null
    if [ $? -ne 0 ]; then
        echo "CloudFrontEntry stack not found"
    else
        cd $CDK_DIR && cdk destroy -f CloudFrontEntry
    fi
    echo "=== Finish deleting CloudFront ==="
    echo
}

delete_s3() {
    echo "=== Start deleting S3 ==="
    aws cloudformation describe-stacks --stack-name S3Storage &> /dev/null
    if [ $? -ne 0 ]; then
        echo "S3Storage stack not found"
    else
        cd $CDK_DIR && cdk destroy -f S3Storage
    fi
    echo "=== Finish deleting S3 ==="
    echo
}

delete_lambda_sync() {
    echo "=== Start deleting LambdaModelsSync ==="
    aws cloudformation describe-stacks --stack-name LambdaModelsSync &> /dev/null
    if [ $? -ne 0 ]; then
        echo "LambdaModelsSync stack not found"
    else
        cd $CDK_DIR && cdk destroy -f LambdaModelsSync
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
        aws cloudformation describe-stacks --stack-name Comfyui-Cluster &> /dev/null
        if [ $? -ne 0 ]; then
            echo "Comfyui-Cluster stack not found"
            break
        else
            cd $CDK_DIR && cdk destroy -f Comfyui-Cluster
            if [ $? -ne 0 ]; then
                echo "Failed to delete Comfyui-Cluster stack, try again"
            else
                echo "Comfyui-Cluster stack deleted"
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
    KarpenterInstanceNodeRole=$(aws cloudformation describe-stacks --stack-name Comfyui-Cluster --query 'Stacks[0].Outputs[?OutputKey==`KarpenterInstanceNodeRole`].OutputValue' --output text 2>/dev/null)
    InstanceProfileName=$(aws iam list-instance-profiles-for-role --role-name $KarpenterInstanceNodeRole --query 'InstanceProfiles[0].InstanceProfileName' --output text 2>/dev/null)
    if [ -z $InstanceProfileName ]; then
        echo "Instance profile not found"
    else
        echo "Remove role from instance profile"
        aws iam remove-role-from-instance-profile --instance-profile-name $InstanceProfileName --role-name $KarpenterInstanceNodeRole
    fi

    # vpc deletion failed
    vpc_id=$(aws cloudformation describe-stack-events \
        --stack-name Comfyui-Cluster \
        --query 'StackEvents[?ResourceStatus==`DELETE_FAILED` && ResourceType==`AWS::EC2::VPC`].{Reason:ResourceStatusReason}'| grep -o 'vpc-[a-z0-9]*'|tail -1)
    if [ -z $vpc_id ]; then
        subnet_id=$(aws cloudformation describe-stack-events \
            --stack-name Comfyui-Cluster \
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

    # 3. Delete eni
    echo "Deleting ENIs..."
    ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text)
    for ENI in $ENIS; do
        echo "Deleting ENI: $ENI"
        aws ec2 delete-network-interface --network-interface-id $ENI
    done

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

delete_k8s_resources
delete_ecr_repo
delete_cloudfront
delete_s3
delete_lambda_sync
delete_comfyui_cluster

echo "=== Destroy infra done! ==="
