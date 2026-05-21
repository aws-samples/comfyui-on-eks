import json
from .utils import get_bedrock_client, tensor_to_base64, mask_to_base64, base64_to_tensor

TASK_TYPES = ["TEXT_IMAGE", "INPAINTING", "OUTPAINTING", "IMAGE_VARIATION", "BACKGROUND_REMOVAL", "COLOR_GUIDED_GENERATION"]


class BedrockNovaCanvas:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "prompt": ("STRING", {"multiline": True, "default": ""}),
                "task_type": (TASK_TYPES, {"default": "TEXT_IMAGE"}),
                "width": ("INT", {"default": 1024, "min": 320, "max": 4096, "step": 16}),
                "height": ("INT", {"default": 1024, "min": 320, "max": 4096, "step": 16}),
                "cfg_scale": ("FLOAT", {"default": 8.0, "min": 1.1, "max": 10.0, "step": 0.1}),
                "seed": ("INT", {"default": 0, "min": 0, "max": 858993459}),
            },
            "optional": {
                "image": ("IMAGE",),
                "mask": ("MASK",),
                "negative_prompt": ("STRING", {"multiline": True, "default": ""}),
            },
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("image",)
    FUNCTION = "generate"
    CATEGORY = "Bedrock/Nova Canvas"

    def generate(self, prompt, task_type, width, height, cfg_scale, seed, image=None, mask=None, negative_prompt=""):
        client = get_bedrock_client()

        image_gen_config = {
            "width": width,
            "height": height,
            "cfgScale": cfg_scale,
            "seed": seed,
            "numberOfImages": 1,
        }

        if task_type == "TEXT_IMAGE":
            body = {
                "taskType": "TEXT_IMAGE",
                "textToImageParams": {"text": prompt},
                "imageGenerationConfig": image_gen_config,
            }
            if negative_prompt:
                body["textToImageParams"]["negativeText"] = negative_prompt
            if image is not None:
                body["textToImageParams"]["conditionImage"] = tensor_to_base64(image)

        elif task_type == "INPAINTING":
            body = {
                "taskType": "INPAINTING",
                "inPaintingParams": {
                    "text": prompt,
                    "image": tensor_to_base64(image),
                    "maskImage": mask_to_base64(mask),
                },
                "imageGenerationConfig": image_gen_config,
            }
            if negative_prompt:
                body["inPaintingParams"]["negativeText"] = negative_prompt

        elif task_type == "OUTPAINTING":
            body = {
                "taskType": "OUTPAINTING",
                "outPaintingParams": {
                    "text": prompt,
                    "image": tensor_to_base64(image),
                    "maskImage": mask_to_base64(mask),
                    "outPaintingMode": "DEFAULT",
                },
                "imageGenerationConfig": image_gen_config,
            }

        elif task_type == "IMAGE_VARIATION":
            body = {
                "taskType": "IMAGE_VARIATION",
                "imageVariationParams": {
                    "text": prompt,
                    "images": [tensor_to_base64(image)],
                },
                "imageGenerationConfig": image_gen_config,
            }
            if negative_prompt:
                body["imageVariationParams"]["negativeText"] = negative_prompt

        elif task_type == "BACKGROUND_REMOVAL":
            body = {
                "taskType": "BACKGROUND_REMOVAL",
                "backgroundRemovalParams": {
                    "image": tensor_to_base64(image),
                },
            }

        elif task_type == "COLOR_GUIDED_GENERATION":
            body = {
                "taskType": "COLOR_GUIDED_GENERATION",
                "colorGuidedGenerationParams": {
                    "text": prompt,
                    "referenceImage": tensor_to_base64(image),
                },
                "imageGenerationConfig": image_gen_config,
            }
            if negative_prompt:
                body["colorGuidedGenerationParams"]["negativeText"] = negative_prompt

        response = client.invoke_model(
            modelId="amazon.nova-canvas-v1:0",
            body=json.dumps(body),
            contentType="application/json",
            accept="application/json",
        )

        result = json.loads(response["body"].read())
        output_b64 = result["images"][0]
        return (base64_to_tensor(output_b64),)


NODE_CLASS_MAPPINGS = {
    "BedrockNovaCanvas": BedrockNovaCanvas,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "BedrockNovaCanvas": "Bedrock Nova Canvas",
}
