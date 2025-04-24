import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import { PROJECT_NAME } from '../env'

const project_name = PROJECT_NAME.toLowerCase()

export class ComfyuiEcrRepo extends cdk.Stack {
    constructor(scope: Construct, id: string, props: cdk.StackProps) {
        super(scope, id, props);
        const repo = new ecr.Repository(this, 'comfyui-images', {
            repositoryName: `comfyui-images-${project_name}`.replace(/-$/,''),
            removalPolicy: cdk.RemovalPolicy.DESTROY,
        });
        
        // Add stack output for the repository URL
        new cdk.CfnOutput(this, 'RepositoryUrl', {
            value: repo.repositoryUri,
            description: 'The URI of the ECR repository',
            exportName: 'ComfyuiEcrRepoUrl',
        });
    }
}

