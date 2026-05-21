import json
import time
from .utils import get_bedrock_client, tensor_to_base64


class BedrockLumaRay:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "prompt": ("STRING", {"multiline": True, "default": ""}),
                "s3_output_bucket": ("STRING", {"default": ""}),
                "s3_output_prefix": ("STRING", {"default": "luma-ray-output/"}),
                "aspect_ratio": (["16:9", "1:1", "9:16", "4:3", "3:4", "21:9", "9:21"], {"default": "16:9"}),
                "duration_seconds": ("INT", {"default": 5, "min": 5, "max": 9}),
            },
            "optional": {
                "image": ("IMAGE",),
            },
        }

    RETURN_TYPES = ("STRING",)
    RETURN_NAMES = ("s3_video_uri",)
    FUNCTION = "generate_video"
    CATEGORY = "Bedrock/Luma"

    def generate_video(self, prompt, s3_output_bucket, s3_output_prefix, aspect_ratio, duration_seconds, image=None):
        client = get_bedrock_client()

        model_input = {
            "prompt": prompt,
            "aspect_ratio": aspect_ratio,
            "duration": f"{duration_seconds}s",
        }

        if image is not None:
            model_input["image"] = {
                "format": "png",
                "source": {"bytes": tensor_to_base64(image)},
            }

        s3_uri = f"s3://{s3_output_bucket}/{s3_output_prefix}"

        response = client.start_async_invoke(
            modelId="luma.ray-v2:0",
            modelInput=model_input,
            outputDataConfig={"s3OutputDataConfig": {"s3Uri": s3_uri}},
        )

        invocation_arn = response["invocationArn"]

        while True:
            status_response = client.get_async_invoke(invocationArn=invocation_arn)
            status = status_response["status"]

            if status == "Completed":
                output_uri = status_response["outputDataConfig"]["s3OutputDataConfig"]["s3Uri"]
                return (f"{output_uri}output.mp4",)
            elif status in ("Failed", "Expired"):
                failure = status_response.get("failureMessage", "Unknown error")
                raise RuntimeError(f"Luma Ray generation failed: {failure}")

            time.sleep(5)


NODE_CLASS_MAPPINGS = {
    "BedrockLumaRay": BedrockLumaRay,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "BedrockLumaRay": "Bedrock Luma Ray v2 (Video)",
}
