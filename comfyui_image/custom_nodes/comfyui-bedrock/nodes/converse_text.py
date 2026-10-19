from .utils import get_bedrock_client, invoke_converse

MODELS = [
    # Default is a non-Amazon-Nova model on the latest Claude line (5.5). Nova is being
    # wound down, so it is no longer the default. NOTE: the Claude 5.x family rejects the
    # `temperature`/`topP` knobs ("deprecated for this model"), so generate() only sends
    # them when the user changes them from the defaults — see below.
    "us.anthropic.claude-haiku-5-5",
    "us.anthropic.claude-sonnet-5-5",
    "us.anthropic.claude-opus-5-5",
    # Previous-gen Claude (accept temperature/topP) — kept as options:
    "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "us.anthropic.claude-sonnet-4-6",
    # Meta Llama (open weight):
    "us.meta.llama4-scout-17b-instruct-v1:0",
    "us.meta.llama4-maverick-17b-instruct-v1:0",
    "us.meta.llama3-3-70b-instruct-v1:0",
    # Mistral (open weight):
    "mistral.mistral-large-3-675b-instruct",
    "mistral.ministral-3-14b-instruct",
    "mistral.magistral-small-2509",
    # NVIDIA Nemotron (open weight):
    "nvidia.nemotron-super-3-120b",
    "nvidia.nemotron-nano-9b-v2",
    # DeepSeek + Qwen (open weight):
    "us.deepseek.r1-v1:0",
    "qwen.qwen3-235b-a22b-2507-v1:0",
    "qwen.qwen3-32b-v1:0",
    # Amazon Nova (deprecation in progress — kept for compatibility, not the default):
    "us.amazon.nova-lite-v1:0",
    "us.amazon.nova-pro-v1:0",
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
        inference_config = {"maxTokens": max_tokens}
        # The Claude 5.x family rejects temperature/topP ("deprecated for this model");
        # other models accept them. Send each knob ONLY when the user changed it from the
        # default, so the default path (neither knob) works across every model — including
        # the latest Claude — and advanced users who tune them must pick a compatible model.
        if temperature != 0.7:
            inference_config["temperature"] = temperature
        if top_p != 0.9:
            inference_config["topP"] = top_p
        kwargs = {
            "modelId": model_id,
            "messages": messages,
            "inferenceConfig": inference_config,
        }
        if system_prompt:
            kwargs["system"] = [{"text": system_prompt}]

        return (invoke_converse(client, kwargs),)


NODE_CLASS_MAPPINGS = {
    "BedrockConverseText": BedrockConverseText,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "BedrockConverseText": "Bedrock Text (Converse)",
}
