import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as lambdaEventSources from 'aws-cdk-lib/aws-lambda-event-sources';
import * as iam from 'aws-cdk-lib/aws-iam';
import { PROJECT_NAME } from '../env'

const project_name = PROJECT_NAME.toLowerCase()

export class LambdaModelsSync extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create S3 bucket for models
    const bucketName = `comfyui-models-${project_name}`.replace(/-$/,'') + '-' + this.account + '-' + this.region;
    const models_bucket = new s3.Bucket(this, bucketName, {
        bucketName: bucketName,
        autoDeleteObjects: true,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create IAM role for lambda
    const roleName = `ComfyModelsSyncLambdaRole-${PROJECT_NAME}`.replace(/-$/,'') + '-' + this.account + '-' + this.region;
    const lambdaRole = new iam.Role(this, 'ComfyModelsSyncLambdaRole', {
        roleName: roleName,
        assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
        managedPolicies: [
            iam.ManagedPolicy.fromAwsManagedPolicyName('AdministratorAccess'),
        ],
    });

    const modelsSyncLambda = new lambda.Function(this, 'ComfyModelsSyncLambda', {
        runtime: lambda.Runtime.PYTHON_3_10,
        code: lambda.Code.fromAsset('lib/ComfyModelsSyncLambda'),
        handler: 'model_sync.lambda_handler',
        functionName: `comfy-models-sync-${PROJECT_NAME}`.replace(/-$/,''),
        role: lambdaRole,
    });

    const s3EventSource = new lambdaEventSources.S3EventSource(models_bucket, {
        events: [
            s3.EventType.OBJECT_CREATED,
            s3.EventType.OBJECT_REMOVED,
        ],
    });

    modelsSyncLambda.addEventSource(s3EventSource);
  }
}
