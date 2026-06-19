import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as lambdaEventSources from 'aws-cdk-lib/aws-lambda-event-sources';
import * as iam from 'aws-cdk-lib/aws-iam';

export class LambdaModelsSync extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, { ...props, description: 'ComfyUI on EKS - Models S3 bucket and Lambda for sync to GPU nodes' });

    const bucketName = `comfyui-models-${this.account}-${this.region}`;
    const accessLogsBucket = new s3.Bucket(this, 'ModelsAccessLogs', {
        bucketName: `comfyui-models-access-logs-${this.account}-${this.region}`,
        removalPolicy: cdk.RemovalPolicy.RETAIN,
        lifecycleRules: [{ expiration: cdk.Duration.days(90) }],
    });
    const models_bucket = new s3.Bucket(this, bucketName, {
        bucketName: bucketName,
        removalPolicy: cdk.RemovalPolicy.RETAIN,
        serverAccessLogsBucket: accessLogsBucket,
        serverAccessLogsPrefix: 'models-bucket/',
    });

    const lambdaRole = new iam.Role(this, 'ComfyModelsSyncLambdaRole', {
        assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
        managedPolicies: [
            iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        ],
        inlinePolicies: {
            modelSync: new iam.PolicyDocument({
                statements: [
                    new iam.PolicyStatement({
                        actions: ['ssm:SendCommand'],
                        resources: [
                            `arn:aws:ec2:${this.region}:${this.account}:instance/*`,
                        ],
                        conditions: {
                            StringEquals: {
                                'ssm:resourceTag/aws:eks:cluster-name': 'ComfyUI-on-EKS-Cluster',
                            },
                        },
                    }),
                    new iam.PolicyStatement({
                        actions: ['ssm:SendCommand'],
                        resources: [
                            `arn:aws:ssm:${this.region}::document/AWS-RunShellScript`,
                        ],
                    }),
                    new iam.PolicyStatement({
                        actions: ['ssm:GetCommandInvocation'],
                        // ssm:GetCommandInvocation does not support resource-level permissions
                        resources: ['*'],
                    }),
                    new iam.PolicyStatement({
                        actions: ['ec2:DescribeInstances'],
                        // ec2:DescribeInstances does not support resource-level permissions
                        resources: ['*'],
                    }),
                    new iam.PolicyStatement({
                        actions: ['s3:GetObject', 's3:ListBucket'],
                        resources: [models_bucket.bucketArn, `${models_bucket.bucketArn}/*`],
                    }),
                ],
            }),
        },
    });

    const modelsSyncLambda = new lambda.Function(this, 'ComfyModelsSyncLambda', {
        runtime: lambda.Runtime.PYTHON_3_12,
        code: lambda.Code.fromAsset('lib/ComfyModelsSyncLambda'),
        handler: 'model_sync.lambda_handler',
        functionName: 'comfy-models-sync',
        role: lambdaRole,
        timeout: cdk.Duration.seconds(120),
        memorySize: 256,
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
