from .utils import get_bedrock_client, tensor_to_base64, mask_to_base64, invoke_stability_model

# The Bedrock Stability Generate node (text-to-image / image-to-image) was removed:
# Stability AI moved all three Bedrock text-to-image models (SD 3.5 Large, Stable Image
# Core, Stable Image Ultra) to the Bedrock Legacy state on 2026-11-09, and they reach
# end of life on 2027-05-09. For text-to-image, use the local SD 3.5 Large / Medium,
# FLUX or SDXL checkpoints, which the auto-model-downloader fetches from Hugging Face.
# The editing nodes below use separate inference-profile models and are unaffected.


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

        return (invoke_stability_model(client, "us.stability.stable-outpaint-v1:0", body),)


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

        return (invoke_stability_model(client, "us.stability.stable-image-erase-object-v1:0", body),)


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

        return (invoke_stability_model(client, "us.stability.stable-image-search-recolor-v1:0", body),)


NODE_CLASS_MAPPINGS = {
    "BedrockStabilityOutpaint": BedrockStabilityOutpaint,
    "BedrockStabilityEraseObject": BedrockStabilityEraseObject,
    "BedrockStabilitySearchRecolor": BedrockStabilitySearchRecolor,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "BedrockStabilityOutpaint": "Bedrock Stability Outpaint",
    "BedrockStabilityEraseObject": "Bedrock Stability Erase Object",
    "BedrockStabilitySearchRecolor": "Bedrock Stability Search & Recolor",
}
