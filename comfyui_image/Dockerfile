FROM nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04

WORKDIR /app

RUN apt-get update && apt-get install -y \
    git \
    python3.10 \
    python3-pip

# Python Evn
RUN pip3 install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu121
RUN git clone https://github.com/comfyanonymous/ComfyUI.git
RUN cd /app/ComfyUI && git checkout v0.3.9
RUN pip3 install -r /app/ComfyUI/requirements.txt

EXPOSE 8848
CMD ["python3", "-u", "/app/ComfyUI/main.py", "--listen", "0.0.0.0", "--port", "8848"]
