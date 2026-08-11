FROM nvcr.io/nvidia/cuda:13.0.3-cudnn-runtime-ubuntu24.04

WORKDIR /app

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --only-upgrade \
    liblzma5 libsqlite3-0 sqlite3 libpam0g libpam-runtime libpam-modules libpam-modules-bin \
    libgcrypt20 libgnutls30t64 libssl3t64 openssl ca-certificates \
    libsmartcols1 libmount1 libblkid1 libuuid1 util-linux \
    libudev1 libsystemd0 libcap2 libtasn1-6 sed gnupg gnupg2 xz-utils && \
    apt-get install -y \
    git \
    python3 \
    python3.12 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Shadow pip and wheel in /usr/local, then purge the dpkg-tracked versions WITHOUT autoremove.
# Inspector2 scans the dpkg database; ESM-only CVE fixes for python3-pip/python3-wheel
# are unavailable without an Ubuntu Pro subscription. Purging removes them from the
# scan surface. autoremove is intentionally omitted — it would also remove python3.
RUN pip3 install --break-system-packages --ignore-installed "pip>=24.3" "wheel>=0.46.2" && \
    apt-get purge -y python3-pip python3-wheel && \
    rm -rf /var/lib/apt/lists/*
RUN pip3 install --break-system-packages torch==2.12.0 torchvision==0.27.0 --extra-index-url https://download.pytorch.org/whl/cu130
RUN git clone https://github.com/comfyanonymous/ComfyUI.git
RUN cd /app/ComfyUI && git checkout 26515acd23fa291a8f5ab53c5997258598de0701
RUN pip3 install --break-system-packages -r /app/ComfyUI/requirements.txt
RUN pip3 install --break-system-packages requests==2.32.3

RUN cd /app/ComfyUI/custom_nodes && git clone https://github.com/kijai/ComfyUI-Florence2.git && \
    cd ComfyUI-Florence2 && git checkout 9ece3de914214c5f581d725167bc9d0eeb0d1120
RUN pip3 install --break-system-packages -r /app/ComfyUI/custom_nodes/ComfyUI-Florence2/requirements.txt

COPY custom_nodes/comfyui-bedrock /app/ComfyUI/custom_nodes/comfyui-bedrock
RUN pip3 install --break-system-packages -r /app/ComfyUI/custom_nodes/comfyui-bedrock/requirements.txt

COPY custom_nodes/comfyui-auto-model-downloader /app/ComfyUI/custom_nodes/comfyui-auto-model-downloader

RUN mkdir -p /app/ComfyUI/output/video

EXPOSE 8848
CMD ["python3", "-u", "/app/ComfyUI/main.py", "--listen", "0.0.0.0", "--port", "8848"]
