# Amazon Bedrock Nodes for ComfyUI

Custom nodes that integrate Amazon Bedrock foundation models into ComfyUI workflows. Access text generation, image understanding, image generation, and video creation without local GPU models — all inference runs on AWS.

## Text & Vision Nodes (Converse API)

These two nodes provide access to multiple LLM providers through a single interface. Select the model from the dropdown — no additional setup required.

### Bedrock Text (Converse)

Sends a text prompt to any supported Bedrock LLM and returns generated text. Use for prompt enhancement, creative writing, content generation, or any text task within a workflow.

**Inputs:** prompt, model_id, max_tokens, temperature, top_p, optional system_prompt
**Output:** text (STRING)

### Bedrock Vision (Converse)

Sends an image + text prompt to a multimodal model. Use for image captioning, scene analysis, visual question answering, or extracting information from images.

**Inputs:** image, prompt, model_id, max_tokens, temperature, optional system_prompt
**Output:** text (STRING)

### Available Models

#### Text Generation (Bedrock Text node)

| Provider | Model ID | Notes |
|----------|----------|-------|
| Amazon | `us.amazon.nova-lite-v1:0` | Fast, cost-effective |
| Amazon | `us.amazon.nova-pro-v1:0` | Balanced performance |
| Amazon | `us.amazon.nova-micro-v1:0` | Lowest latency |
| Anthropic | `us.anthropic.claude-opus-4-7` | Most capable |
| Anthropic | `us.anthropic.claude-sonnet-4-6` | Balanced |
| Anthropic | `us.anthropic.claude-haiku-4-5-20251001-v1:0` | Fast |
| DeepSeek | `us.deepseek.r1-v1:0` | Reasoning model |
| Meta | `us.meta.llama4-scout-17b-instruct-v1:0` | 17B scout |
| Meta | `us.meta.llama4-maverick-17b-instruct-v1:0` | 17B maverick |
| Meta | `us.meta.llama3-3-70b-instruct-v1:0` | 70B instruct |
| Mistral | `mistral.mistral-large-3-675b-instruct` | 675B large |
| Qwen | `qwen.qwen3-235b-a22b-2507-v1:0` | 235B MoE |
| Qwen | `qwen.qwen3-32b-v1:0` | 32B dense |
| Qwen | `qwen.qwen3-next-80b-a3b` | 80B next |
| Qwen | `qwen.qwen3-coder-480b-a35b-v1:0` | 480B coder |

#### Vision + Text (Bedrock Vision node)

| Provider | Model ID | Notes |
|----------|----------|-------|
| Amazon | `us.amazon.nova-lite-v1:0` | Fast multimodal |
| Amazon | `us.amazon.nova-pro-v1:0` | Balanced multimodal |
| Anthropic | `us.anthropic.claude-opus-4-7` | Most capable vision |
| Anthropic | `us.anthropic.claude-sonnet-4-6` | Balanced vision |
| Anthropic | `us.anthropic.claude-haiku-4-5-20251001-v1:0` | Fast vision |
| Meta | `us.meta.llama4-scout-17b-instruct-v1:0` | Multimodal scout |
| Meta | `us.meta.llama4-maverick-17b-instruct-v1:0` | Multimodal maverick |
| Mistral | `us.mistral.pixtral-large-2502-v1:0` | Pixtral Large |
| Mistral | `mistral.mistral-large-3-675b-instruct` | Large with vision |
| Google | `google.gemma-3-27b-it` | 27B multimodal |
| Google | `google.gemma-3-12b-it` | 12B multimodal |
| Qwen | `qwen.qwen3-vl-235b-a22b` | 235B vision-language |

## Image Generation & Editing

### Bedrock Nova Canvas

Multi-mode image generation and editing using Amazon Nova Canvas.

**Task types:** TEXT_IMAGE, INPAINTING, OUTPAINTING, IMAGE_VARIATION, BACKGROUND_REMOVAL, COLOR_GUIDED_GENERATION

**Inputs:** prompt, task_type, width, height, cfg_scale, seed, optional image/mask/negative_prompt
**Output:** image

### Stability AI Nodes

| Node | Capability | Model |
|------|-----------|-------|
| Bedrock Stability Generate | Text-to-image / image-to-image | SD 3.5 Large, Stable Image Core, Stable Image Ultra |
| Bedrock Stability Inpaint | Fill masked regions | stable-image-inpaint-v1 |
| Bedrock Stability Outpaint | Extend image borders | stable-outpaint-v1 |
| Bedrock Stability Upscale | Upscale (fast/conservative/creative) | 3 model variants |
| Bedrock Stability Remove Background | Background removal | stable-image-remove-background-v1 |
| Bedrock Stability Control (Structure/Sketch) | Guided generation from control image | structure + sketch variants |
| Bedrock Stability Search & Replace | Find and replace objects by description | stable-image-search-replace-v1 |
| Bedrock Stability Search & Recolor | Find and recolor objects | stable-image-search-recolor-v1 |
| Bedrock Stability Style Transfer | Transfer style between images | stable-style-transfer-v1 |
| Bedrock Stability Style Guide | Style-guided generation | stable-image-style-guide-v1 |
| Bedrock Stability Erase Object | Remove objects via mask | stable-image-erase-object-v1 |

## Video Generation

### Bedrock Nova Reel (Video)

Text-to-video and image-to-video generation using Amazon Nova Reel. Produces 6-second clips at 1280x720, 24fps. Outputs to S3.

**Inputs:** prompt, s3_output_bucket, s3_output_prefix, seed, optional image (for img2vid)
**Output:** s3_video_uri (STRING)

### Bedrock Luma Ray v2 (Video)

Text-to-video and image-to-video via Luma Ray v2. Produces 5-9 second clips with configurable aspect ratio. Outputs to S3.

**Inputs:** prompt, s3_output_bucket, s3_output_prefix, aspect_ratio, duration_seconds, optional image
**Output:** s3_video_uri (STRING)

## Node Reference

| Node | Category | Description |
|------|----------|-------------|
| Bedrock Text (Converse) | Bedrock | Text generation with 15+ LLMs |
| Bedrock Vision (Converse) | Bedrock | Image understanding with 12+ multimodal models |
| Bedrock Nova Canvas | Bedrock/Nova Canvas | Image generation and editing (6 modes) |
| Bedrock Nova Reel (Video) | Bedrock/Nova Reel | Text/image-to-video |
| Bedrock Luma Ray v2 (Video) | Bedrock/Luma | Text/image-to-video |
| Bedrock Stability Generate | Bedrock/Stability | Text-to-image with SD3.5/Core/Ultra |
| Bedrock Stability Inpaint | Bedrock/Stability | Mask-based inpainting |
| Bedrock Stability Outpaint | Bedrock/Stability | Extend image boundaries |
| Bedrock Stability Upscale | Bedrock/Stability | Image upscaling (3 modes) |
| Bedrock Stability Remove Background | Bedrock/Stability | Background removal |
| Bedrock Stability Control | Bedrock/Stability | Structure/sketch-guided generation |
| Bedrock Stability Search & Replace | Bedrock/Stability | Text-guided object replacement |
| Bedrock Stability Search & Recolor | Bedrock/Stability | Text-guided recoloring |
| Bedrock Stability Style Transfer | Bedrock/Stability | Style transfer between images |
| Bedrock Stability Style Guide | Bedrock/Stability | Style-guided generation |
| Bedrock Stability Erase Object | Bedrock/Stability | Mask-based object removal |

## Requirements

- AWS credentials with Bedrock access (provided automatically via EKS pod IAM role)
- Model access must be enabled in the AWS Bedrock console for your account/region
- Region: defaults to `us-west-2` (configurable via `AWS_DEFAULT_REGION`)
