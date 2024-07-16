## Custom Nodes Support

Typically, ComfyUI users use various custom nodes to build their own workflows, often utilizing [ComfyUI-Manager](https://github.com/ltdrdata/ComfyUI-Manager) to conveniently install and manage their custom nodes.

To support custom nodes in the current solution, two things need to be prepared (if you're unfamiliar with the current solution, it's recommended to review the deployment instructions first):

1. Code and Environment: Custom node code is placed in `$HOME/ComfyUI/custom_nodes`, and the environment is prepared by running `pip install -r` on all requirements.txt files in the custom node directories (any dependency conflicts between custom nodes need to be handled separately). Additionally, any system packages required by the custom nodes should be installed. All these operations are performed through the Dockerfile, building an image containing the required custom nodes.
2. Models: Models used by custom nodes are placed in different directories under `s3://comfyui-models-{account_id}-{region}`. This triggers a Lambda function to send commands to all GPU nodes to synchronize the newly uploaded models to local instance store.



Next, we'll use the [Stable Video Diffusion (SVD) - Image to video generation with high FPS](https://comfyworkflows.com/workflows/bf3b455d-ba13-4063-9ab7-ff1de0c9fa75) workflow as an example to illustrate how to support custom nodes (you can also use your own workflow).



### 1. Build image

When loading this workflow, it will display the missing custom nodes. Next, we will build the missing custom nodes into the image.

 <img src="images/miss_custom_nodes.png" style="zoom:50%;" />



There are two ways to build the image:

1. **Build from GitHub**: In the Dockerfile, download the code for each custom node and set up the environment and dependencies separately.
2. **Build locally**: Copy all the custom nodes from your local Dev environment into the image and set up the environment and dependencies.



Before building the image, please switch to the corresponding branch

```shell
git clone https://github.com/aws-samples/comfyui-on-eks ~/comfyui-on-eks
cd ~/comfyui-on-eks && git checkout custom_nodes_demo
```



#### 1.1 Build from GitHub

Install custom nodes and dependencies with `RUN` command in the Dockerfile. You'll need to find the GitHub URLs for all missing custom nodes.

```dockerfile
...
RUN apt-get update && apt-get install -y \
    git \
    python3.10 \
    python3-pip \
    # needed by custom node ComfyUI-VideoHelperSuite
    libsm6 \
    libgl1 \
    libglib2.0-0
...
# Custom nodes demo of https://comfyworkflows.com/workflows/bf3b455d-ba13-4063-9ab7-ff1de0c9fa75

## custom node ComfyUI-Stable-Video-Diffusion
RUN cd /app/ComfyUI/custom_nodes && git clone https://github.com/thecooltechguy/ComfyUI-Stable-Video-Diffusion.git && cd ComfyUI-Stable-Video-Diffusion/ && python3 install.py
## custom node ComfyUI-VideoHelperSuite
RUN cd /app/ComfyUI/custom_nodes && git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && pip3 install -r ComfyUI-VideoHelperSuite/requirements.txt
## custom node ComfyUI-Frame-Interpolation
RUN cd /app/ComfyUI/custom_nodes && git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git && cd ComfyUI-Frame-Interpolation/ && python3 install.py
...
```

Refer to `comfyui-on-eks/comfyui_image/Dockerfile.github` for the complete Dockerfile.

Run following command to build and push Docker image

```shell
region="us-west-2" # Modify the region to your current region.
cd ~/comfyui-on-eks/comfyui_image/ && bash build_and_push.sh $region Dockerfile.github
```

Pros：

* Clear understanding of the installation method, version, and environmental dependencies for each custom node, providing better control over the entire ComfyUI environment.

Cons：

* When there are too many custom nodes, installation and management can be time-consuming, and you need to find the URL for each custom node yourself (on the other hand, this can also be seen as an pros, as it makes you more familiar with the entire ComfyUI environment).



#### 1.2 Build locally 

Often, we use [ComfyUI-Manager](https://github.com/ltdrdata/ComfyUI-Manager) to install missing custom nodes. ComfyUI-Manager hides the installation details, and we cannot clearly know which custom nodes have been installed. In this case, we can build the image by COPY the entire ComfyUI directory (except the input, output, models, etc. directories) into the Dockerfile.

The prerequisite for building the image locally is that you already have a working ComfyUI environment with custom nodes. In the same directory as ComfyUI, create a `.dockerignore` file and add the following content to ignore these directories when building the Docker image

```
ComfyUI/models
ComfyUI/input
ComfyUI/output
ComfyUI/custom_nodes/ComfyUI-Manager
```

Copy the two files `comfyui-on-eks/comfyui_image/Dockerfile.local` and `comfyui-on-eks/comfyui_image/build_and_push.sh` to the same directory as your local `ComfyUI`, like this:

```shell
ubuntu@comfyui:~$ ll
-rwxrwxr-x  1 ubuntu ubuntu       792 Jul 16 10:27 build_and_push.sh*
drwxrwxr-x 19 ubuntu ubuntu      4096 Jul 15 08:10 ComfyUI/
-rw-rw-r--  1 ubuntu ubuntu       784 Jul 16 10:41 Dockerfile.local
-rw-rw-r--  1 ubuntu ubuntu        81 Jul 16 10:45 .dockerignore
...
```

The `Dockerfile.local` builds the image by COPY the directory

```dockerfile
...
# Python Evn
RUN pip3 install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu121
COPY ComfyUI /app/ComfyUI
RUN pip3 install -r /app/ComfyUI/requirements.txt

# Custom Nodes Env, may encounter some conflicts
RUN find /app/ComfyUI/custom_nodes -maxdepth 2 -name "requirements.txt"|xargs -I {} pip install -r {}
...
```

Refer to `comfyui-on-eks/comfyui_image/Dockerfile.local` for the complete Dockerfile.

Run the following command to build and upload the Docker image

```shell
region="us-west-2" # Modify the region to your current region.
bash build_and_push.sh $region Dockerfile.local
```

Pros：

* You can easily and quickly build your local Dev environment into an image for deployment, without paying attention to the installation, version, and dependency details of custom nodes when there are many of them.

Cons：

* Not paying attention to the deployment environment of custom nodes may cause conflicts or missing dependencies, which need to be manually tested and resolved.



### 2. Upload Models

Upload all the models needed for the workflow to the `s3://comfyui-models-{account_id}-{region}` corresponding directory using your preferred method. The GPU nodes will automatically sync from S3 (triggered by Lambda). If the models are large and numerous, you may need to wait for some time. You can log into the GPU nodes using the `aws ssm start-session --target ${instance_id}` command and use the `ps` command to check the progress of the `aws s3 sync` process.



### 3. Test the Docker Image Locally (Optional, Recommended)

Since there are many types of custom nodes with different dependencies and versions, the runtime environment is quite complex. It is recommended to test the Docker image locally after building it in Step 1 to ensure it runs correctly.

Refer to the code in `comfyui-on-eks/comfyui_image/test_docker_image_locally.sh`. Prepare the models and input directories (assuming the models and input images are stored in `/home/ubuntu/ComfyUI/models` and `/home/ubuntu/ComfyUI/input` respectively), and run the script to test the Docker image

```shell
comfyui-on-eks/comfyui_image/test_docker_image_locally.sh
```



### 4. Rolling Update K8S pods

Use your preferred method to perform a rolling update of the image for the online K8S pods, and then test the service.

 ![svd-custom-nodes](/Users/ray/comfyui-on-eks-aws-samples/images/svd-custom-nodes.gif)



---



## Solution Features

The solution is characterized by the following features:

1. **Infrastructure as Code (IaC) Deployment**: We employ a minimalist approach to operations and maintenance. Using [AWS Cloud Development Kit (AWS CDK)](https://aws.amazon.com/cdk/) and [Amazon EKS Blueprints](https://aws-quickstart.github.io/cdk-eks-blueprints/), we manage the [Amazon Elastic Kubernetes Service (Amazon EKS)](https://aws.amazon.com/eks/) clusters that host and run ComfyUI.
2. **Dynamic Scaling with Karpenter**: Leveraging the capabilities of [Karpenter](https://karpenter.sh/), we customize node scaling strategies to meet business needs.
3. **Cost Savings with Amazon Spot Instances**: We utilize [Amazon Spot instances](https://aws.amazon.com/ec2/spot/) to reduce the costs of GPU instances.
4. **Optimized Use of GPU Instance Store**: By fully utilizing the [instance store](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/InstanceStorage.html) of GPU instances, we maximize performance for model loading and switching while minimizing the costs associated with model storage and transfer.
5. **Direct Image Writing with S3 CSI Driver**: Images generated are directly written to [Amazon S3](https://aws.amazon.com/s3/) using the [S3 CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/s3-csi.html), reducing storage costs.
6. **Accelerated Dynamic Requests with Amazon CloudFront**: To facilitate the use of the platform by art studios across different regions, we use [Amazon CloudFront](https://aws.amazon.com/cloudfront/) for faster dynamic request processing.
7. **Serverless Event-Triggered Model Synchronization**: When models are uploaded to or deleted from S3, serverless event triggers activate, syncing the model directory data across worker nodes.



## Solution Architecture

![Architecture](images/arch.png)

The solution's architecture is structured into two distinct phases: the deployment phase and the user interaction phase.

**Deployment Phase**

1. **Model Storage in S3**: ComfyUI's models are stored in **S3 for models**, following the same directory structure as the native `ComfyUI/models` directory.
2. **GPU Node Initialization in EKS Cluster**: When GPU nodes in the EKS cluster are initiated, they format the local Instance store and synchronize the models from S3 to the local Instance store using user-data scripts.
3. **Running ComfyUI Pods in EKS**: Pods operating ComfyUI effectively link the Instance store directory on the node to the pod's internal models directory, facilitating seamless model access and loading.
4. **Model Sync with Lambda Trigger**: When models are uploaded to or deleted from S3, a Lambda function is triggered to synchronize the models from S3 to the local Instance store on all GPU nodes via SSM commands.
5. **Output Mapping to S3**: Pods running ComfyUI map the `ComfyUI/output` directory to **S3 for outputs** with PVC (Persistent Volume Claim) methods.



**User Interaction Phase**

1. **Request Routing**: When a user request reaches the EKS pod through CloudFront --> ALB, the pod first loads the model from the Instance store.
2. **Image Storage Post-Inference**: After inference, the pod stores the image in the `ComfyUI/output` directory, which is directly written to S3 using the S3 CSI driver.
3. **Performance Advantages of Instance Store**: Thanks to the performance benefits of the Instance store, the time taken for initial model loading and model switching is significantly reduced.

You can find the deployment code with following address, for detailed deployment instructions, please refer to the following section

```shell
https://github.com/aws-samples/comfyui-on-eks
```



## Image Generation

Once deployed, you can access and use the ComfyUI frontend directly through a browser by visiting the domain name of CloudFront or the domain name of Kubernetes Ingress.

![ComfyUI-Web](images/comfyui-web.png)

You can also interact with ComfyUI by saving its workflow as a JSON file that's callable via an API. This method facilitates better integration with your own platforms and systems. For reference on how to make these calls, see the code in `comfyui-on-eks/test/invoke_comfyui_api.py`.

![ComfyUI-API](images/comfyui-api.png)



## Deployment Instructions

### 1. Prerequisites

This solution assumes that you have already installed, deployed, and are familiar with the following tools:

* [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html): latest version
* [eksctl](https://eksctl.io/installation/)
* [kubectl](https://kubernetes.io/docs/tasks/tools/)
* [Docker](https://docs.docker.com/engine/install/)
* [npm](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm/)
* [CDK](https://docs.aws.amazon.com/cdk/v2/guide/getting_started.html): latest version



Make sure that you have enough vCPU quota for G instances. (At least 8 vCPU for a g5.2xl/g4dn.2x used in this guidance)



Download the code, **checkout the branch, install rpm packages, and check the environment**

```shell
git clone https://github.com/aws-samples/comfyui-on-eks ~/comfyui-on-eks
cd ~/comfyui-on-eks && git checkout custom_nodes_demo
npm install
npm list
cdk list
```

Run `npm list` to ensure following packages are installed

```
comfyui-on-eks@0.3.0 ~/comfyui-on-eks
├── @aws-quickstart/eks-blueprints@1.15.1
├── aws-cdk-lib@2.147.3
├── aws-cdk@2.147.3
└── ...
```

Run `cdk list` to ensure the environment is all set, you will have following CloudFormation stack to deploy

```
Comfyui-Cluster
CloudFrontEntry
LambdaModelsSync
S3Storage
ComfyuiEcrRepo
```

### 2. Deploy EKS Cluster

Run the following command

```shell
cd ~/comfyui-on-eks && cdk deploy Comfyui-Cluster 
```

CloudFormation will create a stack named `Comfyui-Cluster` to deploy all the resources required for the EKS Cluster. This process typically takes around 20 to 30 minutes to complete.

The configuration details for the `Comfyui-Cluster Stack` can be explored in the file `comfyui-on-eks/lib/comfyui-on-eks-stack.ts`. Essential elements to focus on are as follows:

1. The EKS cluster is constructed using the EKS Blueprints framework, `blueprints.EksBlueprint.builder()`.
2. A selection of Addons from EKS Blueprints are installed for the EKS cluster:
   - `AwsLoadBalancerControllerAddOn`: Manages the Kubernetes ingress ALB.
   - `SSMAgentAddOn`: Enables the use of SSM on EKS nodes for remote login or command execution.
   - `Karpenter`: Facilitates the scaling of EKS nodes.
   - `GpuOperatorAddon`: Supports the operation of GPU nodes.
3. S3 permissions are added to the EKS nodes to enable the synchronization of model files from S3 to the local instance store.
4. Rather than specifying a nodegroup for GPU instances, we establish a nodegroup with CPU instances dedicated to lightweight applications, which facilitates the operation of Addon pods. The management and scaling of GPU instances are exclusively handled by Karpenter.

Upon successful deployment, the CDK outputs will present a `ConfigCommand`. This command is used to update the configuration, enabling access to the EKS cluster via kubectl.

![eks-blueprints-cmd](images/eks-blueprints-cmd.png)

**Execute the above ConfigCommand to authorize kubectl to access the EKS cluster**

To verify that kubectl has been granted access to the EKS cluster, execute the following command:

```shell
kubectl get svc
```

Now, the deployment of the EKS cluster is complete.

Also, note that EKS Blueprints has outputted `KarpenterInstanceNodeRole`, which is the role for the nodes managed by Karpenter. Please record this role, as it will be configured in section 5.2.



### 3. Deploy an S3 bucket for storing models and set up Lambda for dynamic model synchronization

Run the following command:

```shell
cd ~/comfyui-on-eks && cdk deploy LambdaModelsSync
```

The `LambdaModelsSync` stack primarily creates the following resources:

* S3 bucket: The S3 bucket is named following the format `comfyui-models-{account_id}-{region}`, it's used to store ComfyUI models.
* Lambda function, along with its associated role and event source: The Lambda function, named `comfy-models-sync`, is designed to trigger the synchronization of models from the S3 bucket to local storage on GPU instances whenever models are uploaded to or deleted from S3.

Essential details in the `LambdaModelsSync` resource configuration, located in `comfyui-on-eks/lib/lambda-models-sync.ts`, include:

1. The code for the Lambda function is located in `comfyui-on-eks/lib/ComfyModelsSyncLambda/model_sync.py`.
2. The Lambda is used to filter all GPU instances within the ComfyUI EKS Cluster using tags, when create or remove events occur in the S3 bucket storing models, it uses SSM to command all GPU instances to synchronize the models from S3 to their local directories (instance store).



Once the S3 for Models and Lambda are deployed, the S3 bucket will initially be empty. Execute the following command to initialize the S3 bucket and download the SDXL model for testing purposes.

Note: **The following command will download the SDXL model to your local machine and upload it to S3. Ensure you have enough disk space (20GB). Alternatively, you can upload the model to the corresponding S3 directory using your preferred method.**

```shell
region="us-west-2" # Modify the region to your current region.
cd ~/comfyui-on-eks/test/ && bash init_s3_for_models.sh $region
```

There's no need to wait for the model to finish downloading and uploading to S3. You can proceed with the following steps, just ensure the model is uploaded to S3 before starting the GPU nodes.



### 4. Deploy S3 bucket for storing inputs to ComfyUI and outputs from ComfyUI

Run the following command

```shell
cd ~/comfyui-on-eks && cdk deploy S3Storage
```



The `S3Storage` stack just creates two S3 buckets, named following the pattern `comfyui-outputs-{account_id}-{region}` and `comfyui-inputs-{account_id}-{region}`, which is used to store inputs and outputs.



### 5. Deploy ComfyUI Workload

The ComfyUI workload is deployed through Kubernetes. Please follow the steps below.

#### 5.1 Build and Push ComfyUI Docker Image

Refer to the above Custom Nodes Support section.

#### 5.2 Deploy Karpenter for Managing GPU Instance Scaling

Get the KarpenterInstanceNodeRole in Section 2 and run the following command to deploy Karpenter:

**Run on Linux**

```shell
KarpenterInstanceNodeRole="Comfyui-Cluster-ComfyuiClusterkarpenternoderoleE627-juyEInBqoNtU" # Modify the role to your own.
sed -i "s/role: KarpenterInstanceNodeRole.*/role: $KarpenterInstanceNodeRole/g" comfyui-on-eks/manifests/Karpenter/karpenter_v1beta1.yaml
kubectl apply -f comfyui-on-eks/manifests/Karpenter/karpenter_v1beta1.yaml
```

**Run on MacOS**

```shell
KarpenterInstanceNodeRole="Comfyui-Cluster-ComfyuiClusterkarpenternoderoleE627-juyEInBqoNtU" # Modify the role to your own.
sed -i '' "s/role: KarpenterInstanceNodeRole.*/role: $KarpenterInstanceNodeRole/g" comfyui-on-eks/manifests/Karpenter/karpenter_v1beta1.yaml
kubectl apply -f comfyui-on-eks/manifests/Karpenter/karpenter_v1beta1.yaml
```

To verify the deployment of Karpenter, use this command:

```shell
kubectl describe karpenter
```

Key considerations for Karpenter's deployment: 

1. We use both g5.2xlarge and g4dn.2xlarge instances, along with both `on-demand` and `spot` instances.
2. Initialization of GPU instances launched by Karpenter in userData:
   1. Formatting the instance store local disk and mounting it to the `/comfyui-models` directory.
   2. Synchronizing model files stored on S3 to the local instance store.

The KarpenterInstanceNodeRole needs an additional S3 access permission to allow GPU nodes to sync files from S3. Execute the following command:

```shell
KarpenterInstanceNodeRole="Comfyui-Cluster-ComfyuiClusterkarpenternoderoleE627-juyEInBqoNtU" # Modify the role to your own.
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess --role-name $KarpenterInstanceNodeRole
```



#### 5.3 Deploy S3 PV and PVC to store generated images

Execute the following command to deploy the PV and PVC for S3 CSI.

**Run on Linux**

```shell
region="us-west-2" # Modify the region to your current region.
account=$(aws sts get-caller-identity --query Account --output text)
sed -i "s/region .*/region $region/g" comfyui-on-eks/manifests/PersistentVolume/sd-outputs-s3.yaml
sed -i "s/bucketName: .*/bucketName: comfyui-outputs-$account-$region/g" comfyui-on-eks/manifests/PersistentVolume/sd-outputs-s3.yaml
sed -i "s/region .*/region $region/g" comfyui-on-eks/manifests/PersistentVolume/sd-inputs-s3.yaml
sed -i "s/bucketName: .*/bucketName: comfyui-inputs-$account-$region/g" comfyui-on-eks/manifests/PersistentVolume/sd-inputs-s3.yaml
kubectl apply -f comfyui-on-eks/manifests/PersistentVolume/
```

**Run on MacOS**

```shell
region="us-west-2" # Modify the region to your current region.
account=$(aws sts get-caller-identity --query Account --output text)
sed -i '' "s/region .*/region $region/g" comfyui-on-eks/manifests/PersistentVolume/sd-outputs-s3.yaml
sed -i '' "s/bucketName: .*/bucketName: comfyui-outputs-$account-$region/g" comfyui-on-eks/manifests/PersistentVolume/sd-outputs-s3.yaml
sed -i '' "s/region .*/region $region/g" comfyui-on-eks/manifests/PersistentVolume/sd-inputs-s3.yaml
sed -i '' "s/bucketName: .*/bucketName: comfyui-inputs-$account-$region/g" comfyui-on-eks/manifests/PersistentVolume/sd-inputs-s3.yaml
kubectl apply -f comfyui-on-eks/manifests/PersistentVolume/
```



#### 5.4 Deploy EKS S3 CSI Driver

Run the following command to add your IAM principal to EKS cluster

```shell
identity=$(aws sts get-caller-identity --query 'Arn' --output text --no-cli-pager)
if [[ $identity == *"assumed-role"* ]]; then
    role_name=$(echo $identity | cut -d'/' -f2)
    account_id=$(echo $identity | cut -d':' -f5)
    identity="arn:aws:iam::$account_id:role/$role_name"
fi
aws eks update-cluster-config --name Comfyui-Cluster --access-config authenticationMode=API_AND_CONFIG_MAP
aws eks create-access-entry --cluster-name Comfyui-Cluster --principal-arn $identity --type STANDARD --username comfyui-user
aws eks associate-access-policy --cluster-name Comfyui-Cluster --principal-arn $identity --access-scope type=cluster --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy
```

Run the following command to ensure that your IAM principal has been added

```shell
aws eks list-access-entries --cluster-name Comfyui-Cluster|grep $identity
```



Execute the following command to create a role and service account for the S3 CSI driver, enabling it to read and write to S3.

```shell
region="us-west-2" # Modify the region to your current region.
account=$(aws sts get-caller-identity --query Account --output text)
ROLE_NAME=EKS-S3-CSI-DriverRole-$account-$region
POLICY_ARN=arn:aws:iam::aws:policy/AmazonS3FullAccess
eksctl create iamserviceaccount \
    --name s3-csi-driver-sa \
    --namespace kube-system \
    --cluster Comfyui-Cluster \
    --attach-policy-arn $POLICY_ARN \
    --approve \
    --role-name $ROLE_NAME \
    --region $region
```



Run the following command to install  `aws-mountpoint-s3-csi-driver` Addon

```shell
region="us-west-2" # Modify the region to your current region.
account=$(aws sts get-caller-identity --query Account --output text)
eksctl create addon --name aws-mountpoint-s3-csi-driver --version v1.0.0-eksbuild.1 --cluster Comfyui-Cluster --service-account-role-arn "arn:aws:iam::${account}:role/EKS-S3-CSI-DriverRole-${account}-${region}" --force
```



#### 5.5 Deploy ComfyUI Deployment and Service

Run the following command to replace docker image

**Run on Linux**

```shell
region="us-west-2" # Modify the region to your current region.
account=$(aws sts get-caller-identity --query Account --output text)
sed -i "s/image: .*/image: ${account}.dkr.ecr.${region}.amazonaws.com\/comfyui-images:latest/g" comfyui-on-eks/manifests/ComfyUI/comfyui_deployment.yaml
```

**Run on MacOS**

```shell
region="us-west-2" # Modify the region to your current region.
account=$(aws sts get-caller-identity --query Account --output text)
sed -i '' "s/image: .*/image: ${account}.dkr.ecr.${region}.amazonaws.com\/comfyui-images:latest/g" comfyui-on-eks/manifests/ComfyUI/comfyui_deployment.yaml
```

Run the following command to deploy ComfyUI Deployment and Service

```shell
kubectl apply -f comfyui-on-eks/manifests/ComfyUI
```

A few points to note about ComfyUI Deployment and Service:

1. ComfyUI pod scaling time depends on the instance type, if there are insufficient nodes, Karpenter will need to provision nodes for initialization before pods get scheduled, once images sync, pods become schedulable. You can check Kubernetes events and Karpenter logs with following command:

   ```shell
   podName=$(kubectl get pods -n karpenter|tail -1|awk '{print $1}')
   kubectl logs -f $podName -n karpenter
   ```

   ```shell
   kubectl get events --watch
   ```

   If you see  ERROR log like following

   ```
   AuthFailure.ServiceLinkedRoleCreationNotPermitted: The provided credentials do not have permission to create the service-linked role for EC2 Spot Instances.
   ```

   You need to create a service linked role

   ```shell
   aws iam create-service-linked-role --aws-service-name spot.amazonaws.com
   ```

   

2. Different GPU instance types have different Instance Store sizes.  If the total model size in S3 exceeds the Instance Store size, you'll need to use other method to manage model storage.



When ComfyUI pod is running, execute the following command to check the log:

```shell
podName=$(kubectl get pods |tail -1|awk '{print $1}')
kubectl logs -f $podName
```



### 6. Test ComfyUI on EKS

#### 6.1 API Test

Test with API, run the following command in the `comfyui-on-eks/test` directory:

**Run on Linux**

```shell
ingress_address=$(kubectl get ingress|grep comfyui-ingress|awk '{print $4}')
sed -i "s/SERVER_ADDRESS = .*/SERVER_ADDRESS = \"${ingress_address}\"/g" invoke_comfyui_api.py
sed -i "s/HTTPS = .*/HTTPS = False/g" invoke_comfyui_api.py
sed -i "s/SHOW_IMAGES = .*/SHOW_IMAGES = False/g" invoke_comfyui_api.py
./invoke_comfyui_api.py sdxl_refiner_prompt_api.json
```

**Run on MacOS**

```shell
ingress_address=$(kubectl get ingress|grep comfyui-ingress|awk '{print $4}')
sed -i '' "s/SERVER_ADDRESS = .*/SERVER_ADDRESS = \"${ingress_address}\"/g" invoke_comfyui_api.py
sed -i '' "s/HTTPS = .*/HTTPS = False/g" invoke_comfyui_api.py
sed -i '' "s/SHOW_IMAGES = .*/SHOW_IMAGES = False/g" invoke_comfyui_api.py
./invoke_comfyui_api.py sdxl_refiner_prompt_api.json
```

Refer to `comfyui-on-eks/test/invoke_comfyui_api.py` for the API call logic. Note the following points:

1. The API call executes the ComfyUI workflow stored in `comfyui-on-eks/test/sdxl_refiner_prompt_api.json`. 
2. Two models are used: sd_xl_base_1.0.safetensors and sd_xl_refiner_1.0.safetensors.
3. You can modify the prompt in sdxl_refiner_prompt_api.json or invoke_comfyui_api.py to test different inputs.



#### 6.2 Test with browser

Run the following command to get the K8S ingress address:

```shell
kubectl get ingress
```

Access the ingress address through a web browser.



The deployment and testing of ComfyUI on EKS is now complete. Next we will connect the EKS cluster to CloudFront for edge acceleration.



### 7. Deploy CloudFront for edge acceleration (Optional)

Execute the following command in the `comfyui-on-eks` directory to connect the Kubernetes ingress to CloudFront:

```shell
cdk deploy CloudFrontEntry
```

The `CloudFrontEntry` stack can be referenced in `comfyui-on-eks/lib/cloudfront-entry.ts`. Pay attention to the following:

1. The EKS Ingress ALB is found by tag.
2. The EKS Ingress ALB is set as the CloudFront Distribution origin.
3. The ComfyUI ALB ingress is only configured for HTTP, so the CloudFront Origin Protocol Policy is set to HTTP_ONLY.  
4. Caching is disabled for dynamic requests by setting the cache policy to CACHING_DISABLED.



After deployment completes, Outputs will be printed including the CloudFront URL `CloudFrontEntry.cloudFrontEntryUrl`. Refer to section 6.6 for testing via the API or browser.



## Delete All Resources

Run the following command to delete all Kubernetes resources:

```shell
kubectl delete -f comfyui-on-eks/manifests/ComfyUI/
kubectl delete -f comfyui-on-eks/manifests/PersistentVolume/
kubectl delete -f comfyui-on-eks/manifests/Karpenter/
```



Run the following command to delete all deployed resources:

```shell
aws ecr batch-delete-image --repository-name comfyui-images --image-ids imageTag=latest
cdk destroy ComfyuiEcrRepo
cdk destroy CloudFrontEntry
cdk destroy S3Storage
cdk destroy LambdaModelsSync
cdk destroy Comfyui-Cluster
```



## Cost Analysis

Assuming the following scenario:

* Deploying 1 g5.2xlarge instance for image generation
* Generating a 1024x1024 image takes average 9 seconds, with average size of 1.5MB
* Daily usage time is 8 hours, with 20 days of usage per month
* The number of images that can be generated per month is 8 x 20 x 3600 / 9 = 64000
* The total size of images to be stored each month is 64000 x 1.5MB / 1000 = 96GB
* DTO traffic size is approximately 100GB (96GB + HTTP requests)
* ComfyUI images of different versions total 20GB

The total cost of deploying this solution in us-west-2 is approximately **$441.878 (using CloudFront for external access) or $442.378 (using ALB for external access)**

| Service                                | Pricing | Detail                                                       |
| -------------------------------------- | ------- | ------------------------------------------------------------ |
| Amazon EKS (Control Plane)             | $73     | Fixed Pricing                                                |
| Amazon EC2 (ComfyUI-EKS-GPU-Node)      | $193.92 | 1 g5.2xlarge instance (On-Demand)<br />1 x $1.212/h x 8h x 20days/month |
| Amazon EC2 (Comfyui-EKS-LW-Node)       | $137.68 | 2 t3a.xlarge instance (1yr RI No upfront since it's fixed long running)<br />2 x $68.84/month |
| Amazon S3 (Standard) for models        | $2.3    | Total models size 100GB x $0.023/GB                          |
| Amazon S3 (Standard) for output images | $2.208  | 64000 images/month x 1.5MB/image / 1000 x $0.023/GB<br />Rotate all images per month |
| Amazon ECR                             | $2      | 20GB different versions of images x $0.1/GB                  |
| AWS ALB                                | $22.27  | 1 ALB $16.43 fixed hourly charges<br />+<br />$0.008/LCU/h x 730h x 1LCU x 1ALB |
| DTO (use ALB)                          | $9      | 100GB x $0.09/GB                                             |
| DTO (use CloudFront)                   | $8.5    | 100GB x $0.085/GB                                            |
