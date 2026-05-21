"""
Auto Model Downloader - Transparently downloads missing models before workflow execution.

When a workflow is queued, this extension intercepts the prompt via a frontend JS hook,
identifies any model files not available locally, triggers download from S3 (or HuggingFace),
and automatically re-queues execution once all models are present.
"""

import json
import os
import threading
import logging

from aiohttp import web
from server import PromptServer
import folder_paths

from .model_resolver import ModelResolver

logger = logging.getLogger("AutoModelDownloader")

resolver = ModelResolver()
_download_lock = threading.Lock()
_active_downloads: dict[str, str] = {}

WEB_DIRECTORY = "./web"
NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}
__all__ = ["NODE_CLASS_MAPPINGS", "NODE_DISPLAY_NAME_MAPPINGS", "WEB_DIRECTORY"]


# Patch folder_paths.get_filename_list to include catalog entries as virtual files.
# This allows ComfyUI's server-side combo validation to pass for models that are in
# our catalog but not yet downloaded — the auto-downloader will fetch them at execution.
_original_get_filename_list = folder_paths.get_filename_list

def _patched_get_filename_list(folder_name: str) -> list[str]:
    result = _original_get_filename_list(folder_name)
    catalog_additions = _get_catalog_filenames(folder_name)
    if catalog_additions:
        existing = set(result)
        for filename in catalog_additions:
            if filename not in existing:
                result.append(filename)
    return result

def _get_catalog_filenames(folder_name: str) -> list[str]:
    """Return filenames from the catalog that belong to this folder type."""
    filenames = []
    prefix = f"{folder_name}/"
    for key in resolver.catalog:
        if key.startswith(prefix):
            filename = key[len(prefix):]
            filenames.append(filename)
    return filenames

folder_paths.get_filename_list = _patched_get_filename_list


@PromptServer.instance.routes.get("/auto-model-downloader/status")
async def get_status(request):
    with _download_lock:
        return web.json_response({
            "active_downloads": dict(_active_downloads),
            "catalog_size": len(resolver.catalog),
        })


@PromptServer.instance.routes.post("/auto-model-downloader/check")
async def check_models(request):
    """Check which models from a prompt are missing and trigger downloads."""
    data = await request.json()
    prompt = data.get("prompt", {})
    use_bedrock = data.get("use_bedrock", False)
    force_download = data.get("force_download", False)

    missing = resolver.find_missing_models(prompt)
    if not missing:
        return web.json_response({"status": "ready", "missing": []})

    all_needed = resolver.resolve_dependencies(missing)
    actually_missing = [m for m in all_needed if not resolver.is_model_available(m)]

    if not actually_missing:
        return web.json_response({"status": "ready", "missing": []})

    bedrock_alternatives = resolver.get_bedrock_alternatives(actually_missing)

    if bedrock_alternatives and not use_bedrock and not force_download:
        return web.json_response({
            "status": "bedrock_available",
            "missing": actually_missing,
            "bedrock_alternatives": bedrock_alternatives,
            "message": f"{len(bedrock_alternatives)} model(s) have Bedrock alternatives available. Use Bedrock for instant access without downloading.",
        })

    if use_bedrock:
        models_to_download = [m for m in actually_missing if m not in bedrock_alternatives]
    else:
        models_to_download = actually_missing

    if models_to_download:
        _trigger_downloads(models_to_download)

    return web.json_response({
        "status": "downloading" if models_to_download else "ready",
        "missing": models_to_download,
        "bedrock_models": list(bedrock_alternatives.keys()) if use_bedrock else [],
        "message": f"Downloading {len(models_to_download)} model(s)." if models_to_download else "Using Bedrock alternatives.",
    })


@PromptServer.instance.routes.post("/auto-model-downloader/download")
async def trigger_download(request):
    """Manually trigger download of specific models."""
    data = await request.json()
    models = data.get("models", [])
    if not models:
        return web.json_response({"error": "No models specified"}, status=400)

    all_needed = resolver.resolve_dependencies(models)
    actually_missing = [m for m in all_needed if not resolver.is_model_available(m)]

    if not actually_missing:
        return web.json_response({"status": "ready", "message": "All models already available"})

    _trigger_downloads(actually_missing)
    return web.json_response({
        "status": "downloading",
        "models": actually_missing,
    })


def _trigger_downloads(models: list[str]):
    """Start background download of models from S3."""
    thread = threading.Thread(target=_download_worker, args=(models,), daemon=True)
    thread.start()


def _download_worker(models: list[str]):
    """Download models from S3 to local model directory."""
    import subprocess
    import boto3

    region = os.environ.get("AWS_DEFAULT_REGION", "us-west-2")
    try:
        account_id = boto3.client("sts").get_caller_identity()["Account"]
    except Exception:
        account_id = os.environ.get("AWS_ACCOUNT_ID", "")
    bucket = f"comfyui-models-{account_id}-{region}"
    s3 = boto3.client("s3", region_name=region)

    for model_path in models:
        with _download_lock:
            if model_path in _active_downloads and _active_downloads[model_path] == "downloading":
                continue
            _active_downloads[model_path] = "downloading"

        try:
            local_path = resolver.get_local_path(model_path)
            if local_path and os.path.exists(local_path):
                with _download_lock:
                    _active_downloads[model_path] = "complete"
                continue

            if _try_download_from_s3(s3, bucket, model_path):
                logger.info(f"Downloaded from S3: {model_path}")
                with _download_lock:
                    _active_downloads[model_path] = "complete"
                continue

            if _try_download_from_huggingface(model_path):
                logger.info(f"Downloaded from HuggingFace: {model_path}")
                with _download_lock:
                    _active_downloads[model_path] = "complete"
                _upload_to_s3_async(s3, bucket, model_path)
                continue

            logger.warning(f"Could not download: {model_path}")
            with _download_lock:
                _active_downloads[model_path] = "failed"

        except Exception as e:
            logger.error(f"Error downloading {model_path}: {e}")
            with _download_lock:
                _active_downloads[model_path] = f"error: {str(e)}"

    with _download_lock:
        for model_path in list(_active_downloads.keys()):
            if _active_downloads.get(model_path) == "complete":
                del _active_downloads[model_path]


def _try_download_from_s3(s3, bucket: str, model_path: str) -> bool:
    """Try to download model from S3 bucket."""
    local_path = resolver.get_local_path(model_path)
    if not local_path:
        return False

    try:
        s3.head_object(Bucket=bucket, Key=model_path)
    except Exception:
        return False

    os.makedirs(os.path.dirname(local_path), exist_ok=True)
    temp_path = local_path + ".downloading"
    try:
        logger.info(f"Downloading from S3: s3://{bucket}/{model_path}")
        s3.download_file(bucket, model_path, temp_path)
        os.rename(temp_path, local_path)
        return True
    except Exception as e:
        logger.error(f"S3 download failed for {model_path}: {e}")
        if os.path.exists(temp_path):
            os.remove(temp_path)
        return False


def _try_download_from_huggingface(model_path: str) -> bool:
    """Download model directly from HuggingFace if not in S3."""
    import subprocess

    entry = resolver.catalog.get(model_path)
    if not entry or "url" not in entry:
        return False

    local_path = resolver.get_local_path(model_path)
    if not local_path:
        return False

    os.makedirs(os.path.dirname(local_path), exist_ok=True)
    temp_path = local_path + ".downloading"
    url = entry["url"]

    try:
        logger.info(f"Downloading from HuggingFace: {model_path}")
        result = subprocess.run(
            ["curl", "-L", "--retry", "3", "--retry-delay", "5",
             "--connect-timeout", "30", "-o", temp_path, url],
            capture_output=True, timeout=3600,
        )
        if result.returncode == 0 and os.path.exists(temp_path) and os.path.getsize(temp_path) > 1000:
            os.rename(temp_path, local_path)
            return True
        if os.path.exists(temp_path):
            os.remove(temp_path)
        return False
    except Exception as e:
        logger.error(f"HuggingFace download failed for {model_path}: {e}")
        if os.path.exists(temp_path):
            os.remove(temp_path)
        return False


def _upload_to_s3_async(s3, bucket: str, model_path: str):
    """Upload downloaded model to S3 in background for future use and node sync."""
    def _upload():
        local_path = resolver.get_local_path(model_path)
        if not local_path or not os.path.exists(local_path):
            return
        try:
            s3.upload_file(local_path, bucket, model_path)
            logger.info(f"Uploaded to S3: {model_path}")
        except Exception as e:
            logger.warning(f"S3 upload failed for {model_path}: {e}")

    thread = threading.Thread(target=_upload, daemon=True)
    thread.start()
