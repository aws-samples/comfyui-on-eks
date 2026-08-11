import json
from .utils import get_bedrock_client, tensor_to_base64, mask_to_base64, base64_to_tensor

GENERATE_MODELS = [
    ("SD 3.5 Large", "us.stability.sd3-5-large-v1:0"),
    ("Stable Image Core", "us.stability.stable-image-core-v1:1"),
    ("Stable Image Ultra", "us.stability.sd3-ultra-v1:1"),
]


class BedrockStabilityGenerate:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "prompt": ("STRING", {"multiline": True, "default": ""}),
                "model": ([m[0] for m in GENERATE_MODELS], {"default": GENERATE_MODELS[0][0]}),
                "aspect_ratio": (["1:1", "16:9", "21:9", "2:3", "3:2", "4:5", "5:4", "9:16", "9:21"], {"default": "1:1"}),
                "output_format": (["png", "jpeg", "webp"], {"default": "png"}),
            },
            "optional": {
                "negative_prompt": ("STRING", {"multiline": True, "default": ""}),
                "seed": ("INT", {"default": 0, "min": 0, "max": 4294967294}),
                "image": ("IMAGE",),
                "strength": ("FLOAT", {"default": 0.35, "min": 0.0, "max": 1.0, "step": 0.05}),
            },
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("image",)
    FUNCTION = "generate"
    CATEGORY = "Bedrock/Stability"

    def generate(self, prompt, model, aspect_ratio, output_format, negative_prompt="", seed=0, image=None, strength=0.35):
        client = get_bedrock_client()
        model_id = dict(GENERATE_MODELS)[model]

        body = {
            "prompt": prompt,
            "output_format": output_format,
            "aspect_ratio": aspect_ratio,
        }
        if negative_prompt:
            body["negative_prompt"] = negative_prompt
        if seed > 0:
            body["seed"] = seed
        if image is not None:
            body["image"] = tensor_to_base64(image)
            body["strength"] = strength
            body["mode"] = "image-to-image"

        response = client.invoke_model(
            modelId=model_id,
            body=json.dumps(body),
            contentType="application/json",
            accept="application/json",
        )
        result = json.loads(response["body"].read())
        return (base64_to_tensor(result["images"][0]),)


class BedrockStabilityOutpaint:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "image": ("IMAGE",),
                "output_format": (["png", "jpeg", "webp"], {"default": "png"}),
            },
            "optional": {
                "prompt": ("STRING", {"multiline": True, "default": ""}),
                "creativity": ("FLOAT", {"default": 0.5, "min": 0.1, "max": 1.0, "step": 0.05}),
                "seed": ("INT", {"default": 0, "min": 0, "max": 4294967294}),
                "left": ("INT", {"default": 0, "min": 0, "max": 2000}),
                "right": ("INT", {"default": 0, "min": 0, "max": 2000}),
                "up": ("INT", {"default": 0, "min": 0, "max": 2000}),
                "down": ("INT", {"default": 0, "min": 0, "max": 2000}),
            },
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("image",)
    FUNCTION = "outpaint"
    CATEGORY = "Bedrock/Stability"

    def outpaint(self, image, output_format, prompt="", creativity=0.5, seed=0, left=0, right=0, up=0, down=0):
        client = get_bedrock_client()
        body = {
            "image": tensor_to_base64(image),
            "output_format": output_format,
        }
        if prompt:
            body["prompt"] = prompt
        if creativity != 0.5:
            body["creativity"] = creativity
        if seed > 0:
            body["seed"] = seed
        if left > 0:
            body["left"] = left
        if right > 0:
            body["right"] = right
        if up > 0:
            body["up"] = up
        if down > 0:
            body["down"] = down

        response = client.invoke_model(
            modelId="us.stability.stable-outpaint-v1:0",
            body=json.dumps(body),
            contentType="application/json",
            accept="application/json",
        )
        result = json.loads(response["body"].read())
        return (base64_to_tensor(result["images"][0]),)


class BedrockStabilityEraseObject:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "image": ("IMAGE",),
                "mask": ("MASK",),
                "output_format": (["png", "jpeg", "webp"], {"default": "png"}),
            },
            "optional": {
                "seed": ("INT", {"default": 0, "min": 0, "max": 4294967294}),
            },
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("image",)
    FUNCTION = "erase"
    CATEGORY = "Bedrock/Stability"

    def erase(self, image, mask, output_format, seed=0):
        client = get_bedrock_client()
        body = {
            "image": tensor_to_base64(image),
            "mask": mask_to_base64(mask),
            "output_format": output_format,
        }
        if seed > 0:
            body["seed"] = seed

        response = client.invoke_model(
            modelId="us.stability.stable-image-erase-object-v1:0",
            body=json.dumps(body),
            contentType="application/json",
            accept="application/json",
        )
        result = json.loads(response["body"].read())
        return (base64_to_tensor(result["images"][0]),)


class BedrockStabilitySearchRecolor:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "image": ("IMAGE",),
                "prompt": ("STRING", {"multiline": True, "default": ""}),
                "select_prompt": ("STRING", {"multiline": True, "default": ""}),
                "output_format": (["png", "jpeg", "webp"], {"default": "png"}),
            },
            "optional": {
                "negative_prompt": ("STRING", {"multiline": True, "default": ""}),
                "seed": ("INT", {"default": 0, "min": 0, "max": 4294967294}),
            },
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("image",)
    FUNCTION = "recolor"
    CATEGORY = "Bedrock/Stability"

    def recolor(self, image, prompt, select_prompt, output_format, negative_prompt="", seed=0):
        client = get_bedrock_client()
        body = {
            "image": tensor_to_base64(image),
            "prompt": prompt,
            "select_prompt": select_prompt,
            "output_format": output_format,
        }
        if negative_prompt:
            body["negative_prompt"] = negative_prompt
        if seed > 0:
            body["seed"] = seed

        response = client.invoke_model(
            modelId="us.stability.stable-image-search-recolor-v1:0",
            body=json.dumps(body),
            contentType="application/json",
            accept="application/json",
        )
        result = json.loads(response["body"].read())
        return (base64_to_tensor(result["images"][0]),)


NODE_CLASS_MAPPINGS = {
    "BedrockStabilityGenerate": BedrockStabilityGenerate,
    "BedrockStabilityOutpaint": BedrockStabilityOutpaint,
    "BedrockStabilityEraseObject": BedrockStabilityEraseObject,
    "BedrockStabilitySearchRecolor": BedrockStabilitySearchRecolor,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "BedrockStabilityGenerate": "Bedrock Stability Generate (SD3.5/Core/Ultra)",
    "BedrockStabilityOutpaint": "Bedrock Stability Outpaint",
    "BedrockStabilityEraseObject": "Bedrock Stability Erase Object",
    "BedrockStabilitySearchRecolor": "Bedrock Stability Search & Recolor",
}
