#!/usr/bin/python3

import requests
import uuid
import json
import urllib.parse
import sys
import random
import time
import threading
import comfyui_api_utils

SERVER_ADDRESS = "https://abcdefg123456.cloudfront.net"
SHOW_IMAGES = False

# Check if the image is ready, if not, upload it
def review_prompt(prompt):
    for node in prompt:
        if 'inputs' in prompt[node] and 'image' in prompt[node]['inputs'] and isinstance(prompt[node]['inputs']['image'], str):
            filename = prompt[node]['inputs']['image']
            if not comfyui_api_utils.check_input_image_ready(filename, SERVER_ADDRESS):
                # image need to be placed at the same dir
                comfyui_api_utils.upload_image(filename, SERVER_ADDRESS)

# Set random seed for the prompt
def random_seed(prompt):
    for node in prompt:
        if 'inputs' in prompt[node]:
            if 'seed' in prompt[node]['inputs']:
                prompt[node]['inputs']['seed'] = random.randint(0, sys.maxsize)
            if 'noise_seed' in prompt[node]['inputs']:
                prompt[node]['inputs']['noise_seed'] = random.randint(0, sys.maxsize)
    return prompt

# Get the ComfyUI output images
def get_images(prompt, client_id, server_address):
    prompt_id, aws_alb_cookie = comfyui_api_utils.queue_prompt(prompt, client_id, server_address)
    output_images = {}

    print("Generation started.")
    while True:
        history = comfyui_api_utils.get_history(prompt_id, server_address, aws_alb_cookie)
        if len(history) == 0:
            print("Generation not ready, sleep 1s ...")
            time.sleep(1)
            continue
        else:
            print("Generation finished.")
            break

    history = history[prompt_id]
    for node_id in history['outputs']:
        node_output = history['outputs'][node_id]
        if 'images' in node_output and node_output['images'][0]['type'] == 'output':
            images_output = []
            for image in node_output['images']:
                image_data = comfyui_api_utils.get_image(image['filename'], image['subfolder'], image['type'], server_address, aws_alb_cookie)
                images_output.append(image_data)
            output_images[node_id] = images_output
    return output_images, prompt_id

# Invoke the ComfyUI API with one workflow
def single_inference(server_address, request_api_json):
    start = time.time()
    client_id = str(uuid.uuid4())
    with open(request_api_json, "r") as f:
        prompt = json.load(f)
    review_prompt(prompt)
    prompt = random_seed(prompt)
    images, prompt_id = get_images(prompt, client_id, server_address)
    if SHOW_IMAGES:
        for node_id in images:
            for image_data in images[node_id]:
                from PIL import Image
                import io
                image = Image.open(io.BytesIO(image_data))
                image.show()
    end = time.time()
    timespent = round((end - start), 2)
    print("Inference finished.")
    print(f"ClientID: {client_id}.")
    print(f"PromptID: {prompt_id}.")
    print(f"Num of images: {len(images)}.")
    print(f"Time spent: {timespent}s.")
    print("------")

if __name__ == "__main__":
    # Get the file path from the command line
    if len(sys.argv) == 2:
        REQUEST_API_JSON = sys.argv[1]
    else:
        print("Usage: python3 invoke_comfyui_api.py <request_api_json>")
        sys.exit(1)
    single_inference(SERVER_ADDRESS, REQUEST_API_JSON)
