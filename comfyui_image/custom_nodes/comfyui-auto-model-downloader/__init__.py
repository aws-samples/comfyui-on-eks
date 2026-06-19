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


# Patch output directory to use local disk instead of S3 FUSE mount.
# S3 Mountpoint doesn't support random-access writes (seek), which video encoding
# requires. We write to local disk and upload to S3 in the background.
_LOCAL_OUTPUT_DIR = "/tmp/comfyui-output"
_OUTPUT_BUCKET = None

def _get_output_bucket() -> str:
    global _OUTPUT_BUCKET
    if _OUTPUT_BUCKET is None:
        import boto3
        region = os.environ.get("AWS_DEFAULT_REGION", "us-west-2")
        try:
            account_id = boto3.client("sts").get_caller_identity()["Account"]
        except Exception:
            account_id = os.environ.get("AWS_ACCOUNT_ID", "")
        _OUTPUT_BUCKET = f"comfyui-outputs-{account_id}-{region}"
        logger.info("Output bucket: %s", _OUTPUT_BUCKET)
    return _OUTPUT_BUCKET

def _check_s3_output_mount() -> bool:
    """Check if the output directory is an S3 FUSE mount."""
    try:
        with open("/proc/mounts") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 3 and parts[1] == folder_paths.get_output_directory():
                    return "fuse" in parts[2]
    except Exception:
        pass
    return False

if _check_s3_output_mount():
    os.makedirs(_LOCAL_OUTPUT_DIR, exist_ok=True)

    _original_get_output_directory = folder_paths.get_output_directory
    def _patched_get_output_directory():
        return _LOCAL_OUTPUT_DIR
    folder_paths.get_output_directory = _patched_get_output_directory
    folder_paths.output_directory = _LOCAL_OUTPUT_DIR

    _original_get_save_image_path = folder_paths.get_save_image_path
    def _patched_get_save_image_path(filename_prefix, output_dir=None, *args, **kwargs):
        if output_dir is None or output_dir == _original_get_output_directory():
            output_dir = _LOCAL_OUTPUT_DIR
        return _original_get_save_image_path(filename_prefix, output_dir, *args, **kwargs)
    folder_paths.get_save_image_path = _patched_get_save_image_path

    def _s3_upload_worker():
        """Background thread that uploads completed output files to S3."""
        import time
        import boto3
        bucket = _get_output_bucket()
        s3 = boto3.client("s3", region_name=os.environ.get("AWS_DEFAULT_REGION", "us-west-2"))
        uploaded = set()

        while True:
            time.sleep(3)
            try:
                for root, dirs, files in os.walk(_LOCAL_OUTPUT_DIR):
                    for fname in files:
                        if fname.endswith((".downloading", ".tmp")):
                            continue
                        full_path = os.path.join(root, fname)
                        if full_path in uploaded:
                            continue
                        # Skip files still being written (modified in last 2 seconds)
                        try:
                            if time.time() - os.path.getmtime(full_path) < 2:
                                continue
                        except OSError:
                            continue
                        rel_path = os.path.relpath(full_path, _LOCAL_OUTPUT_DIR)
                        try:
                            s3.upload_file(full_path, bucket, rel_path)
                            uploaded.add(full_path)
                            logger.info("Uploaded output to S3: %s", rel_path)
                        except Exception as e:
                            logger.warning("Failed to upload %s: %s", rel_path, e)
            except Exception as e:
                logger.warning("S3 upload worker error: %s", e)

    _upload_thread = threading.Thread(target=_s3_upload_worker, daemon=True)
    _upload_thread.start()
    logger.info("Output redirected to %s (S3 mount detected)", _LOCAL_OUTPUT_DIR)


def _load_all_blueprint_definitions() -> list:
    """Load subgraph definitions from all blueprint JSON files on disk."""
    import glob
    blueprints_dir = os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
        "blueprints"
    )
    blueprints_dir = os.path.normpath(blueprints_dir)
    all_defs = []
    if not os.path.isdir(blueprints_dir):
        return all_defs
    for bp_file in glob.glob(os.path.join(blueprints_dir, "*.json")):
        try:
            with open(bp_file, "r") as f:
                bp = json.load(f)
            for sg in bp.get("definitions", {}).get("subgraphs", []):
                all_defs.append(sg)
        except Exception:
            continue
    return all_defs

_blueprint_defs: list | None = None

def _get_blueprint_defs() -> list:
    global _blueprint_defs
    if _blueprint_defs is None:
        _blueprint_defs = _load_all_blueprint_definitions()
        logger.info("Loaded %d blueprint subgraph definitions from disk", len(_blueprint_defs))
    return _blueprint_defs


def _on_prompt_handler(json_data):
    """Server-side prompt correction for subgraph blueprint model mismatches."""
    prompt = json_data.get("prompt")
    if not prompt:
        return json_data

    extra_data = json_data.get("extra_data", {})
    workflow = extra_data.get("workflow", {})

    # Build map: subgraph node ID -> subgraph UUID from the workflow's node list
    workflow_nodes = workflow.get("nodes", [])
    all_defs = _get_blueprint_defs()
    defs_by_id = {sg.get("id"): sg for sg in all_defs if sg.get("id")}

    # Map outer node ID -> its subgraph definition
    prefix_to_def: dict[str, dict] = {}
    for wf_node in workflow_nodes:
        node_type = wf_node.get("type", "")
        node_id = str(wf_node.get("id", ""))
        if node_type in defs_by_id:
            prefix_to_def[node_id] = defs_by_id[node_type]

    model_nodes = {nid: nd for nid, nd in prompt.items()
                   if nd.get("class_type") in _WIDGET_ORDER}
    if model_nodes:
        logger.info(
            "Prompt handler: %d model loader nodes, %d prefix mappings. "
            "Node IDs: %s, prefixes: %s",
            len(model_nodes), len(prefix_to_def),
            list(model_nodes.keys())[:10],
            list(prefix_to_def.keys())[:5]
        )

    if prefix_to_def:
        _fix_prompt_from_definitions(prompt, prefix_to_def)

    return json_data


_WIDGET_ORDER = {
    "UNETLoader": ["unet_name", "weight_dtype"],
    "CLIPLoader": ["clip_name", "type", "device"],
    "DualCLIPLoader": ["clip_name1", "clip_name2", "type"],
    "VAELoader": ["vae_name"],
    "LoraLoader": ["lora_name", "strength_model", "strength_clip"],
    "LoraLoaderModelOnly": ["lora_name", "strength_model"],
    "CheckpointLoaderSimple": ["ckpt_name"],
}

from .model_resolver import NODE_INPUT_MODEL_FIELDS


def _fix_prompt_from_definitions(prompt: dict, prefix_to_def: dict[str, dict]):
    """Fix prompt values using subgraph definitions as authoritative source.

    Uses the prefix_to_def mapping (outer node ID -> subgraph definition) to
    correctly identify which definition applies to each expanded prompt node.
    Expanded nodes have IDs like "68:10" where "68" is the outer subgraph node ID.
    """
    for node_id, node_data in prompt.items():
        if ":" not in node_id:
            continue
        prefix = node_id.rsplit(":", 1)[0]
        sg_def = prefix_to_def.get(prefix)
        if not sg_def:
            continue

        class_type = node_data.get("class_type", "")
        order = _WIDGET_ORDER.get(class_type)
        if not order:
            continue

        inputs = node_data.get("inputs", {})

        # Find matching definition node by class_type
        def_candidates = [n for n in sg_def.get("nodes", []) if n.get("type") == class_type]
        for def_node in def_candidates:
            widgets_values = def_node.get("widgets_values", [])
            if not widgets_values:
                continue

            for i, field_name in enumerate(order):
                if field_name not in NODE_INPUT_MODEL_FIELDS:
                    continue
                if i >= len(widgets_values):
                    continue
                intended = widgets_values[i]
                if not intended or not isinstance(intended, str):
                    continue
                if not any(intended.endswith(ext) for ext in (".safetensors", ".ckpt", ".pt", ".pth", ".bin")):
                    continue
                current = inputs.get(field_name)
                if current == intended:
                    continue
                if isinstance(current, str):
                    folder_type = NODE_INPUT_MODEL_FIELDS[field_name]
                    intended_key = f"{folder_type}/{intended}"
                    if intended_key in resolver.catalog:
                        logger.info(
                            f"Correcting {class_type} node {node_id}: "
                            f"{field_name} '{current}' -> '{intended}'"
                        )
                        inputs[field_name] = intended


def _fix_prompt_group_mismatches(prompt: dict):
    """Detect model group mismatches using dependency relationships.

    Uses the catalog's 'requires' field to determine which models belong together.
    If a text encoder is a dependency of a specific diffusion model, those must be
    used together. Corrects any model that doesn't match the dependency chain.
    """
    model_refs = []
    for node_id, node_data in prompt.items():
        class_type = node_data.get("class_type", "")
        inputs = node_data.get("inputs", {})
        for field, folder_type in NODE_INPUT_MODEL_FIELDS.items():
            value = inputs.get(field)
            if not value or not isinstance(value, str):
                continue
            model_key = f"{folder_type}/{value}"
            entry = resolver.catalog.get(model_key)
            if entry:
                model_refs.append({
                    "node_id": node_id,
                    "class_type": class_type,
                    "field": field,
                    "value": value,
                    "model_key": model_key,
                    "group": entry.get("group", ""),
                })

    if len(model_refs) < 2:
        return

    groups = set(r["group"] for r in model_refs if r["group"])
    if len(groups) <= 1:
        return

    logger.info("Group mismatch detected: groups=%s, refs=%s",
                groups, [(r["model_key"], r["group"]) for r in model_refs])

    # Determine authoritative group using dependency relationships.
    # Models with 'requires' dependencies are primary; their required models are secondary.
    # The primary model's group wins.
    primary_group = None
    for key, entry in resolver.catalog.items():
        requires = entry.get("requires", [])
        if not requires:
            continue
        req_keys = set(requires)
        prompt_keys = set(r["model_key"] for r in model_refs)
        if req_keys & prompt_keys:
            primary_group = entry.get("group")
            break

    if not primary_group:
        # Fallback: use the group that has the most model refs
        group_counts = {}
        for r in model_refs:
            g = r["group"]
            if g:
                group_counts[g] = group_counts.get(g, 0) + 1
        primary_group = max(group_counts, key=group_counts.get)

    for ref in model_refs:
        if ref["group"] == primary_group or ref["group"] == "":
            continue

        folder_type = NODE_INPUT_MODEL_FIELDS[ref["field"]]
        correct_model = None
        # Find the correct model: prefer one that is a dependency of the primary model
        for key, entry in resolver.catalog.items():
            if entry.get("group") != primary_group:
                continue
            if not key.startswith(f"{folder_type}/"):
                continue
            correct_model = key.split("/", 1)[1]
            break

        if correct_model and correct_model != ref["value"]:
            node_data = prompt[ref["node_id"]]
            logger.info(
                f"Group mismatch fix: {ref['class_type']} node {ref['node_id']}: "
                f"{ref['field']} '{ref['value']}' -> '{correct_model}' "
                f"(group {ref['group']} -> {primary_group})"
            )
            node_data["inputs"][ref["field"]] = correct_model


PromptServer.instance.add_on_prompt_handler(_on_prompt_handler)


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
    if not url.startswith("https://"):
        logger.error(f"Refusing non-HTTPS download URL for {model_path}: {url}")
        return False

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
