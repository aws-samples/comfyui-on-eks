import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudFront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as acm from 'aws-cdk-lib/aws-certificatemanager';
import * as s3 from 'aws-cdk-lib/aws-s3';

export class CloudFrontEntry extends cdk.Stack {
    constructor(scope: Construct, id: string, props: cdk.StackProps) {
        super(scope, id, props);

        // Get an existing EKS ingress
        const eksIngress = elbv2.ApplicationLoadBalancer.fromLookup(this, 'eksIngress', {
            loadBalancerTags: {
                'elbv2.k8s.aws/cluster': 'Comfyui-Cluster',
                'ingress.k8s.aws/resource': 'LoadBalancer',
                'ingress.k8s.aws/stack': 'default/comfyui-ingress',
            }
        })

        // === [Personal Config] ===
        const arraywangCertificate = acm.Certificate.fromCertificateArn(this,
            'certificate',
            'arn:aws:acm:us-east-1:930179054915:certificate/158ccf2a-532c-4450-97d3-e6f54f74f7cf'
        )
        // === [Personal Config] ===

        // Create a new CloudFront distribution for the EKS ingress
        const cloudFrontEntry = new cloudFront.Distribution(this, 'cloudFrontEntry', {
            defaultBehavior: {
                origin: new origins.LoadBalancerV2Origin(eksIngress, {
                    protocolPolicy: cloudFront.OriginProtocolPolicy.HTTP_ONLY,
                }),
                originRequestPolicy: cloudFront.OriginRequestPolicy.ALL_VIEWER,
                cachePolicy: cloudFront.CachePolicy.CACHING_DISABLED,
                allowedMethods: cloudFront.AllowedMethods.ALLOW_ALL,
                viewerProtocolPolicy: cloudFront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
            },
            // === [Personal Config] ===
            certificate: arraywangCertificate,
            domainNames: ['comfyui.array.wang'],
            enableLogging: true,
            logBucket: new s3.Bucket(this, 'cloudFrontEntryLogBucket', {
                bucketName: 'comfyui-cloudfront-log-' + this.account + '-' + this.region,
                removalPolicy: cdk.RemovalPolicy.DESTROY,
                autoDeleteObjects: true,
                objectOwnership: s3.ObjectOwnership.OBJECT_WRITER,
            }),
            // === [Personal Config] ===
        })

        // Output the name of the ingress
        new cdk.CfnOutput(this, 'eksIngressName', {
            value: eksIngress.loadBalancerDnsName
        })

        // Output the url of the CloudFront distribution
        new cdk.CfnOutput(this, 'cloudFrontEntryUrl', {
            value: cloudFrontEntry.distributionDomainName
        })

        // Output the distribution id
        new cdk.CfnOutput(this, 'cloudFrontEntryId', {
            value: cloudFrontEntry.distributionId
        })
    }
}
