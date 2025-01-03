#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 <aws-region>"
    exit 1
fi

region=$1
account=$(aws sts get-caller-identity --query Account --output text)
PROJECT_NAME=$(node -e "const { PROJECT_NAME } = require('../env.ts'); console.log(PROJECT_NAME);" 2> /dev/null)
project_name=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')
bucket="comfyui-models${project_name:+-$project_name}-$account-$region"
echo "Uploading to bucket: $bucket"

dirs=(checkpoints clip clip_vision configs controlnet diffusers embeddings gligen hypernetworks loras style_models unet upscale_models vae vae_approx)
for dir in "${dirs[@]}"
do
    mkdir -p ~/comfyui-models/$dir
    touch ~/comfyui-models/$dir/put_here
done

curl -L -o ~/comfyui-models/checkpoints/sd_xl_base_1.0.safetensors "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors?download=true"
curl -L -o ~/comfyui-models/checkpoints/sd_xl_refiner_1.0.safetensors "https://huggingface.co/stabilityai/stable-diffusion-xl-refiner-1.0/resolve/main/sd_xl_refiner_1.0.safetensors?download=true"

aws s3 sync ~/comfyui-models s3://$bucket/ --region $region
rm -rf ~/comfyui-models