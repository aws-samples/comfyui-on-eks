## 云端AI生图——面向美术工作室的Stable Diffusion生图方案

### 一、背景介绍

Stable Diffusion 作为当下最流行的开源 AI 图像生成模型在游戏行业有着广泛的应用实践，无论是 ToC 面向玩家的游戏社区场景，还是 ToB 面向游戏工作室的美术制作场景，都可以发挥很大的价值。而如何更好地使用 Stable Diffusion 也成了非常热门的话题，社区也贡献了多种 runtime 来实现 Stable Diffusion 的图像生成，其中广泛流行的包括：[stable-diffusion-webui](https://github.com/AUTOMATIC1111/stable-diffusion-webui), [ComfyUI](https://github.com/comfyanonymous/ComfyUI),  [Fooocus](https://github.com/lllyasviel/Fooocus) 等。同时，如何在企业内部部署运维和迭代 Stable Diffusion 图像生成平台也涌现了多种方案。本文将以 ComfyUI 为例，介绍如何在 AWS 上部署面向美术团队的 Stable Diffusion 图像生成平台。



### 二、ComfyUI 简介

ComfyUI 是一个基于节点式工作流的 Stable Diffusion 方案，它将 Stable Diffsuion 模型推理时各个流程拆分成不同的节点，让用户可以更加清晰地了解 Stable Diffusion 的原理，并且可以更加精细化地控制整个流程。同时得益于 ComfyUI 在 SDXL 模型上相较于其他方案的性能优化，使得它越来越多地被美术创作者所使用。



### 三、方案特点

我们根据实际的使用场景设计方案，总结有以下特点：

* IaC 方式部署，极简运维，使用 [AWS Cloud Development Kit (AWS CDK)](https://aws.amazon.com/cdk/) 和 [Amazon EKS Bluprints](https://aws-quickstart.github.io/cdk-eks-blueprints/) 来管理 [Amazon Elastic Kubernetes Service (Amazon EKS)](https://aws.amazon.com/eks/) 集群以承载运行 ComfyUI。
* 基于 [Karpenter](https://karpenter.sh/) 的能力动态伸缩，自定义节点伸缩策略以适应业务需求。
* 通过 [Amazon Spot instances](https://aws.amazon.com/ec2/spot/) 实例节省 GPU 实例成本。
* 充分利用 GPU 实例的 [instance store](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/InstanceStorage.html)，最大化模型加载和切换的性能，同时最小化模型存储和传输的成本。
* 利用 [S3 CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/s3-csi.html) 将生成的图片直接写入 [Amazon S3](https://aws.amazon.com/s3/)，降低存储成本。
* 利用 [Amazon CloudFront](https://aws.amazon.com/cloudfront/) 边缘节点加速动态请求，以满足跨地区美术工作室共用平台的场景。(Optional)
* 通过 Serverless 事件触发的方式，当模型上传 S3 或在 S3 删除时，触发工作节点同步模型目录数据。



### 四、方案架构

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



### 五、图片生成效果

部署完成后可以通过浏览器直接访问 CloudFront 的域名或 Kubernetes Ingress 的域名来使用 ComfyUI 的前端

![ComfyUI-Web](images/comfyui-web.png)

也可以通过将 ComfyUI 的 workflow 保存为可供 API 调用的  json 文件，以 API 的方式来调用，可以更好地与企业内的平台和系统进行结合。参考调用代码 `comfyui-on-eks/test/invoke_comfyui_api.py` 

![ComfyUI-API](images/comfyui-api.png)



### 六、方案部署指引

#### 6.1 准备工作

此方案默认你已安装部署好并熟练使用以下工具：

* [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html): latest version
* [eksctl](https://eksctl.io/installation/)
* [helm](https://helm.sh/docs/intro/install/)
* [kubectl](https://kubernetes.io/docs/tasks/tools/)
* [Docker](https://docs.docker.com/engine/install/)
* [npm](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm/)
* [CDK](https://docs.aws.amazon.com/cdk/v2/guide/getting_started.html): latest version



下载部署代码，**切换分支，安装 npm packages 并检查环境**

```shell
git clone https://github.com/aws-samples/comfyui-on-eks ~/comfyui-on-eks
cd ~/comfyui-on-eks && git checkout Blog1
npm install
npm list
cdk list
```

运行 `npm list` 确认已安装下面的 packages

```shell
comfyui-on-eks@0.1.0 ~/comfyui-on-eks
├── @aws-quickstart/eks-blueprints@1.13.1
├── aws-cdk-lib@2.115.0
├── aws-cdk@2.99.1
└── ...
```

运行 `cdk list` 确认环境已准备完成，有以下 CloudFormation 可以部署

```
Comfyui-Cluster
CloudFrontEntry
LambdaModelsSync
S3OutputsStorage
ComfyuiEcrRepo
```



#### 6.2 部署 EKS 集群

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

同时请注意，EKS Blueprints 输出了 KarpenterInstanceNodeRole，它是 Karpenter 管理的 Node 的 role，请记下这个 role 接下来将在 6.5.2 节进行配置。



#### 6.3 部署存储模型的 S3 bucket 以及 Lambda 动态同步模型

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



#### 6.4 部署存储 ComfyUI 生成图片的 S3 bucket

执行以下命令

```shell
cd ~/comfyui-on-eks && cdk deploy S3OutputsStorage
```



`S3OutputsStorage` 的 stack 只创建一个 S3 bucket，命名规则为 `comfyui-outputs-{account_id}-{region}`，用于存储 ComfyUI 生成的图片



#### 6.5 部署 ComfyUI Workload

ComfyUI 的 Workload 部署用 Kubernetes 来实现，请按以下顺序来依次部署。



##### 6.5.1 构建并上传 ComfyUI Docker 镜像

执行以下命令，创建 ECR repo 来存放 ComfyUI 镜像

```shell
cd ~/comfyui-on-eks && cdk deploy ComfyuiEcrRepo
```



在准备阶段部署好 Docker 的机器上运行 `build_and_push.sh` 脚本

```shell
region="us-west-2" # 修改 region 为你当前的 region
cd comfyui-on-eks/comfyui_image/ && bash build_and_push.sh $region
```



ComfyUI 的 Docker 镜像请参考 `comfyui-on-eks/comfyui_image/Dockerfile`，需要注意以下几点：

1. 在 Dockerfile 中通过 git clone & git checkout 的方式来固定 ComfyUI 的版本，可以根据业务需求修改为不同的 ComfyUI 版本。
2. Dockerfile 中没有安装 customer node 等插件，可以使用 RUN 来按需添加。
3. 此方案每次的 ComfyUI 版本迭代都只需要通过重新 build 镜像，更换镜像来实现。

构建完镜像后，执行以下命令确保镜像的 Architecture 是 X86 架构，因为此方案使用的 GPU 实例均是基于 X86 的机型。

```shell
region="us-west-2" # 修改 region 为你当前的 region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
image_name=${ACCOUNT_ID}.dkr.ecr.${region}.amazonaws.com/comfyui-images:latest
docker image inspect $image_name|grep Architecture
```



##### 6.5.2 部署 Karpenter 用以管理 GPU 实例的扩缩容

执行以下命令来部署  Karpenter 的 Provisioner

```shell
kubectl apply -f comfyui-on-eks/manifests/Karpenter/karpenter_provisioner.yaml
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

在 6.2 节获取到的 KarpenterInstanceNodeRole 需要添加一条 S3 的访问权限，以允许 GPU node 从 S3 同步文件，请执行以下命令

```shell
KarpenterInstanceNodeRole="Comfyui-Cluster-ComfyuiClusterkarpenternoderoleE627-juyEInBqoNtU" # 修改为你自己的 role
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess --role-name $KarpenterInstanceNodeRole
```



##### 6.5.3 部署 S3 PV 和 PVC 用以存储生成的图片

执行以下命令来部署 S3 CSI 的 PV 和 PVC

**Run on Linux**

```shell
region="us-west-2" # 修改 region 为你当前的 region
account=$(aws sts get-caller-identity --query Account --output text)
sed -i "s/region .*/region $region/g" comfyui-on-eks/manifests/PersistentVolume/sd-outputs-s3.yaml
sed -i "s/bucketName: .*/bucketName: comfyui-outputs-$account-$region/g" comfyui-on-eks/manifests/PersistentVolume/sd-outputs-s3.yaml
kubectl apply -f comfyui-on-eks/manifests/PersistentVolume/sd-outputs-s3.yaml
```

**Run on MacOS**

```shell
region="us-west-2" # 修改 region 为你当前的 region
account=$(aws sts get-caller-identity --query Account --output text)
sed -i '' "s/region .*/region $region/g" comfyui-on-eks/manifests/PersistentVolume/sd-outputs-s3.yaml
sed -i '' "s/bucketName: .*/bucketName: comfyui-outputs-$account-$region/g" comfyui-on-eks/manifests/PersistentVolume/sd-outputs-s3.yaml
kubectl apply -f comfyui-on-eks/manifests/PersistentVolume/sd-outputs-s3.yaml
```



##### 6.5.4 部署 EKS S3 CSI Driver

执行以下命令，创建 S3 CSI driver 的 role 和 service account，以允许 S3 CSI driver 对 S3 进行读写。

```shell
REGION="us-west-2" # 修改 region 为你当前的 region
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
    --region $REGION
```

确保执行上述命令的 Identity 在 EKS 集群的 `aws-auth` configmap 里

```shell
identity=$(aws sts get-caller-identity --query 'Arn' --output text)
kubectl describe configmap aws-auth -n kube-system|grep $identity
```



执行以下命令，安装 `aws-mountpoint-s3-csi-driver` Addon

```shell
helm repo add aws-mountpoint-s3-csi-driver https://awslabs.github.io/mountpoint-s3-csi-driver
helm repo update
helm upgrade --install aws-mountpoint-s3-csi-driver \
    --namespace kube-system \
    aws-mountpoint-s3-csi-driver/aws-mountpoint-s3-csi-driver
```



##### 6.5.5 部署 ComfyUI Deployment 和 Service

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
   kubect get events --watch
   ```

2. 不同的 GPU 实例有不同的 Instance Store 大小，如果 S3 存储的模型总大小超过了 Instance Store 的大小，则需要使用 EFS 的方式来管理模型存储



当 comfyui 的 pod running 时，执行以下命令查看 pod 日志

```shell
podName=$(kubectl get pods |tail -1|awk '{print $1}')
kubectl logs -f $podName
```





#### 6.6 测试 ComfyUI on EKS 部署结果

##### 6.6.1 API 测试

使用 API 的方式来测试，在 `comfyui-on-eks/test` 目录下执行以下命令

**Run on Linux**

```shell
ingress_address=$(kubectl get ingress|grep comfyui-ingress|awk '{print $4}')
sed -i "s/SERVER_ADDRESS = .*/SERVER_ADDRESS = \"${ingress_address}\"/g" invoke_comfyui_api.py
sed -i "s/HTTPS = .*/HTTPS = False/g" invoke_comfyui_api.py
sed -i "s/SHOW_IMAGES = .*/SHOW_IMAGES = False/g" invoke_comfyui_api.py
./invoke_comfyui_api.py
```

**Run on MacOS**

```shell
ingress_address=$(kubectl get ingress|grep comfyui-ingress|awk '{print $4}')
sed -i '' "s/SERVER_ADDRESS = .*/SERVER_ADDRESS = \"${ingress_address}\"/g" invoke_comfyui_api.py
sed -i '' "s/HTTPS = .*/HTTPS = False/g" invoke_comfyui_api.py
sed -i '' "s/SHOW_IMAGES = .*/SHOW_IMAGES = False/g" invoke_comfyui_api.py
./invoke_comfyui_api.py
```



API 调用逻辑参考 `comfyui-on-eks/test/invoke_comfyui_api.py`，注意以下几点：

1. API 调用执行 ComfyUI 的 workflow 存储在 `comfyui-on-eks/test/sdxl_refiner_prompt_api.json`
2. 使用到了两个模型：sd_xl_base_1.0.safetensors, sd_xl_refiner_1.0.safetensors
3. 可以在 sdxl_refiner_prompt_api.json 里或 invoke_comfyui_api.py 修改 prompt 进行测试

##### 6.6.2 浏览器测试

执行以下命令获取 ingress 地址

```shell
kubectl get ingress
```

通过浏览器直接访问 ingress 地址。



至此 ComfyUI on EKS 部分已部署测试完成。接下来我们将对 EKS 集群接入 CloudFront 进行边缘加速。



#### 6.6 部署 CloudFront 边缘加速（可选）

在 `comfyui-on-eks` 目录下执行以下命令，为 Kubernetes 的 ingress 接入 CloudFront 边缘加速

```shell
cdk deploy CloudFrontEntry
```

`CloudFrontEntry` 的 stack 可以参考  `comfyui-on-eks/lib/cloudfront-entry.ts`，需要关注以下几点：

1. 在代码中根据 tag 找到了 EKS Ingress 的 ALB
2. 以 EKS Ingress ALB 作为 CloudFront Distribution 的 origin
3. ComfyUI 的 ALB 入口只配置了 HTTP，所以 CloudFront Origin Protocol Policy 设置为 HTTP_ONLY
4. 加速动态请求，cache policy 设置为 CACHING_DISABLED



部署完成后会打出 Outputs，其中包含了 CloudFront 的 URL `CloudFrontEntry.cloudFrontEntryUrl`，参考 6.6 节通过 API 或浏览器的方式进行测试。



### 七、清理资源

执行以下命令删除所有 Kubernetes 资源

```shell
kubectl delete -f comfyui-on-eks/manifests/ComfyUI/
kubectl delete -f comfyui-on-eks/manifests/PersistentVolume/
kubectl delete -f comfyui-on-eks/manifests/Karpenter/
```

删除上述部署的资源

```shell
cdk destroy ComfyuiEcrRepo
cdk destroy CloudFrontEntry
cdk destroy S3OutputsStorage
cdk destroy LambdaModelsSync
cdk destroy Comfyui-Cluster
```



### 八、总结

本文介绍了一种在 EKS 上部署 ComfyUI 的方案，通过 Instance store 和 S3 的结合，在降低存储成本的同时最大化模型加载和切换的性能，同时通过 Serverless 的方式自动化进行模型的同步，使用 spot 实例降低 GPU 实例成本，并且通过 CloudFront 进行全球加速，以满足跨地区美术工作室协作的场景。整套方案以 IaC 的方式管理底层基础设施，最小化运维成本。
