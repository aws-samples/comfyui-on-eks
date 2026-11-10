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
| Anthropic (**default**) | `us.anthropic.claude-haiku-5-5` | Latest Claude, fast — node default |
| Anthropic | `us.anthropic.claude-sonnet-5-5` | Latest Claude, balanced |
| Anthropic | `us.anthropic.claude-opus-5-5` | Latest Claude, most capable |
| OpenAI | `us.openai.gpt-6.1-sol` | Latest GPT |
| OpenAI | `us.openai.gpt-6-sol` | GPT 6 |
| OpenAI | `us.openai.gpt-5.5` | GPT 5.5 |
| OpenAI | `openai.gpt-oss-120b-1:0` | 120B (open weight) |
| xAI | `us.xai.grok-4.7` | Latest Grok |
| Mistral | `mistral.mistral-large-3-675b-instruct` | 675B large (open weight) |
| Mistral | `mistral.ministral-3-14b-instruct` | 14B (open weight) |
| Mistral | `mistral.magistral-small-2509` | reasoning (open weight) |
| NVIDIA | `nvidia.nemotron-super-3-120b` | 120B (open weight) |
| NVIDIA | `nvidia.nemotron-nano-3-30b` | 30B (open weight) |
| DeepSeek | `deepseek.v3.2` | V3.2 (open weight) |
| MiniMax | `minimax.minimax-m2.5` | M2.5 (open weight) |
| Z.AI | `zai.glm-5` | GLM-5 (open weight) |
| Qwen | `qwen.qwen3-235b-a22b-2507-v1:0` | 235B MoE (open weight) |
| Qwen | `qwen.qwen3-next-80b-a3b` | 80B MoE (open weight) |
| Qwen | `qwen.qwen3-32b-v1:0` | 32B dense (open weight) |

> Default is **Claude Haiku 5.5**. Claude 5.x rejects `temperature`/`topP`, so the node sends those only when changed from defaults — the default path works across every model above. Amazon Nova has been removed — the Nova line is being deprecated by AWS (Nova Premier already EOL; Nova Canvas/Reel removed earlier). Models in the Bedrock Legacy state (EOL March 30, 2027) — Llama 3.3/4, Nemotron Nano 9B v2, DeepSeek R1 — have also been removed.

#### Vision + Text (Bedrock Vision node)

| Provider | Model ID | Notes |
|----------|----------|-------|
| Anthropic | `us.anthropic.claude-haiku-5-5` | Fast vision (default) |
| Anthropic | `us.anthropic.claude-sonnet-5-5` | Balanced vision |
| Anthropic | `us.anthropic.claude-opus-5-5` | Most capable vision |
| xAI | `us.xai.grok-4.7` | Latest Grok, multimodal |
| Mistral | `us.mistral.pixtral-large-2502-v1:0` | Pixtral Large |
| Mistral | `mistral.ministral-3-14b-instruct` | 14B multimodal (open weight) |
| Mistral | `mistral.ministral-3-8b-instruct` | 8B multimodal (open weight) |
| Qwen | `qwen.qwen3-vl-235b-a22b` | 235B vision-language |

> Llama 4 Scout/Maverick and Gemma 3 27B/12B were removed: they are in the Bedrock Legacy state (EOL March 30, 2027).

## Image Generation & Editing

### Image Generation

Bedrock no longer has an Active text-to-image model to wire here. Amazon's native
image models (Nova Canvas, Titan Image Generator) are deprecated, and Stability AI
moved all three of its Bedrock text-to-image models (SD 3.5 Large, Stable Image
Core, Stable Image Ultra) to the Legacy state on November 9, 2026 (end of life
May 9, 2027), so the **Bedrock Stability Generate** node has been removed.

For text-to-image, use a local checkpoint on the GPU node instead. SD 3.5 Large
and Medium, FLUX.1, SDXL and SD 1.5 are in the auto-model-downloader catalog and
are fetched from Hugging Face the first time a workflow needs them.

The Stability editing models are separate and still Active:

| Former Nova Canvas task | Use instead |
|-------------------------|-------------|
| TEXT_IMAGE / IMAGE_VARIATION | Local SD 3.5 / FLUX / SDXL checkpoint |
| INPAINTING | **Bedrock Stability Inpaint** |
| OUTPAINTING | **Bedrock Stability Outpaint** |
| BACKGROUND_REMOVAL | **Bedrock Stability Remove Background** |
| COLOR_GUIDED_GENERATION | **Bedrock Stability Search & Recolor** / **Style Guide** |

See the Stability sections below for inputs and model IDs.

### Stability AI Nodes

| Node | Capability | Model |
|------|-----------|-------|
| Bedrock Stability Inpaint | Fill masked regions | stable-image-inpaint-v1 |
| Bedrock Stability Outpaint | Extend image borders | stable-outpaint-v1 |
| Bedrock Stability Upscale | Upscale (fast/conservative/creative) | 3 model variants |
| Bedrock Stability Remove Background | Background removal; outputs `image` (subject on black) and `mask` (1 = removed background). Wire both into core's **Join Image with Alpha** to save a transparent PNG | stable-image-remove-background-v1 |
| Bedrock Stability Control (Structure/Sketch) | Guided generation from control image | structure + sketch variants |
| Bedrock Stability Search & Replace | Find and replace objects by description | stable-image-search-replace-v1 |
| Bedrock Stability Search & Recolor | Find and recolor objects | stable-image-search-recolor-v1 |
| Bedrock Stability Style Transfer | Transfer style between images | stable-style-transfer-v1 |
| Bedrock Stability Style Guide | Style-guided generation | stable-image-style-guide-v1 |
| Bedrock Stability Erase Object | Remove objects via mask | stable-image-erase-object-v1 |

## Video Generation

### Bedrock Luma Ray v2 (Video)

Text-to-video and image-to-video via Luma Ray v2. Produces 5-9 second clips with configurable aspect ratio. Outputs to S3.

**Inputs:** prompt, s3_output_bucket, s3_output_prefix, aspect_ratio, duration_seconds, optional image
**Output:** s3_video_uri (STRING)

## Node Reference

| Node | Category | Description |
|------|----------|-------------|
| Bedrock Text (Converse) | Bedrock | Text generation with 19 LLMs |
| Bedrock Vision (Converse) | Bedrock | Image understanding with 8 multimodal models |
| Bedrock Luma Ray v2 (Video) | Bedrock/Luma | Text/image-to-video |
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
