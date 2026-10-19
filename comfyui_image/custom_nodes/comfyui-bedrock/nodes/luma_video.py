import json
import time
from botocore.exceptions import ClientError, BotoCoreError
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

        try:
            response = client.start_async_invoke(
                modelId="luma.ray-v2:0",
                modelInput=model_input,
                outputDataConfig={"s3OutputDataConfig": {"s3Uri": s3_uri}},
            )
        except (ClientError, BotoCoreError) as e:
            raise RuntimeError(f"Luma Ray start_async_invoke failed: {e}") from e

        invocation_arn = response["invocationArn"]

        deadline = time.time() + 900  # 15 min wall-clock cap
        while True:
            if time.time() > deadline:
                raise RuntimeError(
                    f"Luma Ray generation timed out after 15 min (invocationArn={invocation_arn})"
                )
            try:
                status_response = client.get_async_invoke(invocationArn=invocation_arn)
            except (ClientError, BotoCoreError) as e:
                raise RuntimeError(f"Luma Ray get_async_invoke failed: {e}") from e
            status = status_response["status"]

            if status == "Completed":
                output_uri = status_response["outputDataConfig"]["s3OutputDataConfig"]["s3Uri"]
                return (f"{output_uri}output.mp4",)
            elif status in ("Failed", "Expired"):
                failure = status_response.get("failureMessage", "Unknown error")
                raise RuntimeError(f"Luma Ray generation failed: {failure}")
            elif status not in ("InProgress", "Submitted"):
                raise RuntimeError(f"Luma Ray returned unexpected status: {status}")

            time.sleep(5)


NODE_CLASS_MAPPINGS = {
    "BedrockLumaRay": BedrockLumaRay,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "BedrockLumaRay": "Bedrock Luma Ray v2 (Video)",
}
