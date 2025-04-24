# ComfyUI on EKS Helm Chart

This Helm chart deploys ComfyUI on Amazon EKS with the following features:

- GPU-enabled nodes using Karpenter for auto-scaling
- S3 integration for inputs, outputs, and custom nodes storage
- ECR integration for container images
- ALB ingress controller integration

## Prerequisites

- Kubernetes 1.24+
- Helm 3.0+
- AWS CLI configured with appropriate permissions
- kubectl configured to communicate with your EKS cluster
- yq 4.0+

## Installation

1. Update the values in `values.yaml` or use the `helm_deploy.sh` script:

```bash
./helm_deploy.sh \
    -b S3Storage \
    -e ComfyuiEcrRepo \
    -k Comfyui-Cluster \
    -v ./chart/values.yaml \
    -c ./chart
```

2. Manual installation:
Update respective values in Values.yaml file and run the following command:
```bash
helm upgrade --install comfyui-eks ./chart 
```
## Cleanup
```bash
helm uninstall comfyui-eks
```