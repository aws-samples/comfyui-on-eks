import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as cloudFront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';

export class CloudFrontEntry extends cdk.Stack {
    constructor(scope: Construct, id: string, props: cdk.StackProps) {
        super(scope, id, { ...props, description: 'ComfyUI on EKS - CloudFront distribution with VPC origin for secure access' });

        // Get the existing internal ALB created by the EKS ingress controller
        const eksIngress = elbv2.ApplicationLoadBalancer.fromLookup(this, 'eksIngress', {
            loadBalancerTags: {
                'elbv2.k8s.aws/cluster': 'ComfyUI-on-EKS-Cluster',
                'ingress.k8s.aws/resource': 'LoadBalancer',
                'ingress.k8s.aws/stack': 'default/comfyui-ingress',
            }
        })

        // Create a CloudFront distribution using VPC Origin to reach the internal ALB
        const cloudFrontEntry = new cloudFront.Distribution(this, 'cloudFrontEntry', {
            defaultBehavior: {
                origin: origins.VpcOrigin.withApplicationLoadBalancer(eksIngress, {
                    protocolPolicy: cloudFront.OriginProtocolPolicy.HTTPS_ONLY,
                }),
                originRequestPolicy: cloudFront.OriginRequestPolicy.ALL_VIEWER,
                cachePolicy: cloudFront.CachePolicy.CACHING_DISABLED,
                allowedMethods: cloudFront.AllowedMethods.ALLOW_ALL,
                viewerProtocolPolicy: cloudFront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
            },
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
