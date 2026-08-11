#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 <aws-region>"
    exit 1
fi

region=$1
account=$(aws sts get-caller-identity --query Account --output text)
bucket="comfyui-models-$account-$region"
echo "Uploading to bucket: $bucket"

dirs=(checkpoints clip clip_vision configs controlnet diffusers diffusion_models embeddings gligen hypernetworks loras style_models text_encoders unet upscale_models vae vae_approx model_patches latent_upscale_models)
for dir in "${dirs[@]}"
do
    mkdir -p ~/comfyui-models/$dir
    touch ~/comfyui-models/$dir/put_here
done

download() {
    local dest=$1
    local url=$2
    local name=$(basename "$dest")
    if [ -f "$dest" ]; then
        echo "Already downloaded: $name"
        return 0
    fi
    echo "Downloading $name..."
    curl -L --retry 3 --retry-delay 5 -o "$dest" "$url"
    if [ $? -ne 0 ]; then
        echo "FAILED: $name"
        rm -f "$dest"
        return 1
    fi
}

# ============================================================
# Template 01: Get Started (z_image_turbo)
# ============================================================
echo ""
echo "=== Template 01: z_image_turbo ==="
download ~/comfyui-models/diffusion_models/z_image_turbo_bf16.safetensors \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors?download=true"
download ~/comfyui-models/text_encoders/qwen_3_4b.safetensors \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors?download=true"
download ~/comfyui-models/vae/ae.safetensors \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors?download=true"

# ControlNet union for z_image_turbo workflows (canny, depth, pose)
download ~/comfyui-models/model_patches/Z-Image-Turbo-Fun-Controlnet-Union.safetensors \
    "https://huggingface.co/alibaba-pai/Z-Image-Turbo-Fun-Controlnet-Union/resolve/main/Z-Image-Turbo-Fun-Controlnet-Union.safetensors?download=true"

# ============================================================
# Template 02: Qwen Image Edit
# ============================================================
echo ""
echo "=== Template 02: Qwen Image Edit ==="
download ~/comfyui-models/diffusion_models/qwen_image_edit_2509_fp8_e4m3fn.safetensors \
    "https://huggingface.co/Comfy-Org/Qwen-Image-Edit_ComfyUI/resolve/main/split_files/diffusion_models/qwen_image_edit_2509_fp8_e4m3fn.safetensors?download=true"
download ~/comfyui-models/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors \
    "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors?download=true"
download ~/comfyui-models/vae/qwen_image_vae.safetensors \
    "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors?download=true"
download ~/comfyui-models/diffusion_models/qwen_image_fp8_e4m3fn.safetensors \
    "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/diffusion_models/qwen_image_fp8_e4m3fn.safetensors?download=true"

# ============================================================
# Template 03: Wan 2.2 Video (i2v)
# ============================================================
echo ""
echo "=== Template 03: Wan 2.2 Video ==="
download ~/comfyui-models/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors \
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors?download=true"
download ~/comfyui-models/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors \
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors?download=true"
download ~/comfyui-models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors \
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors?download=true"
download ~/comfyui-models/vae/wan_2.1_vae.safetensors \
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors?download=true"
download ~/comfyui-models/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors \
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors?download=true"
download ~/comfyui-models/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors \
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors?download=true"

# ============================================================
# Template 04: Hunyuan 3D 2.1
# ============================================================
echo ""
echo "=== Template 04: Hunyuan 3D 2.1 ==="
download ~/comfyui-models/checkpoints/hunyuan_3d_v2.1.safetensors \
    "https://huggingface.co/Comfy-Org/hunyuan3D_2.1_repackaged/resolve/main/hunyuan_3d_v2.1.safetensors?download=true"

# ============================================================
# Template 05: ACE Step Audio
# ============================================================
echo ""
echo "=== Template 05: ACE Step 1.5 Audio ==="
download ~/comfyui-models/diffusion_models/acestep_v1.5_turbo.safetensors \
    "https://huggingface.co/Comfy-Org/ace_step_1.5_ComfyUI_files/resolve/main/split_files/diffusion_models/acestep_v1.5_turbo.safetensors?download=true"
download ~/comfyui-models/text_encoders/qwen_0.6b_ace15.safetensors \
    "https://huggingface.co/Comfy-Org/ace_step_1.5_ComfyUI_files/resolve/main/split_files/text_encoders/qwen_0.6b_ace15.safetensors?download=true"
download ~/comfyui-models/text_encoders/qwen_4b_ace15.safetensors \
    "https://huggingface.co/Comfy-Org/ace_step_1.5_ComfyUI_files/resolve/main/split_files/text_encoders/qwen_4b_ace15.safetensors?download=true"
download ~/comfyui-models/vae/ace_1.5_vae.safetensors \
    "https://huggingface.co/Comfy-Org/ace_step_1.5_ComfyUI_files/resolve/main/split_files/vae/ace_1.5_vae.safetensors?download=true"

# ============================================================
# Flux 1 Dev
# ============================================================
echo ""
echo "=== Flux 1 Dev ==="
download ~/comfyui-models/diffusion_models/flux1-dev.safetensors \
    "https://huggingface.co/Comfy-Org/flux1-dev/resolve/main/flux1-dev-fp8.safetensors?download=true"
download ~/comfyui-models/text_encoders/clip_l.safetensors \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors?download=true"
download ~/comfyui-models/text_encoders/t5xxl_fp16.safetensors \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors?download=true"

# ============================================================
# Archived SD checkpoints
# ============================================================
echo ""
echo "=== SD Checkpoints ==="
download ~/comfyui-models/checkpoints/v1-5-pruned-emaonly-fp16.safetensors \
    "https://huggingface.co/Comfy-Org/stable-diffusion-v1-5-archive/resolve/main/v1-5-pruned-emaonly-fp16.safetensors?download=true"
download ~/comfyui-models/checkpoints/sd_xl_base_1.0.safetensors \
    "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors?download=true"
download ~/comfyui-models/checkpoints/sd_xl_refiner_1.0.safetensors \
    "https://huggingface.co/stabilityai/stable-diffusion-xl-refiner-1.0/resolve/main/sd_xl_refiner_1.0.safetensors?download=true"
download ~/comfyui-models/checkpoints/DreamShaper_8_pruned.safetensors \
    "https://huggingface.co/Lykon/DreamShaper/resolve/main/DreamShaper_8_pruned.safetensors?download=true"
download ~/comfyui-models/checkpoints/512-inpainting-ema.safetensors \
    "https://huggingface.co/stabilityai/stable-diffusion-2-inpainting/resolve/main/512-inpainting-ema.safetensors?download=true"
download ~/comfyui-models/checkpoints/v2-1_768-ema-pruned.safetensors \
    "https://huggingface.co/stabilityai/stable-diffusion-2-1/resolve/main/v2-1_768-ema-pruned.safetensors?download=true"
download ~/comfyui-models/checkpoints/svd.safetensors \
    "https://huggingface.co/stabilityai/stable-video-diffusion-img2vid/resolve/main/svd.safetensors?download=true"

# ============================================================
# ControlNets (SD 1.5)
# ============================================================
echo ""
echo "=== ControlNets ==="
download ~/comfyui-models/controlnet/control_v11p_sd15_scribble_fp16.safetensors \
    "https://huggingface.co/comfyanonymous/ControlNet-v1-1_fp16_safetensors/resolve/main/control_v11p_sd15_scribble_fp16.safetensors?download=true"
download ~/comfyui-models/controlnet/control_v11p_sd15_openpose_fp16.safetensors \
    "https://huggingface.co/comfyanonymous/ControlNet-v1-1_fp16_safetensors/resolve/main/control_v11p_sd15_openpose_fp16.safetensors?download=true"
download ~/comfyui-models/controlnet/control_v11f1p_sd15_depth_fp16.safetensors \
    "https://huggingface.co/comfyanonymous/ControlNet-v1-1_fp16_safetensors/resolve/main/control_v11f1p_sd15_depth_fp16.safetensors?download=true"

# ============================================================
# VAEs
# ============================================================
echo ""
echo "=== VAEs ==="
download ~/comfyui-models/vae/vae-ft-mse-840000-ema-pruned.safetensors \
    "https://huggingface.co/stabilityai/sd-vae-ft-mse-original/resolve/main/vae-ft-mse-840000-ema-pruned.safetensors?download=true"

# ============================================================
# Upscale Models
# ============================================================
echo ""
echo "=== Upscale Models ==="
download ~/comfyui-models/upscale_models/RealESRGAN_x4plus.safetensors \
    "https://huggingface.co/Comfy-Org/Real-ESRGAN_repackaged/resolve/main/RealESRGAN_x4plus.safetensors?download=true"

# ============================================================
# Depth estimation (lotus)
# ============================================================
echo ""
echo "=== Depth Estimation ==="
download ~/comfyui-models/diffusion_models/lotus-depth-d-v1-1.safetensors \
    "https://huggingface.co/Comfy-Org/lotus/resolve/main/lotus-depth-d-v1-1.safetensors?download=true"

# ============================================================
# Qwen Image Lightning LoRAs (speed up Qwen workflows)
# ============================================================
echo ""
echo "=== Qwen Lightning LoRAs ==="
download ~/comfyui-models/loras/Qwen-Image-Lightning-8steps-V1.0.safetensors \
    "https://huggingface.co/lightx2v/Qwen-Image-Lightning/resolve/main/Qwen-Image-Lightning-8steps-V1.0.safetensors?download=true"
download ~/comfyui-models/loras/Qwen-Image-Edit-2509-Lightning-4steps-V1.0-bf16.safetensors \
    "https://huggingface.co/lightx2v/Qwen-Image-Edit-2509-Lightning/resolve/main/Qwen-Image-Edit-2509-Lightning-4steps-V1.0-bf16.safetensors?download=true"

# ============================================================
# Upload all to S3
# ============================================================
echo ""
echo "=== Uploading all models to S3 ==="
aws s3 sync ~/comfyui-models s3://$bucket/ --region $region
if [ $? -ne 0 ]; then
    echo "S3 upload failed!"
    exit 1
fi
echo "Upload complete!"
rm -rf ~/comfyui-models
