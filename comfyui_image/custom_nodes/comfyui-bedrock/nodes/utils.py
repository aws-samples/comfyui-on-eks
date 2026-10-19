import io
import json
import base64
import numpy as np
from PIL import Image
import boto3
from botocore.config import Config
from botocore.exceptions import ClientError, BotoCoreError
import torch


# Bedrock image/video invocations can take 30-120s; the default 60s read timeout
# and "legacy" retry mode cause premature ReadTimeout and unretried throttling.
# Adaptive retries + a generous read timeout cover the long-running InvokeModel /
# Converse / StartAsyncInvoke calls used by every node.
_BEDROCK_CONFIG = Config(
    read_timeout=300,
    connect_timeout=10,
    retries={"max_attempts": 5, "mode": "adaptive"},
)


def _resolve_region(region=None):
    import os
    if not region:
        region = os.environ.get("AWS_DEFAULT_REGION") or os.environ.get("AWS_REGION")
    if not region:
        session = boto3.session.Session()
        region = session.region_name or "us-west-2"
    return region


def get_bedrock_client(region=None):
    return boto3.client("bedrock-runtime", region_name=_resolve_region(region), config=_BEDROCK_CONFIG)


def invoke_stability_model(client, model_id, body):
    """Invoke a Stability InvokeModel call and return the first output image as a tensor.

    Centralizes error handling for all Stability nodes: surfaces ClientError with
    the model id and error code, and guards content-filtered / empty responses
    instead of raising a bare KeyError/IndexError.
    """
    try:
        response = client.invoke_model(
            modelId=model_id,
            body=json.dumps(body),
            contentType="application/json",
            accept="application/json",
        )
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code", "Unknown")
        msg = e.response.get("Error", {}).get("Message", str(e))
        raise RuntimeError(f"Bedrock InvokeModel failed for {model_id} [{code}]: {msg}") from e
    except BotoCoreError as e:
        raise RuntimeError(f"Bedrock InvokeModel failed for {model_id}: {e}") from e

    result = json.loads(response["body"].read())
    images = result.get("images")
    if not images:
        finish = result.get("finish_reasons") or result.get("finishReasons")
        raise RuntimeError(
            f"Bedrock model {model_id} returned no image "
            f"(finish_reasons={finish}); the request may have been content-filtered."
        )
    return base64_to_tensor(images[0])


def invoke_converse(client, kwargs):
    """Run a Converse call and return the concatenated text.

    Handles reasoning models (which emit a reasoningContent block and may spend
    the whole token budget before any text), responses with multiple text blocks,
    and empty/truncated responses -- instead of blindly indexing content[0]["text"].
    """
    model_id = kwargs.get("modelId", "?")
    try:
        response = client.converse(**kwargs)
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code", "Unknown")
        msg = e.response.get("Error", {}).get("Message", str(e))
        raise RuntimeError(f"Bedrock Converse failed for {model_id} [{code}]: {msg}") from e
    except BotoCoreError as e:
        raise RuntimeError(f"Bedrock Converse failed for {model_id}: {e}") from e

    content = response.get("output", {}).get("message", {}).get("content", []) or []
    texts = [b["text"] for b in content if isinstance(b, dict) and "text" in b]
    if not texts:
        stop = response.get("stopReason")
        if stop == "max_tokens":
            raise RuntimeError(
                f"Bedrock model {model_id} returned no text (stopReason=max_tokens). "
                "If this is a reasoning model, raise max_tokens so it has room to answer "
                "beyond its reasoning tokens."
            )
        raise RuntimeError(f"Bedrock model {model_id} returned no text (stopReason={stop}).")
    return "\n".join(texts)


def tensor_to_pil(image_tensor):
    # ComfyUI IMAGE tensors are [batch, H, W, C]; these Bedrock nodes operate on a
    # single image, so take the first batch element explicitly rather than relying
    # on squeeze (which only drops the batch dim when batch==1).
    arr = image_tensor[0] if image_tensor.dim() == 4 else image_tensor
    img_array = (arr.cpu().numpy() * 255).astype(np.uint8)
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
    # MASK tensors are [batch, H, W]; take the first element explicitly (single-image contract).
    m = mask_tensor[0] if mask_tensor.dim() == 3 else mask_tensor
    mask_array = (m.cpu().numpy() * 255).astype(np.uint8)
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
