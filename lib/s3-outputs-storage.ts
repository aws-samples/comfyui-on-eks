import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';

export class S3OutputsStorage extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create S3 bucket for outputs
    const bucketName = 'comfyui-outputs-' + this.account + '-' + this.region;
    const outputs_bucket = new s3.Bucket(this, bucketName, {
        bucketName: bucketName,
        autoDeleteObjects: true,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
  }
}
