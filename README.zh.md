[English](./README.md)

## 这是个什么

这是一个在 Amazon EKS 上部署 ComfyUI 的方案。

## 方案特性

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

## 图片生成 Demo

部署完成后可以通过浏览器直接访问 CloudFront 的域名或 Kubernetes Ingress 的域名来使用 ComfyUI 的前端

![ComfyUI-Web](images/comfyui-web.png)

也可以通过将 ComfyUI 的 workflow 保存为可供 API 调用的  json 文件，以 API 的方式来调用，可以更好地与企业内的平台和系统进行结合。参考调用代码 `comfyui-on-eks/test/invoke_comfyui_api.py` 

![ComfyUI-API](images/comfyui-api.png)

## 部署指引

可以参考[详细部署指引](./archive_docs/deployment_instructions_details.zh.md)一步步执行，也可以运行下面的自动化脚本进行部署（目前只支持 Ubuntu，且需要至少 50GB 的磁盘空间）

### 1. 准备工作

确保账号下有足够的 G 实例配额。（本方案使用 g6.2x/g5.2x/g4dn.2x 至少需要 8vCPU 或 g6e.x 则至少需要 4vCPU）

```shell
rm -rf ~/comfyui-on-eks && git clone https://github.com/aws-samples/comfyui-on-eks ~/comfyui-on-eks
cd ~/comfyui-on-eks && git checkout v0.6.0
region="us-west-2" # Modify the region to your current region
project="" # [Optional] Default is empty, you can modify the project name to your own
if [[ x$project == 'x' ]]
then
	project_dir="$HOME/comfyui-on-eks"
else
	mv $HOME/comfyui-on-eks $HOME/comfyui-on-eks-$project
	project_dir="$HOME/comfyui-on-eks-$project"
fi
sed -i "s/export AWS_DEFAULT_REGION=.*/export AWS_DEFAULT_REGION=$region/g" $project_dir/auto_deploy/env.sh
sed -i "s/export PROJECT_NAME=.*/export PROJECT_NAME=$project/g" $project_dir/auto_deploy/env.sh
cd $project_dir
```

安装所需的工具以及 NPM 库

```shell
cd $project_dir/auto_deploy/ && bash env_prepare.sh
```

### 2. 部署

执行以下脚本部署所有资源

```shell
source ~/.bashrc && cd $project_dir/auto_deploy/ && bash deploy_infra.sh
```

### 3. 删除所有资源

执行以下脚本删除所有资源

```
cd $project_dir/auto_deploy/ && bash destroy_infra.sh
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

## 变更日志

### 自动化部署 -- 2024.12.26

可以在目录 `comfyui-on-eks/auto_deploy/` 下使用自动化脚本来部署，目前只支持 Ubuntu。

### Flux 支持

ComfyUI 已经支持了 Flux，要在当前的方案中使用 Flux，只需要：

1. 用最新版本的 ComfyUI build docker 镜像，已在 [Dockerfile](https://github.com/aws-samples/comfyui-on-eks/blob/main/comfyui_image/Dockerfile) 中完成
2. 将 Flux 的模型放到对应的 S3 目录，参考  [ComfyUI Flux Examples](https://comfyanonymous.github.io/ComfyUI_examples/flux/)

用 comfyui sd3 的 workflow 来调用模型推理，参考 `comfyui-on-eks/test/` 目录

### Custom Nodes 支持

切换到 [custom_nodes_demo](https://github.com/aws-samples/comfyui-on-eks/tree/custom_nodes_demo) 分支了解具体细节。

### Stable Diffusion 3 支持

ComfyUI 已经支持了 Stable Diffusion 3，要在当前的方案中使用 Stable Diffusion 3，只需要：

1. 用最新版本的 ComfyUI build docker 镜像
2. 将 SD3 的模型放到对应的 S3 目录，参考  [ComfyUI SD3 Examples](https://comfyanonymous.github.io/ComfyUI_examples/sd3/)

用 comfyui sd3 的 workflow 来调用模型推理，参考 `comfyui-on-eks/test/` 目录

![sd3](images/sd3.png)

