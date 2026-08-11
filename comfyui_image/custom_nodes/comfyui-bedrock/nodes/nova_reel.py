import json
import time
import boto3
from .utils import get_bedrock_client, tensor_to_base64


class BedrockNovaReel:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "prompt": ("STRING", {"multiline": True, "default": ""}),
                "s3_output_bucket": ("STRING", {"default": ""}),
                "s3_output_prefix": ("STRING", {"default": "nova-reel-output/"}),
                "duration_seconds": ("INT", {"default": 6, "min": 6, "max": 6}),
                "fps": ("INT", {"default": 24, "min": 24, "max": 24}),
                "width": ("INT", {"default": 1280, "min": 1280, "max": 1280}),
                "height": ("INT", {"default": 720, "min": 720, "max": 720}),
                "seed": ("INT", {"default": 0, "min": 0, "max": 2147483647}),
            },
            "optional": {
                "image": ("IMAGE",),
            },
        }

    RETURN_TYPES = ("STRING",)
    RETURN_NAMES = ("s3_video_uri",)
    FUNCTION = "generate_video"
    CATEGORY = "Bedrock/Nova Reel"

    def generate_video(self, prompt, s3_output_bucket, s3_output_prefix, duration_seconds, fps, width, height, seed, image=None):
        client = get_bedrock_client(region="us-east-1")

        model_input = {
            "taskType": "TEXT_VIDEO",
            "textToVideoParams": {"text": prompt},
            "videoGenerationConfig": {
                "durationSeconds": duration_seconds,
                "fps": fps,
                "dimension": f"{width}x{height}",
                "seed": seed,
            },
        }

        if image is not None:
            model_input["textToVideoParams"]["images"] = [
                {"format": "png", "source": {"bytes": tensor_to_base64(image)}}
            ]

        s3_uri = f"s3://{s3_output_bucket}/{s3_output_prefix}"

        response = client.start_async_invoke(
            modelId="amazon.nova-reel-v1:0",
            modelInput=model_input,
            outputDataConfig={"s3OutputDataConfig": {"s3Uri": s3_uri}},
        )

        invocation_arn = response["invocationArn"]

        while True:
            status_response = client.get_async_invoke(invocationArn=invocation_arn)
            status = status_response["status"]

            if status == "Completed":
                output_uri = status_response["outputDataConfig"]["s3OutputDataConfig"]["s3Uri"]
                video_uri = f"{output_uri}output.mp4"
                return (video_uri,)
            elif status in ("Failed", "Expired"):
                failure = status_response.get("failureMessage", "Unknown error")
                raise RuntimeError(f"Nova Reel generation failed: {failure}")

            time.sleep(5)


NODE_CLASS_MAPPINGS = {
    "BedrockNovaReel": BedrockNovaReel,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "BedrockNovaReel": "Bedrock Nova Reel (Video)",
}
