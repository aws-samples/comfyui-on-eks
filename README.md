## Custom Nodes Support

Typically, ComfyUI users use various custom nodes to build their own workflows, often utilizing [ComfyUI-Manager](https://github.com/ltdrdata/ComfyUI-Manager) to conveniently install and manage their custom nodes.

To support custom nodes in the current solution, two things need to be prepared (if you're unfamiliar with the current solution, it's recommended to review the deployment instructions first):

1. Code and Environment: Custom node code is placed in `$HOME/ComfyUI/custom_nodes`, and the environment is prepared by running `pip install -r` on all requirements.txt files in the custom node directories (any dependency conflicts between custom nodes need to be handled separately). Additionally, any system packages required by the custom nodes should be installed. All these operations are performed through the Dockerfile, building an image containing the required custom nodes.
2. Models: Models used by custom nodes are placed in different directories under `s3://comfyui-models-{account_id}-{region}`. This triggers a Lambda function to send commands to all GPU nodes to synchronize the newly uploaded models to local instance store.



Next, we'll use the [Stable Video Diffusion (SVD) - Image to video generation with high FPS](https://comfyworkflows.com/workflows/bf3b455d-ba13-4063-9ab7-ff1de0c9fa75) workflow as an example to illustrate how to support custom nodes (you can also use your own workflow).



### 1. Build image

When loading this workflow, it will display the missing custom nodes. Next, we will build the missing custom nodes into the image.

 <img src="images/miss_custom_nodes.png" style="zoom:50%;" />



There are two ways to build the image:

1. **Build from GitHub**: In the Dockerfile, download the code for each custom node and set up the environment and dependencies separately.
2. **Build locally**: Copy all the custom nodes from your local Dev environment into the image and set up the environment and dependencies.



Before building the image, please switch to the corresponding branch

```shell
git clone https://github.com/aws-samples/comfyui-on-eks ~/comfyui-on-eks
cd ~/comfyui-on-eks && git checkout custom_nodes_demo
```



#### 1.1 Build from GitHub

Install custom nodes and dependencies with `RUN` command in the Dockerfile. You'll need to find the GitHub URLs for all missing custom nodes.

```dockerfile
...
RUN apt-get update && apt-get install -y \
    git \
    python3.10 \
    python3-pip \
    # needed by custom node ComfyUI-VideoHelperSuite
    libsm6 \
    libgl1 \
    libglib2.0-0
...
# Custom nodes demo of https://comfyworkflows.com/workflows/bf3b455d-ba13-4063-9ab7-ff1de0c9fa75

## custom node ComfyUI-Stable-Video-Diffusion
RUN cd /app/ComfyUI/custom_nodes && git clone https://github.com/thecooltechguy/ComfyUI-Stable-Video-Diffusion.git && cd ComfyUI-Stable-Video-Diffusion/ && python3 install.py
## custom node ComfyUI-VideoHelperSuite
RUN cd /app/ComfyUI/custom_nodes && git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && pip3 install -r ComfyUI-VideoHelperSuite/requirements.txt
## custom node ComfyUI-Frame-Interpolation
RUN cd /app/ComfyUI/custom_nodes && git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git && cd ComfyUI-Frame-Interpolation/ && python3 install.py
...
```

Refer to `comfyui-on-eks/comfyui_image/Dockerfile.github` for the complete Dockerfile.

Run following command to build and push Docker image

```shell
region="us-west-2" # Modify the region to your current region.
cd ~/comfyui-on-eks/comfyui_image/ && bash build_and_push.sh $region Dockerfile.github
```

Pros：

* Clear understanding of the installation method, version, and environmental dependencies for each custom node, providing better control over the entire ComfyUI environment.

Cons：

* When there are too many custom nodes, installation and management can be time-consuming, and you need to find the URL for each custom node yourself (on the other hand, this can also be seen as an pros, as it makes you more familiar with the entire ComfyUI environment).



#### 1.2 Build locally 

Often, we use [ComfyUI-Manager](https://github.com/ltdrdata/ComfyUI-Manager) to install missing custom nodes. ComfyUI-Manager hides the installation details, and we cannot clearly know which custom nodes have been installed. In this case, we can build the image by COPY the entire ComfyUI directory (except the input, output, models, etc. directories) into the Dockerfile.

The prerequisite for building the image locally is that you already have a working ComfyUI environment with custom nodes. In the same directory as ComfyUI, create a `.dockerignore` file and add the following content to ignore these directories when building the Docker image

```
ComfyUI/models
ComfyUI/input
ComfyUI/output
ComfyUI/custom_nodes/ComfyUI-Manager
```

Copy the two files `comfyui-on-eks/comfyui_image/Dockerfile.local` and `comfyui-on-eks/comfyui_image/build_and_push.sh` to the same directory as your local `ComfyUI`, like this:

```shell
ubuntu@comfyui:~$ ll
-rwxrwxr-x  1 ubuntu ubuntu       792 Jul 16 10:27 build_and_push.sh*
drwxrwxr-x 19 ubuntu ubuntu      4096 Jul 15 08:10 ComfyUI/
-rw-rw-r--  1 ubuntu ubuntu       784 Jul 16 10:41 Dockerfile.local
-rw-rw-r--  1 ubuntu ubuntu        81 Jul 16 10:45 .dockerignore
...
```

The `Dockerfile.local` builds the image by COPY the directory

```dockerfile
...
# Python Evn
RUN pip3 install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu121
COPY ComfyUI /app/ComfyUI
RUN pip3 install -r /app/ComfyUI/requirements.txt

# Custom Nodes Env, may encounter some conflicts
RUN find /app/ComfyUI/custom_nodes -maxdepth 2 -name "requirements.txt"|xargs -I {} pip install -r {}
...
```

Refer to `comfyui-on-eks/comfyui_image/Dockerfile.local` for the complete Dockerfile.

Run the following command to build and upload the Docker image

```shell
region="us-west-2" # Modify the region to your current region.
bash build_and_push.sh $region Dockerfile.local
```

Pros：

* You can easily and quickly build your local Dev environment into an image for deployment, without paying attention to the installation, version, and dependency details of custom nodes when there are many of them.

Cons：

* Not paying attention to the deployment environment of custom nodes may cause conflicts or missing dependencies, which need to be manually tested and resolved.



### 2. Upload Models

Upload all the models needed for the workflow to the `s3://comfyui-models-{account_id}-{region}` corresponding directory using your preferred method. The GPU nodes will automatically sync from S3 (triggered by Lambda). If the models are large and numerous, you may need to wait for some time. You can log into the GPU nodes using the `aws ssm start-session --target ${instance_id}` command and use the `ps` command to check the progress of the `aws s3 sync` process.



### 3. Test the Docker Image Locally (Optional, Recommended)

Since there are many types of custom nodes with different dependencies and versions, the runtime environment is quite complex. It is recommended to test the Docker image locally after building it in Step 1 to ensure it runs correctly.

Refer to the code in `comfyui-on-eks/comfyui_image/test_docker_image_locally.sh`. Prepare the models and input directories (assuming the models and input images are stored in `/home/ubuntu/ComfyUI/models` and `/home/ubuntu/ComfyUI/input` respectively), and run the script to test the Docker image

```shell
comfyui-on-eks/comfyui_image/test_docker_image_locally.sh
```



### 4. Rolling Update K8S pods

Use your preferred method to perform a rolling update of the image for the online K8S pods, and then test the service.

 ![svd-custom-nodes](images/svd-custom-nodes.gif)



---

Refer to main branch for other deployment instructions.
