import json
from .utils import get_bedrock_client, tensor_to_base64, mask_to_base64, base64_to_tensor


class BedrockStabilityInpaint:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "image": ("IMAGE",),
                "mask": ("MASK",),
                "prompt": ("STRING", {"multiline": True, "default": ""}),
                "output_format": (["png", "jpeg", "webp"], {"default": "png"}),
            },
            "optional": {
                "negative_prompt": ("STRING", {"multiline": True, "default": ""}),
                "seed": ("INT", {"default": 0, "min": 0, "max": 4294967294}),
            },
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("image",)
    FUNCTION = "inpaint"
    CATEGORY = "Bedrock/Stability"

    def inpaint(self, image, mask, prompt, output_format, negative_prompt="", seed=0):
        client = get_bedrock_client()
        body = {
            "image": tensor_to_base64(image),
            "mask": mask_to_base64(mask),
            "prompt": prompt,
            "output_format": output_format,
        }
        if negative_prompt:
            body["negative_prompt"] = negative_prompt
        if seed > 0:
            body["seed"] = seed

        response = client.invoke_model(
            modelId="us.stability.stable-image-inpaint-v1:0",
            body=json.dumps(body),
            contentType="application/json",
            accept="application/json",
        )
        result = json.loads(response["body"].read())
        return (base64_to_tensor(result["images"][0]),)


class BedrockStabilityRemoveBackground:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "image": ("IMAGE",),
                "output_format": (["png", "webp"], {"default": "png"}),
            },
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("image",)
    FUNCTION = "remove_bg"
    CATEGORY = "Bedrock/Stability"

    def remove_bg(self, image, output_format):
        client = get_bedrock_client()
        body = {
            "image": tensor_to_base64(image),
            "output_format": output_format,
        }
        response = client.invoke_model(
            modelId="us.stability.stable-image-remove-background-v1:0",
            body=json.dumps(body),
            contentType="application/json",
            accept="application/json",
        )
        result = json.loads(response["body"].read())
        return (base64_to_tensor(result["images"][0]),)


class BedrockStabilityUpscale:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "image": ("IMAGE",),
                "mode": (["fast", "conservative", "creative"], {"default": "fast"}),
                "output_format": (["png", "jpeg", "webp"], {"default": "png"}),
            },
            "optional": {
                "prompt": ("STRING", {"multiline": True, "default": ""}),
                "creativity": ("FLOAT", {"default": 0.3, "min": 0.1, "max": 0.5, "step": 0.05}),
            },
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("image",)
    FUNCTION = "upscale"
    CATEGORY = "Bedrock/Stability"

    def upscale(self, image, mode, output_format, prompt="", creativity=0.3):
        client = get_bedrock_client()
        model_map = {
            "fast": "us.stability.stable-fast-upscale-v1:0",
            "conservative": "us.stability.stable-conservative-upscale-v1:0",
            "creative": "us.stability.stable-creative-upscale-v1:0",
        }
        body = {
            "image": tensor_to_base64(image),
            "output_format": output_format,
        }
        if prompt:
            body["prompt"] = prompt
        if mode in ("creative", "conservative"):
            body["creativity"] = creativity

        response = client.invoke_model(
            modelId=model_map[mode],
            body=json.dumps(body),
            contentType="application/json",
            accept="application/json",
        )
        result = json.loads(response["body"].read())
        return (base64_to_tensor(result["images"][0]),)


class BedrockStabilityControlStructure:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "image": ("IMAGE",),
                "prompt": ("STRING", {"multiline": True, "default": ""}),
                "control_mode": (["structure", "sketch"], {"default": "structure"}),
                "control_strength": ("FLOAT", {"default": 0.7, "min": 0.0, "max": 1.0, "step": 0.05}),
                "output_format": (["png", "jpeg", "webp"], {"default": "png"}),
            },
            "optional": {
                "negative_prompt": ("STRING", {"multiline": True, "default": ""}),
                "seed": ("INT", {"default": 0, "min": 0, "max": 4294967294}),
            },
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("image",)
    FUNCTION = "generate"
    CATEGORY = "Bedrock/Stability"

    def generate(self, image, prompt, control_mode, control_strength, output_format, negative_prompt="", seed=0):
        client = get_bedrock_client()
        model_map = {
            "structure": "us.stability.stable-image-control-structure-v1:0",
            "sketch": "us.stability.stable-image-control-sketch-v1:0",
        }
        body = {
            "image": tensor_to_base64(image),
            "prompt": prompt,
            "control_strength": control_strength,
            "output_format": output_format,
        }
        if negative_prompt:
            body["negative_prompt"] = negative_prompt
        if seed > 0:
            body["seed"] = seed

        response = client.invoke_model(
            modelId=model_map[control_mode],
            body=json.dumps(body),
            contentType="application/json",
            accept="application/json",
        )
        result = json.loads(response["body"].read())
        return (base64_to_tensor(result["images"][0]),)


class BedrockStabilitySearchReplace:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "image": ("IMAGE",),
                "prompt": ("STRING", {"multiline": True, "default": ""}),
                "search_prompt": ("STRING", {"multiline": True, "default": ""}),
                "output_format": (["png", "jpeg", "webp"], {"default": "png"}),
            },
            "optional": {
                "negative_prompt": ("STRING", {"multiline": True, "default": ""}),
                "seed": ("INT", {"default": 0, "min": 0, "max": 4294967294}),
            },
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("image",)
    FUNCTION = "search_replace"
    CATEGORY = "Bedrock/Stability"

    def search_replace(self, image, prompt, search_prompt, output_format, negative_prompt="", seed=0):
        client = get_bedrock_client()
        body = {
            "image": tensor_to_base64(image),
            "prompt": prompt,
            "search_prompt": search_prompt,
            "output_format": output_format,
        }
        if negative_prompt:
            body["negative_prompt"] = negative_prompt
        if seed > 0:
            body["seed"] = seed

        response = client.invoke_model(
            modelId="us.stability.stable-image-search-replace-v1:0",
            body=json.dumps(body),
            contentType="application/json",
            accept="application/json",
        )
        result = json.loads(response["body"].read())
        return (base64_to_tensor(result["images"][0]),)


class BedrockStabilityStyleTransfer:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "init_image": ("IMAGE",),
                "style_image": ("IMAGE",),
                "output_format": (["png", "jpeg", "webp"], {"default": "png"}),
            },
            "optional": {
                "prompt": ("STRING", {"multiline": True, "default": ""}),
                "negative_prompt": ("STRING", {"multiline": True, "default": ""}),
                "seed": ("INT", {"default": 0, "min": 0, "max": 4294967294}),
                "style_strength": ("FLOAT", {"default": 1.0, "min": 0.0, "max": 1.0, "step": 0.05}),
                "composition_fidelity": ("FLOAT", {"default": 0.9, "min": 0.0, "max": 1.0, "step": 0.05}),
            },
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("image",)
    FUNCTION = "transfer"
    CATEGORY = "Bedrock/Stability"

    def transfer(self, init_image, style_image, output_format, prompt="", negative_prompt="", seed=0, style_strength=1.0, composition_fidelity=0.9):
        client = get_bedrock_client()
        body = {
            "init_image": tensor_to_base64(init_image),
            "style_image": tensor_to_base64(style_image),
            "output_format": output_format,
        }
        if prompt:
            body["prompt"] = prompt
        if negative_prompt:
            body["negative_prompt"] = negative_prompt
        if seed > 0:
            body["seed"] = seed
        if style_strength != 1.0:
            body["style_strength"] = style_strength
        if composition_fidelity != 0.9:
            body["composition_fidelity"] = composition_fidelity

        response = client.invoke_model(
            modelId="us.stability.stable-style-transfer-v1:0",
            body=json.dumps(body),
            contentType="application/json",
            accept="application/json",
        )
        result = json.loads(response["body"].read())
        return (base64_to_tensor(result["images"][0]),)


class BedrockStabilityStyleGuide:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "image": ("IMAGE",),
                "prompt": ("STRING", {"multiline": True, "default": ""}),
                "output_format": (["png", "jpeg", "webp"], {"default": "png"}),
            },
            "optional": {
                "negative_prompt": ("STRING", {"multiline": True, "default": ""}),
                "seed": ("INT", {"default": 0, "min": 0, "max": 4294967294}),
                "fidelity": ("FLOAT", {"default": 0.5, "min": 0.0, "max": 1.0, "step": 0.05}),
                "aspect_ratio": (["1:1", "16:9", "21:9", "2:3", "3:2", "4:5", "5:4", "9:16", "9:21"], {"default": "1:1"}),
            },
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("image",)
    FUNCTION = "guide"
    CATEGORY = "Bedrock/Stability"

    def guide(self, image, prompt, output_format, negative_prompt="", seed=0, fidelity=0.5, aspect_ratio="1:1"):
        client = get_bedrock_client()
        body = {
            "image": tensor_to_base64(image),
            "prompt": prompt,
            "output_format": output_format,
        }
        if negative_prompt:
            body["negative_prompt"] = negative_prompt
        if seed > 0:
            body["seed"] = seed
        if fidelity != 0.5:
            body["fidelity"] = fidelity
        if aspect_ratio != "1:1":
            body["aspect_ratio"] = aspect_ratio

        response = client.invoke_model(
            modelId="us.stability.stable-image-style-guide-v1:0",
            body=json.dumps(body),
            contentType="application/json",
            accept="application/json",
        )
        result = json.loads(response["body"].read())
        return (base64_to_tensor(result["images"][0]),)


NODE_CLASS_MAPPINGS = {
    "BedrockStabilityInpaint": BedrockStabilityInpaint,
    "BedrockStabilityRemoveBackground": BedrockStabilityRemoveBackground,
    "BedrockStabilityUpscale": BedrockStabilityUpscale,
    "BedrockStabilityControlStructure": BedrockStabilityControlStructure,
    "BedrockStabilitySearchReplace": BedrockStabilitySearchReplace,
    "BedrockStabilityStyleTransfer": BedrockStabilityStyleTransfer,
    "BedrockStabilityStyleGuide": BedrockStabilityStyleGuide,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "BedrockStabilityInpaint": "Bedrock Stability Inpaint",
    "BedrockStabilityRemoveBackground": "Bedrock Stability Remove Background",
    "BedrockStabilityUpscale": "Bedrock Stability Upscale",
    "BedrockStabilityControlStructure": "Bedrock Stability Control (Structure/Sketch)",
    "BedrockStabilitySearchReplace": "Bedrock Stability Search & Replace",
    "BedrockStabilityStyleTransfer": "Bedrock Stability Style Transfer",
    "BedrockStabilityStyleGuide": "Bedrock Stability Style Guide",
}
