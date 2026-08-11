from .utils import get_bedrock_client

MODELS = [
    "us.amazon.nova-lite-v1:0",
    "us.amazon.nova-pro-v1:0",
    "us.amazon.nova-micro-v1:0",
    "us.anthropic.claude-opus-4-7",
    "us.anthropic.claude-sonnet-4-6",
    "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "us.deepseek.r1-v1:0",
    "us.meta.llama4-scout-17b-instruct-v1:0",
    "us.meta.llama4-maverick-17b-instruct-v1:0",
    "us.meta.llama3-3-70b-instruct-v1:0",
    "mistral.mistral-large-3-675b-instruct",
    "qwen.qwen3-235b-a22b-2507-v1:0",
    "qwen.qwen3-32b-v1:0",
    "qwen.qwen3-next-80b-a3b",
    "qwen.qwen3-coder-480b-a35b-v1:0",
]


class BedrockConverseText:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "prompt": ("STRING", {"multiline": True, "default": ""}),
                "model_id": (MODELS, {"default": MODELS[0]}),
                "max_tokens": ("INT", {"default": 1024, "min": 1, "max": 8192}),
                "temperature": ("FLOAT", {"default": 0.7, "min": 0.0, "max": 1.0, "step": 0.05}),
                "top_p": ("FLOAT", {"default": 0.9, "min": 0.0, "max": 1.0, "step": 0.05}),
            },
            "optional": {
                "system_prompt": ("STRING", {"multiline": True, "default": ""}),
            },
        }

    RETURN_TYPES = ("STRING",)
    RETURN_NAMES = ("text",)
    FUNCTION = "generate"
    CATEGORY = "Bedrock"

    def generate(self, prompt, model_id, max_tokens, temperature, top_p, system_prompt=""):
        client = get_bedrock_client()
        messages = [{"role": "user", "content": [{"text": prompt}]}]
        kwargs = {
            "modelId": model_id,
            "messages": messages,
            "inferenceConfig": {
                "maxTokens": max_tokens,
                "temperature": temperature,
                "topP": top_p,
            },
        }
        if system_prompt:
            kwargs["system"] = [{"text": system_prompt}]

        response = client.converse(**kwargs)
        output_text = response["output"]["message"]["content"][0]["text"]
        return (output_text,)


NODE_CLASS_MAPPINGS = {
    "BedrockConverseText": BedrockConverseText,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "BedrockConverseText": "Bedrock Text (Converse)",
}
