import base64
from .utils import get_bedrock_client, tensor_to_bytes

VISION_MODELS = [
    "us.amazon.nova-lite-v1:0",
    "us.amazon.nova-pro-v1:0",
    "us.anthropic.claude-opus-4-7",
    "us.anthropic.claude-sonnet-4-6",
    "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "us.meta.llama4-scout-17b-instruct-v1:0",
    "us.meta.llama4-maverick-17b-instruct-v1:0",
    "us.mistral.pixtral-large-2502-v1:0",
    "mistral.mistral-large-3-675b-instruct",
    "google.gemma-3-27b-it",
    "google.gemma-3-12b-it",
    "qwen.qwen3-vl-235b-a22b",
]


class BedrockConverseVision:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "image": ("IMAGE",),
                "prompt": ("STRING", {"multiline": True, "default": "Describe this image in detail."}),
                "model_id": (VISION_MODELS, {"default": VISION_MODELS[0]}),
                "max_tokens": ("INT", {"default": 1024, "min": 1, "max": 8192}),
                "temperature": ("FLOAT", {"default": 0.7, "min": 0.0, "max": 1.0, "step": 0.05}),
            },
            "optional": {
                "system_prompt": ("STRING", {"multiline": True, "default": ""}),
            },
        }

    RETURN_TYPES = ("STRING",)
    RETURN_NAMES = ("text",)
    FUNCTION = "analyze"
    CATEGORY = "Bedrock"

    def analyze(self, image, prompt, model_id, max_tokens, temperature, system_prompt=""):
        client = get_bedrock_client()
        image_bytes = tensor_to_bytes(image, format="PNG", max_dim=1568)

        messages = [
            {
                "role": "user",
                "content": [
                    {"image": {"format": "png", "source": {"bytes": image_bytes}}},
                    {"text": prompt},
                ],
            }
        ]

        kwargs = {
            "modelId": model_id,
            "messages": messages,
            "inferenceConfig": {
                "maxTokens": max_tokens,
                "temperature": temperature,
            },
        }
        if system_prompt:
            kwargs["system"] = [{"text": system_prompt}]

        response = client.converse(**kwargs)
        output_text = response["output"]["message"]["content"][0]["text"]
        return (output_text,)


NODE_CLASS_MAPPINGS = {
    "BedrockConverseVision": BedrockConverseVision,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "BedrockConverseVision": "Bedrock Vision (Converse)",
}
