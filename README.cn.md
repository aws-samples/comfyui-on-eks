## Custom Nodes 支持

通常 ComfyUI 的用户会使用各种不同的 custom nodes 来构建自己的 workflow，在这过程中也会使用 [ComfyUI-Manager](https://github.com/ltdrdata/ComfyUI-Manager) 来方便地安装和管理自己的 custom nodes。

当前的 solution 要支持 custom nodes 只需要准备两样东西（如果你还不熟悉当前的 solution，建议先浏览一遍部署过程）：

1. 代码和环境：custom nodes 的代码放在 `$HOME/ComfyUI/custom_nodes` 下，环境通过 `pip install -r` 所有 custom nodes 目录下的 requirements.txt 来准备（如果有一些 custom nodes 的依赖冲突需要单独处理），同时安装一些 custom nodes 会用到的系统软件包。以上操作均通过 Dockerfile 来实现，构建一个包含了所需 custom nodes 的镜像。
2. 模型：custom nodes 用到的模型放到 `s3://comfyui-models-{account_id}-{region}` 下的不同目录即可，会触发 Lambda 给所有 GPU nodes 发送指令将新上传的模型同步到本地。



接下来以 [Stable Video Diffusion (SVD) - Image to video generation with high FPS](https://comfyworkflows.com/workflows/bf3b455d-ba13-4063-9ab7-ff1de0c9fa75) 这个 workflow 为例介绍如何支持 custom nodes（你也可以使用你自己的 workflow）



### 1. 构建镜像

当 load 这个 workflow 的时候会显示缺失的 custom nodes，我们接下来将会把缺失的 custom nodes 打进镜像中去

 <img src="images/miss_custom_nodes.png" style="zoom:50%;" />

有两种方式构建镜像：

1. 从 Github 构建镜像：在 Dockerfile 中为每个 custom nodes 下载代码，并准备环境和依赖
2. 从本地构建镜像：将本地的 Dev 环境所有 custom nodes 都 COPY 到镜像中，并准备环境和依赖



构建镜像前请切换到对应 branch

```shell
git clone https://github.com/aws-samples/comfyui-on-eks ~/comfyui-on-eks
cd ~/comfyui-on-eks && git checkout custom_nodes_demo
```



#### 1.1 从 Github 构建镜像

通过在 Dockerfile 中使用 RUN 命令来安装 custom nodes 和依赖，需要先找到缺失的 custom nodes 的 Github 地址

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

完整 Dockerfile 参考 `comfyui-on-eks/comfyui_image/Dockerfile.github`

执行以下命令构建并上传 Docker image

```shell
region="us-west-2" # Modify the region to your current region.
cd ~/comfyui-on-eks/comfyui_image/ && bash build_and_push.sh $region Dockerfile.github
```

优点：

* 清楚了解每个 custom nodes 的安装方式、版本、环境依赖等，对整个 ComfyUI 环境更加可控

缺点：

* 当 custom nodes 数量太多时安装管理比较耗时，并且需要自己找到每个 custom node 的地址（另一方面说也是优点，对整个 ComfyUI 环境更加熟悉）



#### 1.2 从本地构建镜像 

很多时候我们通过 [ComfyUI-Manager](https://github.com/ltdrdata/ComfyUI-Manager) 来安装缺失的 custom nodes，ComfyUI-Manager 屏蔽了安装的细节，甚至我们也无法清楚知道安装了哪些 custome nodes，此时我们可以通过在 Dockerfile 中 COPY 整个 ComfyUI 目录（除去 input、output、models 等目录）来构建镜像

从本地构建镜像的前提是本地已经有可运行 custom nodes 的 ComfyUI 环境，在 ComfyUI 同级目录下创建 `.dockerignore` 文件，添加以下内容，在 build docker image 时 COPY 目录忽略以下目录内容

```
ComfyUI/models
ComfyUI/input
ComfyUI/output
ComfyUI/custom_nodes/ComfyUI-Manager
```

将 `comfyui-on-eks/comfyui_image/Dockerfile.local` 和 `comfyui-on-eks/comfyui_image/build_and_push.sh` 两个文件 `cp` 到本地 `ComfyUI` 的同级目录，如

```shell
ubuntu@comfyui:~$ ll
-rwxrwxr-x  1 ubuntu ubuntu       792 Jul 16 10:27 build_and_push.sh*
drwxrwxr-x 19 ubuntu ubuntu      4096 Jul 15 08:10 ComfyUI/
-rw-rw-r--  1 ubuntu ubuntu       784 Jul 16 10:41 Dockerfile.local
-rw-rw-r--  1 ubuntu ubuntu        81 Jul 16 10:45 .dockerignore
...
```

`Dockerfile.local` 中通过 COPY 的方式将代码 build 进 image

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

完整 Dockerfile 参考 `comfyui-on-eks/comfyui_image/Dockerfile.local`

执行以下命令构建并上传 Docker image

```shell
region="us-west-2" # Modify the region to your current region.
bash build_and_push.sh $region Dockerfile.local
```

优点：

* 可以很方便快速地将本地 Dev 环境 build 成镜像发布部署，当 custom nodes 很多时不需要关注 custom nodes 安装、版本和依赖的细节

缺点：

* 不关注 custom nodes 的部署环境可能会有冲突问题，以及依赖缺失问题，需要手动测试解决



### 2. 上传模型

用你熟悉的方法将 workflow 中需要的所有模型上传到 `s3://comfyui-models-{account_id}-{region}` 下对应目录即可，GPU nodes 会自动从 S3 同步（Lambda 触发），如果模型较大且数量较多则需要多等一段时间，可以通过 `aws ssm start-session --target ${instance_id}` 命令登录 GPU nodes，用 `ps` 命令查看 `aws s3 sync` 的同步进程。



### 3. 本地测试 docker image（可选，推荐）

由于 custom nodes 的种类很多，依赖和版本各不相同，运行环境比较复杂，建议在第1步 build 完 image 后，在本地测试 docker image 是否运行正常。

参考 `comfyui-on-eks/comfyui_image/test_docker_image_locally.sh` 这里的代码，准备好 models 和 input 目录（假设本地的 `/home/ubuntu/ComfyUI/models` 和 `/home/ubuntu/ComfyUI/input` 目录分别存放用到的模型和上传的图片），执行脚本运行 docker 进行测试

```shell
comfyui-on-eks/comfyui_image/test_docker_image_locally.sh
```



### 4. Rolling Update K8S pods

用你熟悉的方法 rolling update 线上的 K8S pods 的 image 后，对服务进行测试

 ![svd-custom-nodes](images/svd-custom-nodes.gif)



---



## 方案特点

我们根据实际的使用场景设计方案，总结有以下特点：

* IaC 方式部署，极简运维，使用 [AWS Cloud Development Kit (AWS CDK)](https://aws.amazon.com/cdk/) 和 [Amazon EKS Bluprints](https://aws-quickstart.github.io/cdk-eks-blueprints/) 来管理 [Amazon Elastic Kubernetes Service (Amazon EKS)](https://aws.amazon.com/eks/) 集群以承载运行 ComfyUI。
* 基于 [Karpenter](https://karpenter.sh/) 的能力动态伸缩，自定义节点伸缩策略以适应业务需求。
* 通过 [Amazon Spot instances](https://aws.amazon.com/ec2/spot/) 实例节省 GPU 实例成本。
* 充分利用 GPU 实例的 [instance store](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/InstanceStorage.html)，最大化模型加载和切换的性能，同时最小化模型存储和传输的成本。
* 利用 [S3 CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/s3-csi.html) 将生成的图片直接写入 [Amazon S3](https://aws.amazon.com/s3/)，降低存储成本。
* 利用 [Amazon CloudFront](https://aws.amazon.com/cloudfront/) 边缘节点加速动态请求，以满足跨地区美术工作室共用平台的场景。(Optional)
* 通过 Serverless 事件触发的方式，当模型上传 S3 或在 S3 删除时，触发工作节点同步模型目录数据。



## 方案架构

![Architecture](images/arch.png)

分为两个部分介绍方案架构：

**方案部署过程**

1. ComfyUI 的模型存放在 S3 for models，目录结构和原生的 ` ComfyUI/models` 目录结构一致。
2. EKS 集群的 GPU node 在拉起初始化时，会格式化本地的 Instance store，并通过 user-data 从 S3 将模型同步到本地 Instance store。
3. EKS 运行 ComfyUI 的 pod 会将 node 上的 Instance store 目录映射到 pod 里的 models 目录，以实现模型的读取加载。
4. 当有模型上传到 S3 或从 S3 删除时，会触发 Lambda 对所有 GPU node 通过 SSM 执行命令再次同步 S3 上的模型到本地 Instance store。
5. EKS 运行 ComfyUI 的 pod 会通过 PVC 的方式将 `ComfyUI/output` 目录映射到 S3 for outputs。

**用户使用过程**

1. 当用户请求通过 CloudFront --> ALB 到达 EKS pod 时，pod 会首先从 Instance store 加载模型。
2. pod 推理完成后会将图片存放在 `ComfyUI/output` 目录，通过 S3 CSI driver 直接写入 S3。
3. 得益于 Instance store 的性能优势，用户在第一次加载模型以及切换模型时的时间会大大缩短。



此方案已开源，可以通过以下地址获取部署和测试代码。具体部署指引请参考第六节。

```shell
https://github.com/aws-samples/comfyui-on-eks
```



## 图片生成效果

部署完成后可以通过浏览器直接访问 CloudFront 的域名或 Kubernetes Ingress 的域名来使用 ComfyUI 的前端

![ComfyUI-Web](images/comfyui-web.png)

也可以通过将 ComfyUI 的 workflow 保存为可供 API 调用的  json 文件，以 API 的方式来调用，可以更好地与企业内的平台和系统进行结合。参考调用代码 `comfyui-on-eks/test/invoke_comfyui_api.py` 

![ComfyUI-API](images/comfyui-api.png)



## 方案部署指引

### 1. 准备工作

此方案默认你已安装部署好并熟练使用以下工具：

* [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html): latest version
* [eksctl](https://eksctl.io/installation/)
* [kubectl](https://kubernetes.io/docs/tasks/tools/)
* [Docker](https://docs.docker.com/engine/install/)
* [npm](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm/)
* [CDK](https://docs.aws.amazon.com/cdk/v2/guide/getting_started.html): latest version



确保账号下有足够的 G 实例配额。（本方案使用 g5.2x/g4dn.2x 至少需要 8vCPU）



下载部署代码，**切换分支，安装 npm packages 并检查环境**

```shell
git clone https://github.com/aws-samples/comfyui-on-eks ~/comfyui-on-eks
cd ~/comfyui-on-eks && git checkout custom_nodes_demo
npm install
npm list
cdk list
```

运行 `npm list` 确认已安装下面的 packages

```shell
comfyui-on-eks@0.3.0 ~/comfyui-on-eks
├── @aws-quickstart/eks-blueprints@1.15.1
├── aws-cdk-lib@2.147.3
├── aws-cdk@2.147.3
└── ...
```

运行 `cdk list` 确认环境已准备完成，有以下 CloudFormation 可以部署

```
Comfyui-Cluster
CloudFrontEntry
LambdaModelsSync
S3Storage
ComfyuiEcrRepo
```



### 2. 部署 EKS 集群

执行以下命令

```shell
cd ~/comfyui-on-eks && cdk deploy Comfyui-Cluster 
```

此时会在 CloudFormation 创建一个名为 `Comfyui-Cluster` 的 Stack 来部署 EKS Cluster 所需的所有资源，执行时间约 20-30min。



`Comfyui-Cluster Stack` 的资源定义可以参考 `comfyui-on-eks/lib/comfyui-on-eks-stack.ts`，需要关注以下几点：

1. EKS 集群是通过 EKS Blueprints 框架来构建，`blueprints.EksBlueprint.builder()`
2. 通过 EKS Blueprints 的 Addon 给 EKS 集群安装了以下插件：
   1. AwsLoadBalancerControllerAddOn：用于管理 Kubernetes 的 ingress ALB
   2. SSMAgentAddOn：用于在 EKS node 上使用 SSM，远程登录或执行命令
   3. Karpenter：用于对 EKS node 进行扩缩容
   4. GpuOperatorAddon：支持 GPU node 运行

3. 给 EKS 的 node 增加了 S3 的权限，以实现将 S3 上的模型文件同步到本地 instance store
4. 没有定义 GPU 实例的 nodegroup，而是只定义了轻量级应用的 cpu 实例 nodegroup 用于运行 Addon 的 pods，GPU 实例的扩缩容完全交由 Karpenter 实现

部署完成后，CDK 的 outputs 会显示一条 ConfigCommand，用来更新配置以 kubectl 来访问 EKS 集群

![eks-blueprints-cmd](images/eks-blueprints-cmd.png)

**执行上面的 ConfigCommand 命令以授权 kubectl 访问 EKS 集群**

执行以下命令验证 kubectl 已获授权访问 EKS 集群

```shell
kubectl get svc
```

至此，EKS 集群已完成部署。

同时请注意，EKS Blueprints 输出了 KarpenterInstanceNodeRole，它是 Karpenter 管理的 Node 的 role，请记下这个 role 接下来将在 5.2 节进行配置。



### 3. 部署存储模型的 S3 bucket 以及 Lambda 动态同步模型

执行以下命令

```shell
cd ~/comfyui-on-eks && cdk deploy LambdaModelsSync
```



`LambdaModelsSync ` 的 stack 主要创建以下资源：

* S3 bucket：命名规则为 `comfyui-models-{account_id}-{region}`，用来存储 ComfyUI 使用到的模型
* Lambda 以及对应的 role 和 event source：Lambda function 名为 `comfy-models-sync`，用来在模型上传到 S3 或从 S3 删除时触发 GPU 实例同步 S3 bucket 内的模型到本地



`LambdaModelsSync` 的资源定义可以参考  `comfyui-on-eks/lib/lambda-models-sync.ts`，需要关注以下几点：

1. Lambda 的代码在目录 `comfyui-on-eks/lib/ComfyModelsSyncLambda/model_sync.py`
2. lambda 的作用是通过 tag 过滤所有 ComfyUI EKS Cluster 里的 GPU 实例，当存放模型的 S3 发生 create 或 remove 事件时，通过 SSM 的方式让所有 GPU 实例同步 S3 上的模型到本地目录（instance store）



S3 for Models 和 Lambda 部署完成后，此时 S3 还是空的，执行以下命令用来初始化 S3 bucket 并下载 SDXL 模型准备测试。

注意：**以下命令会将 SDXL 模型下载到本地并上传到 S3，需要有充足的磁盘空间（20G），你也可以通过自己的方式将模型上传到 S3 对应的目录。**

```shell
region="us-west-2" # 修改 region 为你当前的 region
cd ~/comfyui-on-eks/test/ && bash init_s3_for_models.sh $region
```

无需等待模型下载上传 S3 完成，可继续以下步骤，只需要在 GPU node 拉起前确认模型上传 S3 完成即可。



### 4. 部署 S3 bucket 用以存储上传到 ComfyUI 以及 ComfyUI 生成的图片

执行以下命令

```shell
cd ~/comfyui-on-eks && cdk deploy S3Storag
```



`S3OutputsStorage` 的 stack 只创建两个 S3 bucket，命名规则为 `comfyui-outputs-{account_id}-{region}` 和 `comfyui-inputs-{account_id}-{region}`，用于存储上传到 ComfyUI 以及 ComfyUI 生成的图片。



### 5. 部署 ComfyUI Workload

ComfyUI 的 Workload 部署用 Kubernetes 来实现，请按以下顺序来依次部署。



#### 5.1 构建并上传 ComfyUI Docker 镜像

参考上文 Custom Nodes 支持



#### 5.2 部署 Karpenter 用以管理 GPU 实例的扩缩容

获取第 2 节输出的 KarpenterInstanceNodeRole，执行以下命令来部署  Karpenter

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

执行以下命令来验证 Karpenter 的部署结果

```shell
kubectl describe karpenter
```

Karpenter 的部署需要注意以下几点：

1. 使用了 g5.2xlarge 和 g4dn.2xlarge 机型，同时使用了 `on-demand` 和 `spot` 实例。
2. 在 userData 中对 karpenter 拉起的 GPU 实例做以下初始化操作：
   1. 格式化 instance store 本地盘，并 mount 到 `/comfyui-models` 目录。
   2. 将存储在 S3 上的模型文件同步到本地 instance store。

在第 2 节获取到的 KarpenterInstanceNodeRole 需要添加一条 S3 的访问权限，以允许 GPU node 从 S3 同步文件，请执行以下命令

```shell
KarpenterInstanceNodeRole="Comfyui-Cluster-ComfyuiClusterkarpenternoderoleE627-juyEInBqoNtU" # 修改为你自己的 role
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess --role-name $KarpenterInstanceNodeRole
```



#### 5.3 部署 S3 PV 和 PVC 用以存储生成的图片

执行以下命令来部署 S3 CSI 的 PV 和 PVC

**Run on Linux**

```shell
region="us-west-2" # 修改 region 为你当前的 region
account=$(aws sts get-caller-identity --query Account --output text)
sed -i "s/region .*/region $region/g" comfyui-on-eks/manifests/PersistentVolume/sd-outputs-s3.yaml
sed -i "s/bucketName: .*/bucketName: comfyui-outputs-$account-$region/g" comfyui-on-eks/manifests/PersistentVolume/sd-outputs-s3.yaml
sed -i "s/region .*/region $region/g" comfyui-on-eks/manifests/PersistentVolume/sd-inputs-s3.yaml
sed -i "s/bucketName: .*/bucketName: comfyui-inputs-$account-$region/g" comfyui-on-eks/manifests/PersistentVolume/sd-inputs-s3.yaml
kubectl apply -f comfyui-on-eks/manifests/PersistentVolume/
```

**Run on MacOS**

```shell
region="us-west-2" # 修改 region 为你当前的 region
account=$(aws sts get-caller-identity --query Account --output text)
sed -i '' "s/region .*/region $region/g" comfyui-on-eks/manifests/PersistentVolume/sd-outputs-s3.yaml
sed -i '' "s/bucketName: .*/bucketName: comfyui-outputs-$account-$region/g" comfyui-on-eks/manifests/PersistentVolume/sd-outputs-s3.yaml
sed -i '' "s/region .*/region $region/g" comfyui-on-eks/manifests/PersistentVolume/sd-inputs-s3.yaml
sed -i '' "s/bucketName: .*/bucketName: comfyui-inputs-$account-$region/g" comfyui-on-eks/manifests/PersistentVolume/sd-inputs-s3.yaml
kubectl apply -f comfyui-on-eks/manifests/PersistentVolume/
```



#### 5.4 部署 EKS S3 CSI Driver



执行以下命令，将你的 IAM principal 加到 EKS cluster 中去

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

执行以下命令，确认你的 IAM principal 已加到 EKS cluster 中

```shell
aws eks list-access-entries --cluster-name Comfyui-Cluster|grep $identity
```



执行以下命令，创建 S3 CSI driver 的 role 和 service account，以允许 S3 CSI driver 对 S3 进行读写。

```shell
region="us-west-2" # 修改 region 为你当前的 region
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



执行以下命令，安装 `aws-mountpoint-s3-csi-driver` Addon

```shell
region="us-west-2" # 修改 region 为你当前的 region
account=$(aws sts get-caller-identity --query Account --output text)
eksctl create addon --name aws-mountpoint-s3-csi-driver --version v1.0.0-eksbuild.1 --cluster Comfyui-Cluster --service-account-role-arn arn:aws:iam::$account:role/EKS-S3-CSI-DriverRole-$account-$region --force
```



#### 5.5 部署 ComfyUI Deployment 和 Service

执行以下命令来替换容器 image 镜像

**Run on Linux**

```shell
region="us-west-2" # 修改 region 为你当前的 region
account=$(aws sts get-caller-identity --query Account --output text)
sed -i "s/image: .*/image: ${account}.dkr.ecr.${region}.amazonaws.com\/comfyui-images:latest/g" comfyui-on-eks/manifests/ComfyUI/comfyui_deployment.yaml
```

**Run on MacOS**

```shell
region="us-west-2" # 修改 region 为你当前的 region
account=$(aws sts get-caller-identity --query Account --output text)
sed -i '' "s/image: .*/image: ${account}.dkr.ecr.${region}.amazonaws.com\/comfyui-images:latest/g" comfyui-on-eks/manifests/ComfyUI/comfyui_deployment.yaml
```



执行以下命令来部署 ComfyUI 的 Deployment 和 Service

```shell
kubectl apply -f comfyui-on-eks/manifests/ComfyUI
```



ComfyUI 的 deployment 和 service 部署注意以下几点：

1. ComfyUI 的 pod 扩展时间和实例类型有关，如果实例不足需要 Karpenter 拉起 node 进行初始化，同步镜像后才可以被 pod 调度。可以通过以下命令分别查看 Kubernetes 事件以及 Karpenter 日志

   ```shell
   podName=$(kubectl get pods -n karpenter|tail -1|awk '{print $1}')
   kubectl logs -f $podName -n karpenter
   ```

   ```shell
   kubectl get events --watch
   ```

   如果你看到下面的 ERROR log

   ```shell
   AuthFailure.ServiceLinkedRoleCreationNotPermitted: The provided credentials do not have permission to create the service-linked role for EC2 Spot Instances.
   ```

   执行以下命令创建一个 service linked role

   ```shell
   aws iam create-service-linked-role --aws-service-name spot.amazonaws.com
   ```

   

2. 不同的 GPU 实例有不同的 Instance Store 大小，如果 S3 存储的模型总大小超过了 Instance Store 的大小，则需要使用 EFS 的方式来管理模型存储



当 comfyui 的 pod running 时，执行以下命令查看 pod 日志

```shell
podName=$(kubectl get pods |tail -1|awk '{print $1}')
kubectl logs -f $podName
```





### 6. 测试 ComfyUI on EKS 部署结果

#### 6.1 API 测试

使用 API 的方式来测试，在 `comfyui-on-eks/test` 目录下执行以下命令

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



API 调用逻辑参考 `comfyui-on-eks/test/invoke_comfyui_api.py`，注意以下几点：

1. API 调用执行 ComfyUI 的 workflow 存储在 `comfyui-on-eks/test/sdxl_refiner_prompt_api.json`
2. 使用到了两个模型：sd_xl_base_1.0.safetensors, sd_xl_refiner_1.0.safetensors
3. 可以在 sdxl_refiner_prompt_api.json 里或 invoke_comfyui_api.py 修改 prompt 进行测试

#### 6.2 浏览器测试

执行以下命令获取 ingress 地址

```shell
kubectl get ingress
```

通过浏览器直接访问 ingress 地址。



至此 ComfyUI on EKS 部分已部署测试完成。接下来我们将对 EKS 集群接入 CloudFront 进行边缘加速。



### 7. 部署 CloudFront 边缘加速（可选）

在 `comfyui-on-eks` 目录下执行以下命令，为 Kubernetes 的 ingress 接入 CloudFront 边缘加速

```shell
cdk deploy CloudFrontEntry
```

`CloudFrontEntry` 的 stack 可以参考  `comfyui-on-eks/lib/cloudfront-entry.ts`，需要关注以下几点：

1. 在代码中根据 tag 找到了 EKS Ingress 的 ALB
2. 以 EKS Ingress ALB 作为 CloudFront Distribution 的 origin
3. ComfyUI 的 ALB 入口只配置了 HTTP，所以 CloudFront Origin Protocol Policy 设置为 HTTP_ONLY
4. 加速动态请求，cache policy 设置为 CACHING_DISABLED



部署完成后会打出 Outputs，其中包含了 CloudFront 的 URL `CloudFrontEntry.cloudFrontEntryUrl`，参考第 6 节通过 API 或浏览器的方式进行测试。



## 清理资源

执行以下命令删除所有 Kubernetes 资源

```shell
kubectl delete -f comfyui-on-eks/manifests/ComfyUI/
kubectl delete -f comfyui-on-eks/manifests/PersistentVolume/
kubectl delete -f comfyui-on-eks/manifests/Karpenter/
```

删除上述部署的资源

```shell
aws ecr batch-delete-image --repository-name comfyui-images --image-ids imageTag=latest
cdk destroy ComfyuiEcrRepo
cdk destroy CloudFrontEntry
cdk destroy S3Storage
cdk destroy LambdaModelsSync
cdk destroy Comfyui-Cluster
```



## 成本预估

假设场景：

* 部署 1 台 g5.2xlarge 来支持图像生成
* 一张 1024x1024 的图片生成平均需要 9s，平均大小为 1.5MB
* 每天使用时间为 8h，每个月使用 20 天
* 每个月可以生成 8 x 20 x 3600 / 9 = 64000 张图片
* 每个月需要存储的图片大小为 64000 x 1.5MB / 1000 = 96GB
* DTO 流量大小约 100GB（96GB + 加上 HTTP 请求）
* ComfyUI 不同版本的镜像共 20G

使用此方案部署在 us-west-2 的总价约为 **$441.878（使用 CloudFront 对外）或 $442.378（使用 ALB 对外）**

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
