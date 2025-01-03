import * as cdk from 'aws-cdk-lib';
import BlueprintConstruct from '../lib/comfyui-on-eks-stack';
import { CloudFrontEntry } from '../lib/cloudfront-entry';
import { LambdaModelsSync } from '../lib/lambda-models-sync';
import { S3Storage } from '../lib/s3-storage';
import { ComfyuiEcrRepo } from '../lib/comfyui-ecr-repo';
import { PROJECT_NAME } from '../env'

const app = new cdk.App();

const account = process.env.CDK_DEFAULT_ACCOUNT;
const region = process.env.CDK_DEFAULT_REGION;
const props = { env: { account, region } };

new BlueprintConstruct(app, props);
new CloudFrontEntry(app, "CloudFrontEntry", props);
new LambdaModelsSync(app, `LambdaModelsSync-${PROJECT_NAME}`.replace(/-$/,''), props);
new S3Storage(app, `S3Storage-${PROJECT_NAME}`.replace(/-$/,''), props);
new ComfyuiEcrRepo(app, `ComfyuiEcrRepo-${PROJECT_NAME}`.replace(/-$/,''), props);