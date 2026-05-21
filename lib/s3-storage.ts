import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';

export class S3Storage extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, { ...props, description: 'ComfyUI on EKS - S3 buckets for workflow inputs and image outputs' });

    const outputsBucketName = `comfyui-outputs-${this.account}-${this.region}`;
    new s3.Bucket(this, outputsBucketName, {
        bucketName: outputsBucketName,
        removalPolicy: cdk.RemovalPolicy.RETAIN,
        encryption: s3.BucketEncryption.S3_MANAGED,
    });

    const inputsBucketName = `comfyui-inputs-${this.account}-${this.region}`;
    new s3.Bucket(this, inputsBucketName, {
        bucketName: inputsBucketName,
        removalPolicy: cdk.RemovalPolicy.RETAIN,
        encryption: s3.BucketEncryption.S3_MANAGED,
    });
  }
}
