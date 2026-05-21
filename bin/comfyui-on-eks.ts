import * as cdk from 'aws-cdk-lib';
import BlueprintConstruct from '../lib/comfyui-on-eks-stack';
import { CloudFrontEntry } from '../lib/cloudfront-entry';
import { LambdaModelsSync } from '../lib/lambda-models-sync';
import { S3Storage } from '../lib/s3-storage';
import { ComfyuiEcrRepo } from '../lib/comfyui-ecr-repo';

const app = new cdk.App();

const account = process.env.CDK_DEFAULT_ACCOUNT;
const region = process.env.CDK_DEFAULT_REGION;
const props = { env: { account, region } };

cdk.Tags.of(app).add('Project', 'comfyui-on-eks');

new BlueprintConstruct(app, props);
new CloudFrontEntry(app, 'ComfyUI-on-EKS-CloudFront', props);
new LambdaModelsSync(app, 'ComfyUI-on-EKS-Models', props);
new S3Storage(app, 'ComfyUI-on-EKS-S3', props);
new ComfyuiEcrRepo(app, 'ComfyUI-on-EKS-ECR', props);