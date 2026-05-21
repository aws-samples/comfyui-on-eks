[English](./README.md)

## 这是什么

在 Amazon EKS 上部署 [ComfyUI](https://github.com/comfyanonymous/ComfyUI) 的方案，支持 GPU 加速、自动伸缩和通过 CloudFront 安全访问。

## 方案特性

1. **IaC 方式部署**：使用 [AWS CDK](https://aws.amazon.com/cdk/) 和 [Amazon EKS Blueprints](https://aws-quickstart.github.io/cdk-eks-blueprints/) 管理 [Amazon EKS](https://aws.amazon.com/eks/) 集群。
2. **基于 Karpenter 动态伸缩**：[Karpenter](https://karpenter.sh/) v1.3 按需拉起 GPU 节点，空闲时缩容至零。
3. **Spot 实例节省成本**：使用 [Amazon Spot instances](https://aws.amazon.com/ec2/spot/) 降低 GPU 实例成本（g6.2xlarge / g5.2xlarge）。
4. **GPU Instance Store 优化**：模型同步到本地 [Instance Store](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/InstanceStorage.html) NVMe，加载和切换极快。
5. **S3 CSI 驱动直写**：生成的图片通过 [Mountpoint for S3 CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/s3-csi.html) v2.5 直接写入 [Amazon S3](https://aws.amazon.com/s3/)。
6. **CloudFront VPC Origins 安全访问**：[Amazon CloudFront](https://aws.amazon.com/cloudfront/) 通过 [VPC Origins](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html) 连接内部 ALB — ALB 永远不暴露到公网。
7. **Serverless 事件触发模型同步**：S3 事件触发 Lambda 通过 SSM 同步模型文件到所有 GPU 节点。
8. **CodeBuild 构建与模型下载**：容器镜像和模型下载均在 [AWS CodeBuild](https://aws.amazon.com/codebuild/) 上运行 — 无需本地 Docker、GPU、磁盘空间或带宽。模型从 HuggingFace 直接下载到 S3，速度超过 200 MiB/s。
9. **Amazon Bedrock 集成**：内置 [Amazon Bedrock](https://aws.amazon.com/bedrock/) 自定义节点 — 文生图（Nova Canvas）、文生视频（Nova Reel）、图像放大/修复（Stability AI）、提示词增强（Claude、Nova、Qwen3）和图像理解（视觉模型）。

## 安全注意事项

1. **网络访问控制**：
   - ALB 配置为 **仅内部访问**，不可从公网到达
   - CloudFront 通过 VPC Origins 访问 ALB（私有连接）
   - 所有资源部署在私有子网，通过 NAT Gateway 出站

2. **访问安全建议**：
   - 在 CloudFront 前实现认证（如 AWS WAF、Cognito、Lambda@Edge）
   - 生产环境中使用签名 URL 或 Cookie 限制 CloudFront 访问
   - 所有 IAM 角色遵循最小权限原则（使用 inline 策略，无 AdministratorAccess）

3. **资源标签**：
   - 所有 AWS 资源通过 CDK 全局标签打上 `Project: comfyui-on-eks`
   - Kubernetes 资源使用标签 `project: comfyui-on-eks`

## 方案架构

![Architecture](images/arch.png)

**方案部署过程**

1. ComfyUI 的模型存放在 S3 for models，目录结构和原生的 `ComfyUI/models` 目录结构一致。
2. EKS 集群的 GPU node 在拉起初始化时，会格式化本地的 Instance store，并通过 user-data 从 S3 将模型同步到本地 Instance store。
3. EKS 运行 ComfyUI 的 pod 会将 node 上的 Instance store 目录映射到 pod 里的 models 目录，以实现模型的读取加载。
4. 当有模型上传到 S3 或从 S3 删除时，会触发 Lambda 对所有 GPU node 通过 SSM 执行命令再次同步 S3 上的模型到本地 Instance store。
5. EKS 运行 ComfyUI 的 pod 会通过 PVC 的方式将 `ComfyUI/output` 目录映射到 S3 for outputs。

**用户使用过程**

1. 当用户请求通过 CloudFront --> ALB 到达 EKS pod 时，pod 会首先从 Instance store 加载模型。
2. pod 推理完成后会将图片存放在 `ComfyUI/output` 目录，通过 S3 CSI driver 直接写入 S3。
3. 得益于 Instance store 的性能优势，用户在第一次加载模型以及切换模型时的时间会大大缩短。

## 图片生成 Demo

部署完成后可以通过浏览器直接访问 CloudFront 的域名来使用 ComfyUI 的前端。

![ComfyUI-Web](images/comfyui-web.png)

也可以通过将 ComfyUI 的 workflow 保存为可供 API 调用的 json 文件，以 API 的方式来调用。参考调用代码 `test/invoke_comfyui_api.py`。

![ComfyUI-API](images/comfyui-api.png)

## Amazon Bedrock 集成

本方案内置了连接 [Amazon Bedrock](https://aws.amazon.com/bedrock/) 基础模型的 ComfyUI 自定义节点，支持云端图像生成、视频生成、编辑、放大和基于 LLM 的提示词增强 — 无需管理模型基础设施。

节点通过 GPU 节点的实例配置文件与 Bedrock 通信。部署脚本会自动附加 IAM 策略，授予 `bedrock:InvokeModel` 和 `bedrock:InvokeModelWithResponseStream` 权限（范围限定为下列模型系列）。ComfyUI 内部无需 API 密钥或手动配置。

### 可用节点

| 节点 | 分类 | 描述 | 用途 |
|------|------|------|------|
| **Bedrock Text (Converse)** | Bedrock | 通过 Converse API 进行文本生成 | 提示词增强、创意写作 |
| **Bedrock Vision (Converse)** | Bedrock | 通过 Converse API 进行图文理解 | 图片描述、场景分析 |
| **Bedrock Nova Canvas** | Bedrock/Nova Canvas | 图像生成与编辑 | 文生图、修复、外扩、去背景、图像变体 |
| **Bedrock Nova Reel (Video)** | Bedrock/Nova Reel | 文本/图像生成视频 | 带摄像机运动控制的短视频片段 |
| **Bedrock Stability Inpaint** | Bedrock/Stability | 基于遮罩的修复 | 填充遮罩区域 |
| **Bedrock Stability Remove Background** | Bedrock/Stability | 背景去除 | 提取图像主体 |
| **Bedrock Stability Upscale** | Bedrock/Stability | 图像放大（快速/保守/创意） | 提升分辨率 |
| **Bedrock Stability Control** | Bedrock/Stability | 结构/草图引导生成 | 类 ControlNet 深度/边缘引导 |
| **Bedrock Stability Search & Replace** | Bedrock/Stability | 文本引导对象替换 | 按描述替换对象 |
| **Bedrock Stability Style Transfer** | Bedrock/Stability | 应用参考图像风格 | 风格迁移 |

### 支持的模型

**文本/视觉（Converse API）**

| 模型 ID | 提供商 | 类型 |
|---------|--------|------|
| `us.amazon.nova-lite-v1:0` | Amazon | 文本 + 视觉 |
| `us.amazon.nova-pro-v1:0` | Amazon | 文本 + 视觉 |
| `anthropic.claude-sonnet-4-6-20250514-v1:0` | Anthropic | 文本 + 视觉 |
| `anthropic.claude-haiku-4-5-20251001-v1:0` | Anthropic | 文本 + 视觉 |
| `qwen.qwen3-235b-a22b-2507-v1:0` | Qwen | 文本 |
| `qwen.qwen3-32b-v1:0` | Qwen | 文本 |
| `qwen.qwen3-vl-235b-a22b` | Qwen | 视觉 |

**图像生成/编辑（InvokeModel API）**

| 模型 ID | 提供商 | 能力 |
|---------|--------|------|
| `amazon.nova-canvas-v1:0` | Amazon | 文生图、修复、外扩、去背景、图像变体 |
| `stability.stable-image-inpaint-v1:0` | Stability AI | 修复 |
| `stability.stable-image-remove-background-v1:0` | Stability AI | 背景去除 |
| `stability.stable-image-fast-upscale-v1:0` | Stability AI | 快速放大 |
| `stability.stable-image-conservative-upscale-v1:0` | Stability AI | 保守放大 |
| `stability.stable-image-creative-upscale-v1:0` | Stability AI | 创意放大 |
| `stability.stable-image-control-structure-v1:0` | Stability AI | 深度/边缘引导生成 |
| `stability.stable-image-control-sketch-v1:0` | Stability AI | 草图引导生成 |
| `stability.stable-image-search-and-replace-v1:0` | Stability AI | 对象替换 |
| `stability.stable-image-style-transfer-v1:0` | Stability AI | 风格迁移 |

**视频生成（StartAsyncInvoke API）**

| 模型 ID | 提供商 | 能力 |
|---------|--------|------|
| `amazon.nova-reel-v1:0` | Amazon | 文生视频、图生视频（6秒片段，1280x720，24fps） |

### Bedrock 访问机制

1. EKS GPU 节点使用 Karpenter 管理的实例角色
2. 部署时，`deploy_infra.sh` 为该角色附加内联 IAM 策略（`BedrockInvokeAccess`）：
   ```json
   {
     "Effect": "Allow",
     "Action": ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream", "bedrock:StartAsyncInvoke", "bedrock:GetAsyncInvoke"],
     "Resource": [
       "arn:aws:bedrock:*::foundation-model/qwen.*",
       "arn:aws:bedrock:*::foundation-model/amazon.nova-*",
       "arn:aws:bedrock:*::foundation-model/stability.*",
       "arn:aws:bedrock:*::foundation-model/anthropic.claude-*"
     ]
   }
   ```
3. ComfyUI pod 通过节点的实例配置文件继承此权限 — 无需凭证或环境变量
4. 自定义节点在 pod 内使用 `boto3` 直接调用 Bedrock API

### 前置条件

1. 在 [Bedrock 控制台](https://console.aws.amazon.com/bedrock/home#/modelaccess) 启用所需的模型访问权限（Nova、Stability AI、Claude 和/或 Qwen）
2. 对于 Nova Reel：提供一个 S3 存储桶用于视频输出（节点将异步结果写入 S3）
3. 部署脚本会自动处理所有 IAM 配置

### 示例工作流

**提示词增强** — 使用 Bedrock Text 节点配合 Claude 或 Nova Lite：
1. 连接一个简单的文本提示（如 "花园里的猫"）
2. 设置系统提示为 "用丰富的视觉细节增强这个 Stable Diffusion 提示词"
3. 将输出文本连接到 KSampler 节点的正向提示

**云端图像生成** — 使用 Nova Canvas 节点：
1. 输入描述所需图像的文本提示
2. 设置宽高和 cfg_scale
3. 将输出 IMAGE 连接到预览或保存节点

**图像放大** — 使用 Stability Upscale 节点：
1. 连接工作流中的任何 IMAGE 输出
2. 选择放大模式（快速、保守或创意）
3. 将放大后的 IMAGE 连接到保存节点

**视频生成** — 使用 Nova Reel 节点：
1. 输入描述视频场景的文本提示
2. 可选连接一个 IMAGE 作为第一帧
3. 提供 S3 存储桶/前缀用于输出视频
4. 节点返回生成的 .mp4 文件的 S3 URI（6秒，1280x720，24fps）

## 部署指引

### 前置条件

- AWS 账号，具有足够的 G 实例 vCPU 配额（g6.2xlarge/g5.2xlarge 至少需要 8 vCPU）
- Ubuntu 实例 50GB+ 磁盘空间（自动化部署），或 macOS（本地 CDK 操作）
- 已配置好权限的 AWS CLI

### 1. 克隆并准备

```shell
git clone https://github.com/aws-samples/comfyui-on-eks ~/comfyui-on-eks
cd ~/comfyui-on-eks
```

如需部署到其他区域，编辑 `auto_deploy/env.sh`：
```shell
export AWS_DEFAULT_REGION="us-west-2"  # 修改为目标区域
```

如需使用非默认 AWS 配置文件：
```shell
export AWS_PROFILE=your-profile-name
```

### 2. 安装依赖

```shell
cd ~/comfyui-on-eks/auto_deploy/ && bash env_prepare.sh
```

此脚本安装 AWS CLI、eksctl、kubectl、Node.js、CDK CLI 和 npm 包。

### 3. 部署

```shell
source ~/.bashrc && cd ~/comfyui-on-eks/auto_deploy/ && bash deploy_infra.sh
```

按顺序部署：

1. EKS 集群
2. Lambda（模型同步）
3. S3 存储桶
4. ECR + CodeBuild 项目
5. **Tier 1 模型下载**（阻塞直到核心模型到达 S3）
6. **全量模型下载**（通过 CodeBuild 后台运行）
7. 容器镜像构建（CodeBuild）
8. Karpenter 节点池
9. S3 PV/PVC
10. S3 CSI 驱动
11. ComfyUI 部署
12. CloudFront 分发

### 4. 访问

部署完成后，通过 `ComfyUI-on-EKS-CloudFront` 堆栈输出的 CloudFront URL 访问 ComfyUI。

### 5. 删除所有资源

```shell
cd ~/comfyui-on-eks/auto_deploy/ && bash destroy_infra.sh
```

## 模型管理

### 模型如何加载

模型通过专用的 [AWS CodeBuild](https://aws.amazon.com/codebuild/) 项目（`comfyui-model-download`）从 HuggingFace 下载并存储到 S3。相比本地下载，这种方式有以下优势：

- **快速**：CodeBuild 在 AWS 内部运行，直连 HuggingFace 和 S3（200+ MiB/s）
- **无需本地资源**：不需要本地磁盘空间或带宽
- **可靠**：内置重试机制，最长 4 小时超时，以及跳过已存在文件的逻辑
- **分层下载**：核心模型（Tier 1）优先下载以解除部署阻塞；其余模型后台下载

### 部署流程

```
deploy_infra.sh
    |
    |--> cdk_deploy_ecr()           # 创建 CodeBuild 项目
    |--> upload_models_to_s3_tier1() # 触发 CodeBuild (tier1) - 阻塞
    |       下载: z_image_turbo, qwen_3_4b, ae.safetensors, RealESRGAN
    |       (~15 GB, 约 2 分钟)
    |
    |--> upload_models_to_s3_all()   # 触发 CodeBuild (all) - 后台
    |       下载: SD 1.5/XL, Flux, Qwen Image, Wan 2.2, ACE Step 等
    |       (~130 GB, 约 30 分钟)
    |
    |--> deploy_comfyui()            # Pod 启动时 Tier 1 模型已就绪
```

### 包含的模型（~38 个文件，~130 GB）

| 分类 | 模型 | 用途 |
|------|------|------|
| **diffusion_models/** | z_image_turbo, flux1-dev-fp8, qwen_image, qwen_image_edit, wan2.2 (i2v high/low noise), acestep_v1.5_turbo, lotus-depth | 模板 01-05, Flux, Qwen, Wan |
| **text_encoders/** | qwen_3_4b, clip_l, t5xxl_fp16, qwen_2.5_vl_7b, umt5_xxl, qwen_0.6b/4b_ace15 | 所有工作流 |
| **checkpoints/** | SD 1.5, SDXL base/refiner, DreamShaper 8, SD2 inpainting, SD2.1, SVD, hunyuan_3d_v2.1 | 归档 + 3D 工作流 |
| **vae/** | ae, vae-ft-mse, qwen_image_vae, wan_2.1_vae, ace_1.5_vae | 所有工作流 |
| **controlnet/** | scribble, openpose, depth (SD1.5 fp16) | 归档 ControlNet 工作流 |
| **upscale_models/** | RealESRGAN_x4plus | 图像放大工作流 |
| **loras/** | Qwen Lightning, Wan 2.2 lightx2v, Qwen Edit Lightning | 加速 Qwen/Wan 工作流 |
| **model_patches/** | Z-Image-Turbo-Fun-Controlnet-Union | z_image_turbo 的 ControlNet |

### 添加自定义模型

部署完成后添加自定义模型：

```shell
# 直接上传到 S3（遵循 ComfyUI/models 目录结构）
aws s3 cp my-model.safetensors s3://comfyui-models-<ACCOUNT>-<REGION>/checkpoints/

# Lambda 触发器会自动通过 SSM 同步到 GPU 节点
# 或通过 CodeBuild 触发手动下载：
cd test/ && bash download_models_codebuild.sh <region> <profile> all
```

### 重新运行模型下载

如需重新下载模型（例如在 `buildspec_models.yml` 中添加新条目后）：

```shell
cd ~/comfyui-on-eks/test
bash download_models_codebuild.sh us-west-2 default all
```

CodeBuild 任务会跳过 S3 中已存在的模型，因此重复运行是安全的，只会下载缺失的文件。

### 按需模型下载（Auto Model Downloader）

除了预加载的模型外，本方案还包含一个**自动下载扩展**，当工作流需要某个模型时会透明地获取它。这意味着完整的 ~90 个模型目录可按需使用，无需全部预加载。

**工作原理：**

1. 用户加载任意工作流模板并点击 "Queue Prompt"
2. 扩展拦截提示，扫描模型文件引用
3. 如有模型缺失，UI 中显示下载进度通知
4. 模型从 S3（或 HuggingFace 作为回退）下载到本地实例存储
5. 依赖项（文本编码器、VAE）自动协同下载
6. 所有模型就绪后，工作流自动执行

**用户体验：** 无需学习新节点，无需手动干预。引用了尚未下载的模型的工作流只是首次运行时间较长，之后即可即时运行。

**支持的模型目录**（~90 个模型，20+ 能力组）：

| 组 | 能力 | 模型 |
|---|------|------|
| `z_image_turbo` | 快速文生图 | z_image_turbo + qwen_3_4b + ae VAE |
| `flux1_dev` | 高质量文生图 | flux1-dev-fp8 + clip_l + t5xxl |
| `flux2_dev` | 指令式编辑 | flux2 + mistral_3_small + decoder |
| `qwen_image` | Qwen 文生图 | qwen_image + qwen_2.5_vl + vae |
| `qwen_image_edit` | Qwen 指令编辑 | qwen_image_edit + encoder + vae |
| `wan22_i2v` | 图生视频 | Wan 2.2 14B i2v (high/low noise) |
| `wan22_t2v` | 文生视频 | Wan 2.2 14B t2v (high/low noise) |
| `wan21_vace` | 视频修复 | Wan 2.1 VACE 14B |
| `ltx23` | LTX 视频生成+放大 | LTX 2.3 22B + gemma + 空间放大器 |
| `ltx2_controlnet` | 视频 ControlNet | LTX 2.0 + canny/depth/pose LoRAs |
| `ace_step` | 音频生成 | ACE Step 1.5 turbo |
| `capybara` | HunyuanImage | Capybara + qwen_2.5_vl + sigclip |
| `hunyuan_3d` | 3D 模型生成 | Hunyuan 3D v2.1 |
| `sd15` | SD 1.5 工作流 | SD 1.5 + DreamShaper + MSE VAE |
| `sdxl` | SDXL 工作流 | SDXL Base + Refiner |

目录定义在 `comfyui_image/custom_nodes/comfyui-auto-model-downloader/model_catalog.json`，可通过添加新条目来扩展。

## 组件版本

| 组件 | 版本 |
|------|------|
| Amazon EKS | 1.32 |
| Karpenter | 1.3.0 |
| NVIDIA GPU Operator | 最新（驱动/工具包来自 AMI） |
| ComfyUI | v0.21.1 |
| PyTorch | 2.12.0 (CUDA 13.0) |
| Mountpoint S3 CSI Driver | v2.5.0 |
| AWS CDK | 2.1109.0 |
| EKS Blueprints | 1.18.2 |
| 节点 AMI | AL2023 GPU (driver 580+) |

## 成本预估

假设场景：

* 部署 1 台 g5.2xlarge 支持图像生成
* 一张 1024x1024 的图片生成平均需要 9s，平均大小为 1.5MB
* 每天使用时间为 8h，每月使用 20 天
* 每月可以生成 8 x 20 x 3600 / 9 = 64000 张图片
* 每月需要存储的图片大小为 64000 x 1.5MB / 1000 = 96GB
* DTO 流量大小约 100GB（96GB + HTTP 请求）
* ComfyUI 不同版本的镜像共 20G

使用此方案部署在 us-west-2 的总价约为 **$450/月**（因实例定价而异）：

| 服务 | 费用 | 详情 |
| --- | --- | --- |
| Amazon EKS (Control Plane) | $73 | 固定费用 |
| Amazon EC2 (GPU 节点) | $193.92 | 1 台 g5.2xlarge (按需), 8h/天 x 20 天 |
| Amazon EC2 (系统节点) | $137.68 | 2 台 t3a.xlarge (1 年 RI 无预付) |
| Amazon S3 (模型) | $2.3 | 100GB x $0.023/GB |
| Amazon S3 (输出) | $2.21 | ~96GB/月 轮转 |
| Amazon ECR | $2 | 20GB 镜像 x $0.1/GB |
| AWS ALB (内部) | $22.27 | 固定 + LCU 费用 |
| Amazon CloudFront | $8.5 | 100GB DTO x $0.085/GB |

## CloudFormation 堆栈

| 堆栈 | 描述 |
|------|------|
| `ComfyUI-on-EKS-Cluster` | EKS 集群，GPU 节点与 Karpenter 自动伸缩 |
| `ComfyUI-on-EKS-CloudFront` | CloudFront 分发，通过 VPC Origin 安全访问 |
| `ComfyUI-on-EKS-Models` | 模型 S3 存储桶与同步 Lambda 函数 |
| `ComfyUI-on-EKS-S3` | S3 存储桶，工作流输入与图片输出 |
| `ComfyUI-on-EKS-ECR` | ECR 仓库、容器镜像构建 CodeBuild 和模型下载 CodeBuild |

## 变更日志

### 重大升级 -- 2026.05.20

- 升级到 EKS 1.32（标准支持）、Karpenter 1.3.0、PyTorch 2.12.0、ComfyUI v0.21.1
- 容器构建迁移到 AWS CodeBuild（无需本地 Docker）
- 切换到 CloudFront VPC Origins（ALB 保持内部，永不暴露到公网）
- GPU Operator 驱动/工具包禁用（AL2023 GPU AMI 预装 NVIDIA 580+）
- CUDA 从 12.x 升级到 13.0.3
- S3 CSI 驱动升级到 v2.5.0
- 所有资源通过 CDK 全局标签打上 `Project: comfyui-on-eks`
- IAM 策略收紧为最小权限（移除 AdministratorAccess、节点上的 S3FullAccess）
- 移除 `PROJECT_NAME` 间接引用 — 简化为单一固定命名约定
- 所有 CloudFormation 堆栈添加描述

### 自动化部署 -- 2024.12.26

自动化部署脚本位于 `comfyui-on-eks/auto_deploy/`，支持 Ubuntu 和 macOS。

### Flux / SD3 / Custom Nodes 支持

ComfyUI v0.21.1 支持 Flux、Stable Diffusion 3 和自定义节点。使用任何模型：

1. 将模型上传到 S3 模型桶，遵循 `ComfyUI/models` 目录结构
2. 通过 API 使用对应的 workflow JSON（参考 `test/` 目录中的示例）
