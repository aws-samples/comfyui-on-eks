#!/usr/bin/env bats
# Regression tests for deploy/destroy script hardening.
# Run: ~/.toolbox/bin/bats auto_deploy/test/hardening.bats

setup() {
    export SCRIPT_DIR="$BATS_TEST_DIRNAME/.."
    export CDK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

    # Create a temp dir for our fake CDK binary
    TEST_TMP="$(mktemp -d)"
    export PATH="$TEST_TMP:$PATH"
}

teardown() {
    rm -rf "$TEST_TMP"
}

# Helper: source env.sh + lib.sh without executing the main scripts
load_lib() {
    # Override ACCOUNT_ID and region so preflight doesn't fail on creds
    export ACCOUNT_ID="123456789012"
    export AWS_DEFAULT_REGION="us-west-2"
    export CDK="$CDK_DIR/node_modules/.bin/cdk"
    source "$SCRIPT_DIR/lib.sh"
}

# --- The core regression test ---
# Reproduces the exact incident: cdk exits 0 but writes schema-mismatch to stderr.
@test "get_stacks_names aborts when cdk list exits 0 with schema error on stderr" {
    # Create a fake cdk that mimics the broken behavior
    cat > "$TEST_TMP/cdk" <<'EOF'
#!/bin/bash
echo "Cloud assembly schema version mismatch: Maximum schema version supported is 48.x.x, but found 54.0.0" >&2
exit 0
EOF
    chmod +x "$TEST_TMP/cdk"

    load_lib
    # Override CDK AFTER load_lib (which sets it to the real binary)
    export CDK="$TEST_TMP/cdk"

    run get_stacks_names
    [ "$status" -ne 0 ]
    [[ "$output" == *"FATAL"* ]]
    [[ "$output" == *"yielded no match"* ]]
}

@test "get_stacks_names succeeds with real repo-local cdk (no stacks deployed)" {
    load_lib

    run get_stacks_names
    [ "$status" -eq 0 ]
    [[ "$output" == *"EKS_CLUSTER_STACK"* ]]
    [[ "$output" == *"ComfyUI-on-EKS-Cluster"* ]]
}

@test "preflight_checks aborts on empty ACCOUNT_ID" {
    export ACCOUNT_ID=""
    export AWS_DEFAULT_REGION="us-west-2"
    export CDK="$CDK_DIR/node_modules/.bin/cdk"
    source "$SCRIPT_DIR/lib.sh"

    run preflight_checks
    [ "$status" -ne 0 ]
    [[ "$output" == *"FATAL"* ]]
    [[ "$output" == *"ACCOUNT_ID empty"* ]]
}

@test "assert_cdk_version aborts on old CDK CLI" {
    cat > "$TEST_TMP/cdk" <<'EOF'
#!/bin/bash
echo "2.1031.2 (build abcdef0)"
EOF
    chmod +x "$TEST_TMP/cdk"
    export ACCOUNT_ID="123456789012"
    export AWS_DEFAULT_REGION="us-west-2"
    source "$SCRIPT_DIR/lib.sh"
    # Override CDK AFTER sourcing lib.sh
    export CDK="$TEST_TMP/cdk"

    run assert_cdk_version
    [ "$status" -ne 0 ]
    [[ "$output" == *"FATAL"* ]]
    [[ "$output" == *"older than required"* ]]
}

@test "CDK_DIR resolves to repo root regardless of CWD" {
    # Source env.sh from a different directory
    cd /tmp
    source "$SCRIPT_DIR/env.sh"
    [ -f "$CDK_DIR/cdk.json" ]
}
