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

new BlueprintConstruct(app, props);
new CloudFrontEntry(app, "CloudFrontEntry", props);
new LambdaModelsSync(app, "LambdaModelsSync", props);
new S3Storage(app, "S3Storage", props);
new ComfyuiEcrRepo(app, "ComfyuiEcrRepo", props);
