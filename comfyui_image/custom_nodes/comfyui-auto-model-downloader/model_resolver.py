import json
import os
import logging

import folder_paths

logger = logging.getLogger("AutoModelDownloader")

MODEL_DIR_MAPPING = {
    "checkpoints": "checkpoints",
    "clip": "clip",
    "clip_vision": "clip_vision",
    "controlnet": "controlnet",
    "diffusion_models": "diffusion_models",
    "diffusers": "diffusers",
    "embeddings": "embeddings",
    "gligen": "gligen",
    "hypernetworks": "hypernetworks",
    "loras": "loras",
    "style_models": "style_models",
    "text_encoders": "text_encoders",
    "unet": "unet",
    "upscale_models": "upscale_models",
    "vae": "vae",
    "vae_approx": "vae_approx",
    "model_patches": "custom_nodes",
    "latent_upscale_models": "checkpoints",
}

NODE_INPUT_MODEL_FIELDS = {
    "ckpt_name": "checkpoints",
    "unet_name": "diffusion_models",
    "clip_name": "text_encoders",
    "clip_name1": "text_encoders",
    "clip_name2": "text_encoders",
    "clip_name3": "text_encoders",
    "vae_name": "vae",
    "lora_name": "loras",
    "control_net_name": "controlnet",
    "model_name": "upscale_models",
    "style_model_name": "style_models",
    "gligen_name": "gligen",
    "clip_vision": "clip_vision",
}


BEDROCK_ALTERNATIVES = {
    "checkpoints/v1-5-pruned-emaonly-fp16.safetensors": {
        "node": "BedrockStabilityGenerate",
        "capability": "text-to-image",
        "description": "Stability SD3.5 Large via Bedrock (no download needed)",
    },
    "checkpoints/sd_xl_base_1.0.safetensors": {
        "node": "BedrockStabilityGenerate",
        "capability": "text-to-image",
        "description": "Stability SD3.5 Large / Image Ultra via Bedrock (no download needed)",
    },
    "checkpoints/sd_xl_refiner_1.0.safetensors": {
        "node": "BedrockStabilityGenerate",
        "capability": "text-to-image",
        "description": "Stability Image Ultra via Bedrock (no download needed)",
    },
    "checkpoints/DreamShaper_8_pruned.safetensors": {
        "node": "BedrockStabilityGenerate",
        "capability": "text-to-image",
        "description": "Stability SD3.5 Large via Bedrock (no download needed)",
    },
    "checkpoints/512-inpainting-ema.safetensors": {
        "node": "BedrockStabilityInpaint",
        "capability": "inpainting",
        "description": "Stability Inpaint via Bedrock (no download needed)",
    },
    "upscale_models/RealESRGAN_x4plus.safetensors": {
        "node": "BedrockStabilityUpscale",
        "capability": "upscale",
        "description": "Stability Upscale (fast/conservative/creative) via Bedrock (no download needed)",
    },
    "checkpoints/svd.safetensors": {
        "node": "BedrockNovaReel",
        "capability": "video-generation",
        "description": "Nova Reel or Luma Ray v2 via Bedrock (no download needed)",
    },
    "diffusion_models/z_image_turbo_bf16.safetensors": {
        "node": "BedrockStabilityGenerate",
        "capability": "text-to-image",
        "description": "Stability Image Core via Bedrock — fast text-to-image (no download needed)",
    },
    "diffusion_models/flux1-dev-fp8.safetensors": {
        "node": "BedrockStabilityGenerate",
        "capability": "text-to-image",
        "description": "Stability SD3.5 Large via Bedrock (no download needed)",
    },
}


class ModelResolver:
    _FOLDER_FALLBACKS = {
        "checkpoints": ["diffusion_models"],
        "diffusion_models": ["checkpoints"],
    }

    def __init__(self):
        catalog_path = os.path.join(os.path.dirname(__file__), "model_catalog.json")
        with open(catalog_path, "r") as f:
            self.catalog: dict = json.load(f)

    def _resolve_catalog_key(self, model_key: str, filename: str) -> str:
        """Return the canonical catalog key, trying alternate folder prefixes if needed."""
        if model_key in self.catalog:
            return model_key
        folder_type = model_key.split("/", 1)[0]
        for alt_folder in self._FOLDER_FALLBACKS.get(folder_type, []):
            alt_key = f"{alt_folder}/{filename}"
            if alt_key in self.catalog:
                return alt_key
        return model_key

    def find_missing_models(self, prompt: dict) -> list[str]:
        """Scan a ComfyUI prompt dict for model references and return missing ones."""
        missing = []
        for node_id, node_data in prompt.items():
            inputs = node_data.get("inputs", {})
            class_type = node_data.get("class_type", "")

            for field, folder_type in NODE_INPUT_MODEL_FIELDS.items():
                if field not in inputs:
                    continue
                value = inputs[field]
                if not isinstance(value, str) or not value:
                    continue
                if value == "put_here" or value.startswith("["):
                    continue

                model_key = f"{folder_type}/{value}"
                resolved_key = self._resolve_catalog_key(model_key, value)
                if resolved_key in self.catalog and not self.is_model_available(resolved_key):
                    missing.append(resolved_key)
                elif resolved_key not in self.catalog:
                    logger.warning(
                        "Model '%s' is not in the auto-downloader catalog. "
                        "Workflow may fail if the file is not already on disk.",
                        model_key
                    )

        return list(set(missing))

    def resolve_dependencies(self, models: list[str]) -> list[str]:
        """Expand model list with all required dependencies."""
        all_models = set(models)
        to_process = list(models)

        while to_process:
            current = to_process.pop()
            entry = self.catalog.get(current, {})
            for dep in entry.get("requires", []):
                if dep not in all_models:
                    all_models.add(dep)
                    to_process.append(dep)

        return list(all_models)

    def is_model_available(self, model_key: str) -> bool:
        """Check if a model file exists on the local filesystem."""
        local_path = self.get_local_path(model_key)
        if local_path and os.path.exists(local_path):
            return True
        return False

    def get_local_path(self, model_key: str) -> str | None:
        """Get the expected local filesystem path for a model key like 'checkpoints/model.safetensors'."""
        parts = model_key.split("/", 1)
        if len(parts) != 2:
            return None

        folder_type, filename = parts
        mapped_type = MODEL_DIR_MAPPING.get(folder_type, folder_type)

        try:
            full_path = folder_paths.get_full_path(mapped_type, filename)
            if full_path:
                return full_path
        except Exception:
            pass

        paths = folder_paths.get_folder_paths(mapped_type)
        if paths:
            return os.path.join(paths[0], filename)

        base = os.path.join(folder_paths.models_dir, folder_type)
        return os.path.join(base, filename)

    def get_bedrock_alternatives(self, missing_models: list[str]) -> dict[str, dict]:
        """Return Bedrock alternatives for missing models."""
        alternatives = {}
        for model_key in missing_models:
            if model_key in BEDROCK_ALTERNATIVES:
                alternatives[model_key] = BEDROCK_ALTERNATIVES[model_key]
        return alternatives
