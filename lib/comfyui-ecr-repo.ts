import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as codebuild from 'aws-cdk-lib/aws-codebuild';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';

export class ComfyuiEcrRepo extends cdk.Stack {
    constructor(scope: Construct, id: string, props: cdk.StackProps) {
        super(scope, id, { ...props, description: 'ComfyUI on EKS - ECR repository and CodeBuild project for container images' });

        const repo = new ecr.Repository(this, 'comfyui-images', {
            repositoryName: 'comfyui-images',
            removalPolicy: cdk.RemovalPolicy.RETAIN,
            imageScanOnPush: true,
            lifecycleRules: [
                {
                    maxImageCount: 10,
                    description: 'Keep only the 10 most recent images',
                },
            ],
        });

        const modelsBucket = s3.Bucket.fromBucketName(this, 'ModelsBucket',
            `comfyui-models-${this.account}-${this.region}`);

        const codebuildRole = new iam.Role(this, 'CodeBuildRole', {
            assumedBy: new iam.ServicePrincipal('codebuild.amazonaws.com'),
            managedPolicies: [
                iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEC2ContainerRegistryPowerUser'),
            ],
            inlinePolicies: {
                codebuildS3: new iam.PolicyDocument({
                    statements: [
                        new iam.PolicyStatement({
                            actions: ['s3:GetObject', 's3:GetBucketLocation'],
                            resources: [modelsBucket.bucketArn, `${modelsBucket.bucketArn}/*`],
                        }),
                        new iam.PolicyStatement({
                            actions: ['logs:CreateLogGroup', 'logs:CreateLogStream', 'logs:PutLogEvents'],
                            resources: ['*'],
                        }),
                    ],
                }),
            },
        });

        new codebuild.Project(this, 'ComfyuiImageBuild', {
            projectName: 'comfyui-image-build',
            environment: {
                buildImage: codebuild.LinuxBuildImage.STANDARD_7_0,
                computeType: codebuild.ComputeType.LARGE,
                privileged: true,
                environmentVariables: {
                    AWS_DEFAULT_REGION: { value: this.region },
                    AWS_ACCOUNT_ID: { value: this.account },
                    IMAGE_REPO_NAME: { value: 'comfyui-images' },
                    IMAGE_TAG: { value: 'latest' },
                },
            },
            source: codebuild.Source.s3({
                bucket: modelsBucket,
                path: 'codebuild/comfyui-build-source.zip',
            }),
            role: codebuildRole,
            timeout: cdk.Duration.minutes(60),
        });

        const modelDownloadRole = new iam.Role(this, 'ModelDownloadRole', {
            assumedBy: new iam.ServicePrincipal('codebuild.amazonaws.com'),
            inlinePolicies: {
                modelDownloadS3: new iam.PolicyDocument({
                    statements: [
                        new iam.PolicyStatement({
                            actions: ['s3:GetObject', 's3:PutObject', 's3:ListBucket', 's3:GetBucketLocation'],
                            resources: [modelsBucket.bucketArn, `${modelsBucket.bucketArn}/*`],
                        }),
                        new iam.PolicyStatement({
                            actions: ['logs:CreateLogGroup', 'logs:CreateLogStream', 'logs:PutLogEvents'],
                            resources: ['*'],
                        }),
                    ],
                }),
            },
        });

        new codebuild.Project(this, 'ComfyuiModelDownload', {
            projectName: 'comfyui-model-download',
            environment: {
                buildImage: codebuild.LinuxBuildImage.STANDARD_7_0,
                computeType: codebuild.ComputeType.LARGE,
                environmentVariables: {
                    MODELS_BUCKET: { value: `comfyui-models-${this.account}-${this.region}` },
                    MODEL_TIER: { value: 'all' },
                },
            },
            source: codebuild.Source.s3({
                bucket: modelsBucket,
                path: 'codebuild/comfyui-models-source.zip',
            }),
            role: modelDownloadRole,
            timeout: cdk.Duration.hours(4),
        });
    }
}
