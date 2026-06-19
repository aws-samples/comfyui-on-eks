FROM nvcr.io/nvidia/cuda:13.0.3-cudnn-runtime-ubuntu24.04

WORKDIR /app

RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    git \
    python3.12 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --break-system-packages torch==2.12.0 torchvision==0.27.0 --extra-index-url https://download.pytorch.org/whl/cu130
RUN git clone https://github.com/comfyanonymous/ComfyUI.git
RUN cd /app/ComfyUI && git checkout v0.21.1
RUN pip3 install --break-system-packages -r /app/ComfyUI/requirements.txt
RUN pip3 install --break-system-packages requests==2.32.3

RUN cd /app/ComfyUI/custom_nodes && git clone https://github.com/kijai/ComfyUI-Florence2.git && \
    cd ComfyUI-Florence2 && git checkout 4e4ae42
RUN pip3 install --break-system-packages -r /app/ComfyUI/custom_nodes/ComfyUI-Florence2/requirements.txt

COPY custom_nodes/comfyui-bedrock /app/ComfyUI/custom_nodes/comfyui-bedrock
RUN pip3 install --break-system-packages -r /app/ComfyUI/custom_nodes/comfyui-bedrock/requirements.txt

COPY custom_nodes/comfyui-auto-model-downloader /app/ComfyUI/custom_nodes/comfyui-auto-model-downloader

RUN mkdir -p /app/ComfyUI/output/video

EXPOSE 8848
CMD ["python3", "-u", "/app/ComfyUI/main.py", "--listen", "0.0.0.0", "--port", "8848"]
