#!/usr/bin/python3

import requests
import json
import os
import urllib
import sys


def _validate_file_path(file_path):
    resolved = os.path.realpath(file_path)
    if not os.path.isfile(resolved):
        raise ValueError(f"File does not exist: {resolved}")
    return resolved


# Send prompt request to server and get prompt_id and AWSALB cookie
def queue_prompt(prompt, client_id, server_address):
    p = {"prompt": prompt, "client_id": client_id}
    data = json.dumps(p).encode('utf-8')
    response = requests.post("{}/prompt".format(server_address), data=data)
    if response.status_code != 200:
        print("Error: status_code={}".format(response.status_code))
        sys.exit(1)
    if 'Set-Cookie' not in response.headers:
        print("No ALB, test directly to EC2.")
        aws_alb_cookie = None
    else:
        aws_alb_cookie = response.headers['Set-Cookie'].split(';')[0]
    prompt_id = response.json()['prompt_id']
    return prompt_id, aws_alb_cookie

# Check if input image is ready
def check_input_image_ready(filename, server_address):
    basename = os.path.basename(filename)
    data = {"filename": basename, "subfolder": "", "type": "input"}
    url_values = urllib.parse.urlencode(data)
    response = requests.get("{}/view?{}".format(server_address, url_values))
    if response.status_code == 200:
        print("Input image {} is ready, skip upload.".format(basename))
        return True
    print("Input image {} not exists, uploading from current directory.".format(basename))
    return False

# Upload image to server, POST to /upload/image/
def upload_image(image_path, server_address):
    validated_path = _validate_file_path(image_path)
    with open(validated_path, "rb") as f:
        files = {"image": f}
        response = requests.post("{}/upload/image".format(server_address), files=files)
    print("Upload status: {}".format(response.status_code))

# Get image from server
def get_image(filename, subfolder, folder_type, server_address, aws_alb_cookie):
    data = {"filename": filename, "subfolder": subfolder, "type": folder_type}
    url_values = urllib.parse.urlencode(data)
    response = requests.get("{}/view?{}".format(server_address, url_values), headers={"Cookie": aws_alb_cookie})
    return response.content

# Get invocation history from server
def get_history(prompt_id, server_address, aws_alb_cookie):
    response = requests.get("{}/history/{}".format(server_address, prompt_id), headers={"Cookie": aws_alb_cookie})
    return response.json()

def get_queue_status(prompt_id, server_address):
    response = requests.get("{}/queue".format(server_address))
    print("Queue status: {} items".format(len(response.json().get("queue_running", []))))

if __name__ == "__main__":
    test_api("https://your-cloudfront-url.example.com")
