#!/bin/bash
# Shared functions for deploy_infra.sh and destroy_infra.sh.
# Sourced after env.sh (which sets CDK_DIR, CDK, ACCOUNT_ID, AWS_DEFAULT_REGION).

REQUIRED_CDK_VERSION="2.1128.0"

assert_cdk_version() {
    local actual
    actual=$("$CDK" --version 2>/dev/null | awk '{print $1}')
    if [ -z "$actual" ]; then
        echo "FATAL: '$CDK' not found or not executable" >&2
        exit 1
    fi
    # sort -V: newer version sorts last; if required sorts last, actual is too old
    local newer
    newer=$(printf '%s\n%s\n' "$REQUIRED_CDK_VERSION" "$actual" | sort -V | tail -1)
    if [ "$newer" != "$actual" ]; then
        echo "FATAL: CDK CLI version $actual is older than required $REQUIRED_CDK_VERSION" >&2
        echo "  The repo-local binary at \$CDK ($CDK) should be $REQUIRED_CDK_VERSION." >&2
        echo "  Run: cd $CDK_DIR && npm install" >&2
        exit 1
    fi
}

preflight_checks() {
    local missing=()
    for tool in aws kubectl jq; do
        command -v "$tool" &>/dev/null || missing+=("$tool")
    done
    [ ${#missing[@]} -gt 0 ] && { echo "FATAL: missing tools: ${missing[*]}" >&2; exit 1; }

    # ACCOUNT_ID is set in env.sh via aws sts get-caller-identity (stderr suppressed).
    # An empty value means credentials are expired/missing.
    [ -z "$ACCOUNT_ID" ] && { echo "FATAL: ACCOUNT_ID empty -- 'aws sts get-caller-identity' failed (expired/missing credentials?)" >&2; exit 1; }
    [ -z "$AWS_DEFAULT_REGION" ] && { echo "FATAL: AWS_DEFAULT_REGION not set" >&2; exit 1; }
    [ -d "$CDK_DIR" ] || { echo "FATAL: CDK_DIR ($CDK_DIR) does not exist" >&2; exit 1; }

    assert_cdk_version
    echo "Preflight OK -- account $ACCOUNT_ID, region $AWS_DEFAULT_REGION, cdk $("$CDK" --version | awk '{print $1}')"
}

# Fail-loud stack name resolution. Replaces the old get_stacks_names().
# cdk list exits 0 even on schema mismatch (writes error to stderr only),
# so we capture both streams and assert non-empty results.
get_stacks_names() {
    echo "==== Resolving CloudFormation stack names ===="
    local out
    if ! out=$(cd "$CDK_DIR" && "$CDK" list 2>&1); then
        echo "FATAL: '$CDK list' failed:" >&2
        echo "$out" >&2
        exit 1
    fi

    export EKS_CLUSTER_STACK=$(echo "$out" | grep -o "ComfyUI-on-EKS-Cluster[^ ]*" | head -1)
    export LAMBDA_STACK=$(echo "$out" | grep -o "ComfyUI-on-EKS-Models[^ ]*" | head -1)
    export S3_STACK=$(echo "$out" | grep -o "ComfyUI-on-EKS-S3[^ ]*" | head -1)
    export ECR_STACK=$(echo "$out" | grep -o "ComfyUI-on-EKS-ECR[^ ]*" | head -1)
    export CLOUDFRONT_STACK=$(echo "$out" | grep -o "ComfyUI-on-EKS-CloudFront[^ ]*" | head -1)

    local missing=()
    for v in EKS_CLUSTER_STACK LAMBDA_STACK S3_STACK ECR_STACK CLOUDFRONT_STACK; do
        [ -z "${!v}" ] && missing+=("$v")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "FATAL: '$CDK list' exited 0 but yielded no match for: ${missing[*]}" >&2
        echo "Raw output:" >&2
        echo "$out" >&2
        echo "" >&2
        echo "Usually a CDK CLI version mismatch, credential failure, or synth error." >&2
        exit 1
    fi

    echo "  EKS_CLUSTER_STACK : $EKS_CLUSTER_STACK"
    echo "  LAMBDA_STACK      : $LAMBDA_STACK"
    echo "  S3_STACK          : $S3_STACK"
    echo "  ECR_STACK         : $ECR_STACK"
    echo "  CLOUDFRONT_STACK  : $CLOUDFRONT_STACK"
    echo "==== Stack names resolved ===="
}

# Check if a CFN stack exists (properly quoted, handles empty var).
stack_exists() {
    local stack_name="$1"
    [ -z "$stack_name" ] && return 1
    aws cloudformation describe-stacks --stack-name "$stack_name" &>/dev/null
}
