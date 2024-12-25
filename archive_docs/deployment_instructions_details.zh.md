### 1. 准备工作

此方案默认你已安装部署好并熟练使用以下工具：

* [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html): latest version
* [eksctl](https://eksctl.io/installation/)
* [kubectl](https://kubernetes.io/docs/tasks/tools/)
* [Docker](https://docs.docker.com/engine/install/)
* [npm](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm/)
* [CDK](https://docs.aws.amazon.com/cdk/v2/guide/getting_started.html): 2.173.2

以上所有工具都可以通过运行下面的脚本安装（只支持 Ubuntu）

```shell
cd ~/comfyui-on-eks/auto_deploy && bash env_prepare.sh
```

**切换分支，安装 npm packages 并检查环境**

```shell
git clone https://github.com/aws-samples/comfyui-on-eks ~/comfyui-on-eks
cd ~/comfyui-on-eks && git checkout v0.4.0
npm install --force
npm list
cdk list
```

运行 `npm list` 确认已安装下面的 packages

```shell
comfyui-on-eks@0.3.0 ~/comfyui-on-eks
├── @aws-quickstart/eks-blueprints@1.16.2
├── aws-cdk-lib@2.173.2
├── aws-cdk@2.173.2
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

![eks-blueprints-cmd](../images/eks-blueprints-cmd.png)

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

执行以下命令，创建 ECR repo 来存放 ComfyUI 镜像

```shell
cd ~/comfyui-on-eks && cdk deploy ComfyuiEcrRepo
```



在准备阶段部署好 Docker 的机器上运行 `build_and_push.sh` 脚本

```shell
region="us-west-2" # 修改 region 为你当前的 region
cd ~/comfyui-on-eks/comfyui_image/ && bash build_and_push.sh $region
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
kubectl describe karpenter -n kube-system
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
   podName=$(kubectl get pods -n kube-system|grep karpenter|tail -1|awk '{print $1}')
   kubectl logs -f $podName -n kube-system
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



部署完 comfyui 的 pod 后你可能会遇到下面的报错

```
E0718 16:22:59.734961       1 driver.go:96] GRPC error: rpc error: code = Internal desc = Could not mount "comfyui-outputs-123456789012-us-west-2" at "/var/lib/kubelet/pods/5d662061-4f4b-45
4e-bac1-2a051503c3f4/volumes/kubernetes.io~csi/comfyui-outputs-pv/mount": Could not check if "/var/lib/kubelet/pods/5d662061-4f4b-454e-bac1-2a051503c3f4/volumes/kubernetes.io~csi/comfyui-ou
tputs-pv/mount" is a mount point: stat /var/lib/kubelet/pods/5d662061-4f4b-454e-bac1-2a051503c3f4/volumes/kubernetes.io~csi/comfyui-outputs-pv/mount: no such file or directory, Failed to re
ad /host/proc/mounts: open /host/proc/mounts: invalid argument
```

这可能是因为一个 Karpenter 和 mountpoint-s3-csi-driver 的 bug：[Pod "Sometimes" cannot mount PVC in CSI](https://github.com/awslabs/mountpoint-s3-csi-driver/issues/174)

目前的解决方法是把 `s3-csi-node-xxxx` 这个 pod kill 掉让它重启，即可正常挂载

```shell
kubectl delete pod s3-csi-node-xxxx -n kube-system # Modify the pod name to your own
```



### 6. 测试 ComfyUI on EKS 部署结果

#### 6.1 API 测试

使用 API 的方式来测试，在 `comfyui-on-eks/test` 目录下执行以下命令

**Run on Linux**

```shell
ingress_address=$(kubectl get ingress|grep comfyui-ingress|awk '{print $4}')
sed -i "s/SERVER_ADDRESS = .*/SERVER_ADDRESS = \"${ingress_address}\"/g" invoke_comfyui_api.py
sed -i "s/SHOW_IMAGES = .*/SHOW_IMAGES = False/g" invoke_comfyui_api.py
./invoke_comfyui_api.py test_workflows/sdxl_refiner_prompt_api.json
```

**Run on MacOS**

```shell
ingress_address=$(kubectl get ingress|grep comfyui-ingress|awk '{print $4}')
sed -i '' "s/SERVER_ADDRESS = .*/SERVER_ADDRESS = \"${ingress_address}\"/g" invoke_comfyui_api.py
sed -i '' "s/SHOW_IMAGES = .*/SHOW_IMAGES = False/g" invoke_comfyui_api.py
./invoke_comfyui_api.py test_workflows/sdxl_refiner_prompt_api.json
```



API 调用逻辑参考 `comfyui-on-eks/test/invoke_comfyui_api.py`，注意以下几点：

1. API 调用执行 ComfyUI 的 workflow 存储在 `comfyui-on-eks/test/test_workflows/sdxl_refiner_prompt_api.json`
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
aws ecr delete-repository --repository-name comfyui-images --force
cdk destroy ComfyuiEcrRepo
cdk destroy CloudFrontEntry
cdk destroy S3Storage
cdk destroy LambdaModelsSync
cdk destroy Comfyui-Cluster
```

