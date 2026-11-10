FROM nvcr.io/nvidia/cuda:13.0.3-cudnn-runtime-ubuntu24.04

WORKDIR /app

# Optional Ubuntu archive mirror (e.g. us-west-2.ec2.archive.ubuntu.com, Canonical's
# in-region EC2 mirror). The CodeBuild buildspec passes the build region's mirror so
# the build does not depend on archive.ubuntu.com being reachable. Empty = default.
ARG UBUNTU_MIRROR=""
RUN if [ -n "$UBUNTU_MIRROR" ]; then \
      sed -i "s#http://archive.ubuntu.com/ubuntu#http://${UBUNTU_MIRROR}/ubuntu#g" /etc/apt/sources.list.d/ubuntu.sources; \
    fi

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
# torch 2.14.1 (2026-09-30) + torchvision 0.29.1: newest matched pair published for cu130.
RUN pip3 install --break-system-packages torch==2.14.1 torchvision==0.29.1 --extra-index-url https://download.pytorch.org/whl/cu130
RUN git clone https://github.com/comfyanonymous/ComfyUI.git
# ComfyUI v0.44.2 (released 2026-11-06). Newest patch tag one minor behind the v0.45.x
# line cut on 2026-11-10, to pick up a few days of soak.
RUN cd /app/ComfyUI && git checkout e6515b16ed360b01bd6548bffaca193f88f181fb
RUN pip3 install --break-system-packages -r /app/ComfyUI/requirements.txt
RUN pip3 install --break-system-packages requests==2.34.2

# ComfyUI-Florence2 v1.1.0 (9ece3de, 2026-05-06) — verified current tip of main as of
# the v0.41.3 upgrade. Since 9acc6e9 the node runs the model natively without transformers,
# which avoids transformers-version breakage against newer ComfyUI.
RUN cd /app/ComfyUI/custom_nodes && git clone https://github.com/kijai/ComfyUI-Florence2.git && \
    cd ComfyUI-Florence2 && git checkout 9ece3de914214c5f581d725167bc9d0eeb0d1120
RUN pip3 install --break-system-packages -r /app/ComfyUI/custom_nodes/ComfyUI-Florence2/requirements.txt

COPY custom_nodes/comfyui-bedrock /app/ComfyUI/custom_nodes/comfyui-bedrock
RUN pip3 install --break-system-packages -r /app/ComfyUI/custom_nodes/comfyui-bedrock/requirements.txt

COPY custom_nodes/comfyui-auto-model-downloader /app/ComfyUI/custom_nodes/comfyui-auto-model-downloader

RUN mkdir -p /app/ComfyUI/output/video

EXPOSE 8848
# --offline: since v0.44, ComfyUI registers POST /api/deploy/bundle, which uploads an
# installation snapshot (custom nodes, model list) to Comfy-Org's cloud builder. This
# deployment has no authentication in front of CloudFront by default, so any visitor could
# trigger that upload. --offline disables it, also disables Comfy-Org partner (paid API)
# nodes, and makes the browser UI load only same-origin content. The Bedrock nodes and the
# auto-model-downloader run server-side / same-origin and are unaffected.
CMD ["python3", "-u", "/app/ComfyUI/main.py", "--listen", "0.0.0.0", "--port", "8848", "--offline"]
