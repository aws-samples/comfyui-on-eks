# Python lambda

import json
import re
import boto3

VALID_MODEL_KEY = re.compile(r'^[a-zA-Z0-9/_.\-]+$')

def validate_model_key(key):
    if not key or len(key) > 512 or not VALID_MODEL_KEY.match(key):
        raise ValueError(f"Invalid model key rejected: {key!r}")
    if '..' in key:
        raise ValueError(f"Path traversal rejected: {key!r}")
    return key

account_id = boto3.client('sts').get_caller_identity().get('Account')
region = boto3.session.Session().region_name
S3_BUCKET = 's3://comfyui-models-%s-%s' % (account_id, region)
NODE_DIR = '/comfyui-models'

# Collect changed keys with their event type (CREATE vs REMOVE)
def files_change(event):
    changes = []
    for record in event['Records']:
        obj_name = record['s3']['object']['key']
        obj_size = record['s3']['object'].get('size', 0)
        if obj_size > 1073741824:
            size_str = str(round(obj_size / 1073741824, 2)) + 'GB'
        elif obj_size > 1048576:
            size_str = str(round(obj_size / 1048576, 2)) + 'MB'
        elif obj_size > 1024:
            size_str = str(round(obj_size / 1024, 2)) + 'KB'
        else:
            size_str = str(obj_size) + 'B'
        obj_event = record['eventName']
        print(obj_name, size_str, obj_event)
        changes.append((obj_name, obj_event))
    return changes

# Get all GPU instances in Comfyui cluster
# Modify the filter if needed
def get_all_gpu_instances():
    ec2 = boto3.client('ec2')
    response = ec2.describe_instances(
        Filters=[
            {
                'Name': 'instance-state-name',
                'Values': ['running']
            },
            {
                'Name': 'tag:aws:eks:cluster-name',
                'Values': ['ComfyUI-on-EKS-Cluster']
            },
            {
                'Name': 'tag:karpenter.sh/nodepool',
                'Values': ['karpenter-nodepool']
            },
        ],
    )
    instance_ids = []
    for reservation in response['Reservations']:
        for instance in reservation['Instances']:
            instance_ids.append(instance['InstanceId'])
    return instance_ids

# Sync models to all GPU instances
# S3 bucket is created by the same CDK stack — not user-provided, mitigating bucket squatting
def sync_models_to_gpu_instances(instance_ids):
    ssm = boto3.client('ssm')
    response = ssm.send_command(
        InstanceIds=instance_ids,
        DocumentName="AWS-RunShellScript",
        Parameters={'commands': ['aws s3 sync --checksum-mode ENABLED %s/* %s' % (S3_BUCKET, NODE_DIR)]},
        CloudWatchOutputConfig={'CloudWatchOutputEnabled': True},
    )
    return response

# Apply a single model change (copy on create, delete on remove) across GPU nodes
def sync_single_model_to_gpu_instances(instance_ids, model_key, is_delete):
    ssm = boto3.client('ssm')
    if is_delete:
        command = 'rm -f %s/%s' % (NODE_DIR, model_key)
    else:
        command = 'aws s3 cp --checksum-mode ENABLED %s/%s %s/%s' % (S3_BUCKET, model_key, NODE_DIR, model_key)
    response = ssm.send_command(
        InstanceIds=instance_ids,
        DocumentName="AWS-RunShellScript",
        Parameters={'commands': [command]},
        CloudWatchOutputConfig={'CloudWatchOutputEnabled': True},
    )
    return response

def lambda_handler(event, context):
    changes = files_change(event)
    instance_ids = get_all_gpu_instances()
    print("Following instances will be synced:", instance_ids)
    if not instance_ids:
        # No running GPU nodes (e.g. scaled to zero). New nodes sync from S3 on boot
        # via user-data, so this is not an error — but surface it so a stuck sync is visible.
        print("WARNING: no running GPU instances matched; nothing to sync now.")
        return {'statusCode': 200, 'body': json.dumps('No GPU instances to sync.')}
    command_ids = []
    for model_key, obj_event in changes:
        is_delete = obj_event.startswith('ObjectRemoved')
        try:
            validate_model_key(model_key)
        except ValueError as e:
            print(f"Skipping invalid model key: {e}")
            continue
        response = sync_single_model_to_gpu_instances(instance_ids, model_key, is_delete)
        command_id = response['Command']['CommandId']
        command_ids.append(command_id)
        # Status at send time is always 'Pending'; the real result is in the SSM command
        # history / CloudWatch (command output is now streamed there). Log the dispatch.
        print(f"Dispatched SSM command {command_id} ({'rm' if is_delete else 'cp'} {model_key})")
    return {
        'statusCode': 200,
        'body': json.dumps({'message': 'Model sync dispatched', 'command_ids': command_ids}),
    }
