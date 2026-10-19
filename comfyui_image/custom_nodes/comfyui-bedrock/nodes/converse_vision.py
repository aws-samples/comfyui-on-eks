import base64
from .utils import get_bedrock_client, tensor_to_bytes, invoke_converse

VISION_MODELS = [
    # Latest Claude line (5.5), multimodal — default. Amazon Nova models removed (Nova line
    # being deprecated by AWS). Claude 5.x rejects temperature/topP, so analyze() omits them
    # at their defaults.
    "us.anthropic.claude-haiku-5-5",
    "us.anthropic.claude-sonnet-5-5",
    "us.anthropic.claude-opus-5-5",
    # Open-weight vision models:
    "us.meta.llama4-scout-17b-instruct-v1:0",
    "us.meta.llama4-maverick-17b-instruct-v1:0",
    "us.mistral.pixtral-large-2502-v1:0",
    "google.gemma-3-27b-it",
    "google.gemma-3-12b-it",
    "qwen.qwen3-vl-235b-a22b",
    # Amazon Nova removed — the Nova line is being deprecated by AWS (Nova Premier already
    # EOL; Canvas/Reel removed earlier). Use the non-Nova vision models above instead.
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

        inference_config = {"maxTokens": max_tokens}
        # Claude 5.x rejects `temperature` ("deprecated for this model"); send it only
        # when the user changed it from the default so the default path works everywhere.
        if temperature != 0.7:
            inference_config["temperature"] = temperature
        kwargs = {
            "modelId": model_id,
            "messages": messages,
            "inferenceConfig": inference_config,
        }
        if system_prompt:
            kwargs["system"] = [{"text": system_prompt}]

        return (invoke_converse(client, kwargs),)


NODE_CLASS_MAPPINGS = {
    "BedrockConverseVision": BedrockConverseVision,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "BedrockConverseVision": "Bedrock Vision (Converse)",
}
