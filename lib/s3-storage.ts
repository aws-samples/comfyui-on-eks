import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';
import { PROJECT_NAME } from '../env'

const project_name = PROJECT_NAME.toLowerCase()

export class S3Storage extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create S3 bucket for outputs
    const outputs_bucketName = `comfyui-outputs-${project_name}`.replace(/-$/,'') + '-' + this.account + '-' + this.region;
    const outputs_bucket = new s3.Bucket(this, outputs_bucketName, {
        bucketName: outputs_bucketName,
        autoDeleteObjects: true,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create S3 bucket for inputs
    const inputs_bucketName = `comfyui-inputs-${project_name}`.replace(/-$/,'') + '-' + this.account + '-' + this.region;
    const inputs_bucket = new s3.Bucket(this, inputs_bucketName, {
        bucketName: inputs_bucketName,
        autoDeleteObjects: true,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create S3 bucket for custom nodes
    const customNodes_bucketName = `comfyui-custom-nodes-${project_name}`.replace(/-$/,'') + '-' + this.account + '-' + this.region;
    const customNodes_bucket = new s3.Bucket(this, customNodes_bucketName, {
        bucketName: customNodes_bucketName,
        autoDeleteObjects: true,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Add CloudFormation outputs
    new cdk.CfnOutput(this, 'OutputsBucketName', {
      value: outputs_bucket.bucketName,
      description: 'The name of the outputs bucket',
      exportName: 'ComfyUIOutputsBucket'
    });

    new cdk.CfnOutput(this, 'InputsBucketName', {
      value: inputs_bucket.bucketName,
      description: 'The name of the inputs bucket',
      exportName: 'ComfyUIInputsBucket'
    });

    new cdk.CfnOutput(this, 'CustomNodesBucketName', {
      value: customNodes_bucket.bucketName,
      description: 'The name of the custom nodes bucket',
      exportName: 'ComfyUICustomNodesBucket'
    });

    // Add ARN outputs
    new cdk.CfnOutput(this, 'OutputsBucketArn', {
      value: outputs_bucket.bucketArn,
      description: 'The ARN of the outputs bucket',
      exportName: 'ComfyUIOutputsBucketArn'
    });

    new cdk.CfnOutput(this, 'InputsBucketArn', {
      value: inputs_bucket.bucketArn,
      description: 'The ARN of the inputs bucket',
      exportName: 'ComfyUIInputsBucketArn'
    });

    new cdk.CfnOutput(this, 'CustomNodesBucketArn', {
      value: customNodes_bucket.bucketArn,
      description: 'The ARN of the custom nodes bucket',
      exportName: 'ComfyUICustomNodesBucketArn'
    });
  }
}
