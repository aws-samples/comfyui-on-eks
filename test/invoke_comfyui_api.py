#!/usr/bin/python3

import requests
import uuid
import json
import urllib.parse
import sys
import random
import time
import threading

SERVER_ADDRESS = "abcdefg123456.cloudfront.net"
HTTPS = True
SHOW_IMAGES = True

# Send prompt request to server and get prompt_id and AWSALB cookie
def queue_prompt(prompt, client_id, server_address):
    p = {"prompt": prompt, "client_id": client_id}
    data = json.dumps(p).encode('utf-8')
    if HTTPS:
        response = requests.post("https://{}/prompt".format(server_address), data=data)
    else:
        response = requests.post("http://{}/prompt".format(server_address), data=data)
    aws_alb_cookie = response.headers['Set-Cookie'].split(';')[0]
    prompt_id = response.json()['prompt_id']
    return prompt_id, aws_alb_cookie

def get_image(filename, subfolder, folder_type, server_address, aws_alb_cookie):
    data = {"filename": filename, "subfolder": subfolder, "type": folder_type}
    url_values = urllib.parse.urlencode(data)
    if HTTPS:
        response = requests.get("https://{}/view?{}".format(server_address, url_values), headers={"Cookie": aws_alb_cookie})
    else:
        response = requests.get("http://{}/view?{}".format(server_address, url_values), headers={"Cookie": aws_alb_cookie})
    return response.content

def get_history(prompt_id, server_address, aws_alb_cookie):
    if HTTPS:
        response = requests.get("https://{}/history/{}".format(server_address, prompt_id), headers={"Cookie": aws_alb_cookie})
    else:
        response = requests.get("http://{}/history/{}".format(server_address, prompt_id), headers={"Cookie": aws_alb_cookie})
    return response.json()

def get_images(prompt, client_id, server_address):
    prompt_id, aws_alb_cookie = queue_prompt(prompt, client_id, server_address)
    output_images = {}

    print("Generation started.")
    while True:
        history = get_history(prompt_id, server_address, aws_alb_cookie)
        if len(history) == 0:
            print("Generation not ready, sleep 1s ...")
            time.sleep(1)
            continue
        else:
            print("Generation finished.")
            break

    #history = get_history(prompt_id, server_address, aws_alb_cookie)[prompt_id]
    history = history[prompt_id]
    for o in history['outputs']:
        for node_id in history['outputs']:
            node_output = history['outputs'][node_id]
            if 'images' in node_output:
                images_output = []
                for image in node_output['images']:
                    image_data = get_image(image['filename'], image['subfolder'], image['type'], server_address, aws_alb_cookie)
                    images_output.append(image_data)
            output_images[node_id] = images_output
    return output_images, prompt_id

def random_seed(prompt):
    for node in prompt:
        if 'inputs' in prompt[node]:
            if 'seed' in prompt[node]['inputs']:
                prompt[node]['inputs']['seed'] = random.randint(0, sys.maxsize)
            if 'noise_seed' in prompt[node]['inputs']:
                prompt[node]['inputs']['noise_seed'] = random.randint(0, sys.maxsize)
    return prompt

def single_inference(server_address, request_api_json):
    start = time.time()
    client_id = str(uuid.uuid4())
    with open(request_api_json, "r") as f:
        prompt = json.load(f)
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
    print(f"CKPT: {prompt['4']['inputs']['ckpt_name']}.")
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
