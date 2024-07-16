#!/bin/bash

# Test docker image locally by running docker

TAG=latest
docker run -it -p 8848:8848 --gpus all \
        --mount src=/home/ubuntu/ComfyUI/models,target=/app/ComfyUI/models,type=bind \
        --mount src=/home/ubuntu/ComfyUI/input,target=/app/ComfyUI/input,type=bind \
        comfyui-images:${TAG}
