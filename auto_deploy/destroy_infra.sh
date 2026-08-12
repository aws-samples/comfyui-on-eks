#!/bin/bash
# ComfyUI-on-EKS teardown. Fails loudly on version mismatch, credential failure,
# or partial deletion. See lib.sh for preflight and get_stacks_names logic.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
source "$SCRIPT_DIR/lib.sh"

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
    if ! stack_exists "$ECR_STACK"; then
        echo "$ECR_STACK stack not found"
    else
        cd "$CDK_DIR" && "$CDK" destroy -f "$ECR_STACK"
    fi
    echo "=== Finish deleting ECR repo ==="
    echo
}

delete_cloudfront() {
    echo "=== Start deleting CloudFront ==="
    if ! stack_exists "$CLOUDFRONT_STACK"; then
        echo "$CLOUDFRONT_STACK stack not found"
    else
        cd "$CDK_DIR" && "$CDK" destroy -f "$CLOUDFRONT_STACK"
    fi
    echo "=== Finish deleting CloudFront ==="
    echo
}

delete_s3() {
    echo "=== Start deleting S3 ==="
    if ! stack_exists "$S3_STACK"; then
        echo "$S3_STACK stack not found"
    else
        cd "$CDK_DIR" && "$CDK" destroy -f "$S3_STACK"
    fi
    echo "=== Finish deleting S3 ==="
    echo
}

delete_lambda_sync() {
    echo "=== Start deleting LambdaModelsSync ==="
    if ! stack_exists "$LAMBDA_STACK"; then
        echo "$LAMBDA_STACK stack not found"
    else
        cd "$CDK_DIR" && "$CDK" destroy -f "$LAMBDA_STACK"
    fi
    echo "=== Finish deleting LambdaModelsSync ==="
    echo
}

delete_comfyui_cluster() {
    echo "=== Start deleting Comfyui-Cluster ==="

    # Try 3 times
    local i=0
    while [[ $i -lt 3 ]]; do
        fix_comfyui_stack_deletion
        # Delete stack
        if ! stack_exists "$EKS_CLUSTER_STACK"; then
            echo "$EKS_CLUSTER_STACK stack not found"
            break
        else
            cd "$CDK_DIR" && "$CDK" destroy -f "$EKS_CLUSTER_STACK"
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
    KarpenterInstanceNodeRole=$(aws cloudformation describe-stacks --stack-name "$EKS_CLUSTER_STACK" --query 'Stacks[0].Outputs[?OutputKey==`KarpenterInstanceNodeRole`].OutputValue' --output text 2>/dev/null)
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
        --stack-name "$EKS_CLUSTER_STACK" \
        --query 'StackEvents[?ResourceStatus==`DELETE_FAILED` && ResourceType==`AWS::EC2::VPC`].{Reason:ResourceStatusReason}'| grep -o 'vpc-[a-z0-9]*'|tail -1)
    if [ -z $vpc_id ]; then
        subnet_id=$(aws cloudformation describe-stack-events \
            --stack-name "$EKS_CLUSTER_STACK" \
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

# ====== Residual cleanup (non-data orphans outside CloudFormation) ====== #
cleanup_residuals() {
    echo "=== Cleaning up residual resources ==="

    # 1. Bedrock Pod Identity role (created imperatively, not via CFN)
    local ROLE_NAME="ComfyUI-Bedrock-PodIdentity-${ACCOUNT_ID}-${AWS_DEFAULT_REGION}"
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        echo "  Deleting IAM role: $ROLE_NAME"
        # Delete all inline policies (there may be 1-N, don't hardcode names)
        for pol in $(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames[]' --output text 2>/dev/null); do
            aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$pol" 2>/dev/null
        done
        aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null && echo "    Deleted" || echo "    (could not delete)"
    else
        echo "  IAM role $ROLE_NAME not found (already clean)"
    fi

    # 1b. Karpenter instance profile (created by deploy_karpenter, outside CFN)
    local IP_NAME="ComfyUI-Karpenter-${ACCOUNT_ID}-${AWS_DEFAULT_REGION}"
    if aws iam get-instance-profile --instance-profile-name "$IP_NAME" &>/dev/null; then
        echo "  Deleting instance profile: $IP_NAME"
        # Remove all roles first
        for role in $(aws iam get-instance-profile --instance-profile-name "$IP_NAME" --query 'InstanceProfile.Roles[].RoleName' --output text 2>/dev/null); do
            aws iam remove-role-from-instance-profile --instance-profile-name "$IP_NAME" --role-name "$role" 2>/dev/null
        done
        aws iam delete-instance-profile --instance-profile-name "$IP_NAME" 2>/dev/null && echo "    Deleted" || echo "    (could not delete)"
    fi

    # 2. CloudWatch log groups
    echo "  Deleting orphaned log groups..."
    for prefix in "/aws/lambda/ComfyUI" "/aws/lambda/Comfyui" "/aws/codebuild/comfyui-"; do
        for lg in $(aws logs describe-log-groups --log-group-name-prefix "$prefix" --query 'logGroups[].logGroupName' --output text 2>/dev/null); do
            echo "    Deleting: $lg"
            aws logs delete-log-group --log-group-name "$lg" 2>/dev/null
        done
    done

    # 3. ECR base-cache repo (created by CodeBuild buildspec, not CDK)
    if aws ecr describe-repositories --repository-names comfyui-base-cache &>/dev/null; then
        echo "  Deleting ECR repo: comfyui-base-cache"
        aws ecr delete-repository --repository-name comfyui-base-cache --force 2>/dev/null
    fi

    # 4. SSM patch association (created imperatively)
    local ASSOC_ID
    ASSOC_ID=$(aws ssm list-associations \
        --query "Associations[?AssociationName=='comfyui-eks-nodes-autopatch'].AssociationId" \
        --output text 2>/dev/null)
    if [ -n "$ASSOC_ID" ] && [ "$ASSOC_ID" != "None" ]; then
        echo "  Deleting SSM association: $ASSOC_ID"
        aws ssm delete-association --association-id "$ASSOC_ID" 2>/dev/null
    fi

    # 5. KMS key (schedule deletion; can't be immediate)
    local KEY_ID
    KEY_ID=$(aws kms list-keys --query 'Keys[].KeyId' --output text 2>/dev/null | while read -r kid; do
        tags=$(aws kms list-resource-tags --key-id "$kid" --query "Tags[?TagKey=='Project' && TagValue=='comfyui-on-eks'].TagValue" --output text 2>/dev/null)
        [ -n "$tags" ] && echo "$kid" && break
    done)
    if [ -n "$KEY_ID" ]; then
        echo "  Scheduling KMS key deletion (7 days): $KEY_ID"
        aws kms schedule-key-deletion --key-id "$KEY_ID" --pending-window-in-days 7 2>/dev/null
    fi

    echo "=== Residual cleanup complete ==="
    echo
}

# ====== Post-deletion verification backstop ====== #
verify_teardown_complete() {
    echo "=== Verifying teardown completeness ==="
    local failures=0

    # Check no ComfyUI stacks remain in a non-deleted state
    local remaining
    remaining=$(aws cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE ROLLBACK_COMPLETE UPDATE_ROLLBACK_COMPLETE CREATE_IN_PROGRESS DELETE_IN_PROGRESS \
        --query "StackSummaries[?contains(StackName,'ComfyUI')].StackName" --output text 2>/dev/null)
    if [ -n "$remaining" ]; then
        echo "  WARNING: stacks still present: $remaining"
        failures=$((failures+1))
    fi

    # Check no EKS cluster
    if aws eks describe-cluster --name "ComfyUI-on-EKS-Cluster" &>/dev/null; then
        echo "  WARNING: EKS cluster still exists"
        failures=$((failures+1))
    fi

    # Check no tagged EC2 instances running
    local instances
    instances=$(aws ec2 describe-instances \
        --filters "Name=tag:eks:eks-cluster-name,Values=ComfyUI-on-EKS-Cluster" \
                  "Name=instance-state-name,Values=running,pending,stopped" \
        --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null)
    if [ -n "$instances" ]; then
        echo "  WARNING: EC2 instances still running: $instances"
        failures=$((failures+1))
    fi

    if [ $failures -gt 0 ]; then
        echo "  TEARDOWN INCOMPLETE: $failures issue(s) found above."
        echo "  Some resources may still be running and billing."
        return 1
    fi
    echo "  All clear -- no ComfyUI resources detected."
    echo "=== Verification passed ==="
}

# ====== Activate NVM & CDK ====== #
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# ====== Main execution ====== #
preflight_checks
get_stacks_names
delete_k8s_resources
terminate_karpenter_nodes
delete_cluster_load_balancers
delete_ecr_repo
delete_cloudfront
delete_s3
delete_lambda_sync
delete_comfyui_cluster
cleanup_residuals

if verify_teardown_complete; then
    echo ""
    echo "=========================================="
    echo "  Destroy infra done!"
    echo "=========================================="
    echo ""
    echo "Note: S3 buckets (models, inputs, outputs) are preserved."
    echo "To delete them: rerun with --delete-data"
else
    echo ""
    echo "=========================================="
    echo "  TEARDOWN INCOMPLETE -- see warnings above"
    echo "=========================================="
    exit 1
fi
