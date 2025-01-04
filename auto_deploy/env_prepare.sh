#!/bin/bash

source ./env.sh

PROJECT_NAME=$1

install_dependencies() {
    sudo apt-get update
    sudo apt-get install -yy unzip curl
}

install_awscli() {
    echo "==== Start installing AWS CLI ===="
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    if ! command -v aws &> /dev/null; then
        echo "AWS CLI not found, installing..."
        sudo ./aws/install
    else
        echo "AWS CLI is already installed, updating..."
        sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
    fi
    rm -rf awscliv2.zip aws
    aws --version
    if [[ $? -ne 0 ]]
    then
        echo "AWS CLI installation failed."
        exit 1
    fi
    iam_entity=$(aws sts get-caller-identity --query 'Arn' --output text --no-cli-pager)
    if [[ $? -ne 0 ]]
    then
        # Get user input for choosing 1. aws configure 2. Add iam role later
        echo "AWS CLI is not configured. Please choose one of the following options:"
        echo "1. Run 'aws configure' to configure AWS CLI"
        echo "2. Add IAM role later"
        read -p "Enter your choice (1/2): " choice
        if [[ $choice -eq 1 ]]
        then
            aws configure
        fi
    else
        echo "Make sure current IAM entity '$iam_entity' has necessary permissions to create resources."
    fi
    echo "==== Finish installing AWS CLI ===="
}

install_eksctl() {
    echo "==== Start installing eksctl ===="
    ARCH=amd64
    PLATFORM=$(uname -s)_$ARCH
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo mv /tmp/eksctl /usr/local/bin
    eksctl version
    if [[ $? -ne 0 ]]
    then
        echo "eksctl installation failed."
        exit 1
    fi
    echo "==== Finish installing eksctl ===="
}

install_kubectl() {
    echo "==== Start installing kubectl ===="
    curl -sLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    kubectl version --client
    if [[ $? -ne 0 ]]
    then
        echo "kubectl installation failed."
        exit 1
    fi
    echo "==== Finish installing kubectl ===="
}

install_docker() {
    echo "==== Start installing Docker ===="
    # Add Docker's official GPG key:
    sudo apt-get -yy update
    sudo apt-get install -yy ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get -yy update
    sudo apt-get install -yy docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker $USER
    sudo docker images
    if [[ $? -ne 0 ]]
    then
        echo "docker installation failed."
        exit 1
    fi
    echo "==== Finish installing Docker ===="
}

install_npm() {
    echo "==== Start installing npm ===="

    # Install nvm
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
    nvm --version

    # Install lts version of node
    nvm install --lts
    nvm use --lts
    if [[ $? -ne 0 ]]
    then
        echo "npm installation failed."
        exit 1
    fi
    echo "Node version: $(node -v)"
    echo "NPM version: $(npm -v)"
    echo "==== Finish installing npm ===="
}

install_cdk() {
    npm install -g aws-cdk@2.173.2
}

prepare_code_dependency() {
    echo "==== Start preparing code ===="
    cd $CDK_DIR && npm install --force && npm list && cdk bootstrap && cdk list
    if [[ $? -ne 0 ]]
    then
        echo "Code preparation failed."
        exit 1
    fi
    if [[ -z $PROJECT_NAME ]]
    then
        echo "PROJECT_NAME is not provided, use default empty."
    else
        sed -i "s/export const PROJECT_NAME =.*/export const PROJECT_NAME = '${PROJECT_NAME}'/g" $CDK_DIR/env.ts
        sed -i "s/export PROJECT_NAME=.*/export PROJECT_NAME='${PROJECT_NAME}'/g" $CDK_DIR/auto_deploy/env.sh
        echo "Stacks after updating PROJECT_NAME: $PROJECT_NAME"
        cd $CDK_DIR && cdk list
    fi
    echo "==== Finish preparing code ===="
}

install_dependencies
install_awscli
install_eksctl
install_kubectl
install_docker
install_npm
install_cdk
prepare_code_dependency
