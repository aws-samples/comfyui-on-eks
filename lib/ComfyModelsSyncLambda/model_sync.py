# Python lambda

import json
import boto3

account_id = boto3.client('sts').get_caller_identity().get('Account')
region = boto3.session.Session().region_name
S3_BUCKET = 's3://comfyui-models-%s-%s' % (account_id, region)
NODE_DIR = '/comfyui-models'

# Print files change in S3
def show_files_change(event):
    for record in event['Records']:
        obj_name = record['s3']['object']['key']
        obj_size = record['s3']['object']['size']
        if obj_size > 1073741824:
            obj_size = str(round(obj_size / 1073741824, 2)) + 'GB'
        elif obj_size > 1048576:
            obj_size = str(round(obj_size / 1048576, 2)) + 'MB'
        elif obj_size > 1024:
            obj_size = str(round(obj_size / 1024, 2)) + 'KB'
        else:
            obj_size = str(obj_size) + 'B'
        obj_event = record['eventName']
        print(obj_name, obj_size, obj_event)

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
                'Values': ['Comfyui-Cluster']
            },
            {
                'Name': 'tag:karpenter.sh/managed-by',
                'Values': ['Comfyui-Cluster']
            },
            {
                'Name': 'tag:kubernetes.io/cluster/Comfyui-Cluster',
                'Values': ['owned']
            },
        ],
    )
    instance_ids = []
    for reservation in response['Reservations']:
        for instance in reservation['Instances']:
            instance_ids.append(instance['InstanceId'])
    return instance_ids

# Sync models to all GPU instances
def sync_models_to_gpu_instances(instance_ids):
    ssm = boto3.client('ssm')
    response = ssm.send_command(
        InstanceIds=instance_ids,
        DocumentName="AWS-RunShellScript",
        Parameters={'commands': ['aws s3 sync %s %s --delete' % (S3_BUCKET, NODE_DIR)]}
    )
    return response

def lambda_handler(event, context):
    show_files_change(event)
    instance_ids = get_all_gpu_instances()
    print("Following instances will be synced:", instance_ids)
    response = sync_models_to_gpu_instances(instance_ids)
    # print command and status
    print(response['Command']['Parameters']['commands'], response['Command']['Status'])
    return {
        'statusCode': 200,
        'body': json.dumps('Models synced!')
    }
