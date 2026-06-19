import io
import base64
import numpy as np
from PIL import Image
import boto3
import torch


def get_bedrock_client(region=None):
    import os
    if not region:
        region = os.environ.get("AWS_DEFAULT_REGION") or os.environ.get("AWS_REGION")
    if not region:
        session = boto3.session.Session()
        region = session.region_name or "us-west-2"
    return boto3.client("bedrock-runtime", region_name=region)


def tensor_to_pil(image_tensor):
    img_array = (image_tensor.squeeze(0).cpu().numpy() * 255).astype(np.uint8)
    return Image.fromarray(img_array)


def tensor_to_bytes(image_tensor, format="PNG", max_dim=None):
    img = tensor_to_pil(image_tensor)
    if max_dim and (img.width > max_dim or img.height > max_dim):
        ratio = min(max_dim / img.width, max_dim / img.height)
        img = img.resize((int(img.width * ratio), int(img.height * ratio)), Image.LANCZOS)
    buffer = io.BytesIO()
    img.save(buffer, format=format)
    return buffer.getvalue()


def tensor_to_base64(image_tensor, format="PNG", max_dim=None):
    return base64.b64encode(tensor_to_bytes(image_tensor, format, max_dim)).decode("utf-8")


def mask_to_bytes(mask_tensor, format="PNG"):
    mask_array = (mask_tensor.squeeze(0).cpu().numpy() * 255).astype(np.uint8)
    img = Image.fromarray(mask_array, mode="L")
    buffer = io.BytesIO()
    img.save(buffer, format=format)
    return buffer.getvalue()


def mask_to_base64(mask_tensor, format="PNG"):
    return base64.b64encode(mask_to_bytes(mask_tensor, format)).decode("utf-8")


def bytes_to_tensor(image_bytes):
    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    img_array = np.array(img).astype(np.float32) / 255.0
    return torch.from_numpy(img_array).unsqueeze(0)


def base64_to_tensor(b64_string):
    return bytes_to_tensor(base64.b64decode(b64_string))
