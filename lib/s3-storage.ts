import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';

export class S3Storage extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create S3 bucket for outputs
    const outputs_bucketName = 'comfyui-outputs-' + this.account + '-' + this.region;
    const outputs_bucket = new s3.Bucket(this, outputs_bucketName, {
        bucketName: outputs_bucketName,
        autoDeleteObjects: true,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create S3 bucket for inputs
    const inputs_bucketName = 'comfyui-inputs-' + this.account + '-' + this.region;
    const inputs_bucket = new s3.Bucket(this, inputs_bucketName, {
        bucketName: inputs_bucketName,
        autoDeleteObjects: true,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
  }
}
