import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ecr from 'aws-cdk-lib/aws-ecr';

export class ComfyuiEcrRepo extends cdk.Stack {
    constructor(scope: Construct, id: string, props: cdk.StackProps) {
        super(scope, id, props);
        const repo = new ecr.Repository(this, 'comfyui-images', {
            repositoryName: 'comfyui-images',
            removalPolicy: cdk.RemovalPolicy.DESTROY,
        });
    }
}

