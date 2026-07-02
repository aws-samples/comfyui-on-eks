import * as cdk from 'aws-cdk-lib';
import * as ec2 from "aws-cdk-lib/aws-ec2";
import { KubernetesVersion, NodegroupAmiType } from 'aws-cdk-lib/aws-eks';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from "constructs";
import * as blueprints from '@aws-quickstart/eks-blueprints';

const stackName = 'ComfyUI-on-EKS-Cluster';

export default class BlueprintConstruct {
    constructor(scope: Construct, props: cdk.StackProps) {
        // Custom VPC for S3 Gateway Endpoint
        class CustomVpcProvider implements blueprints.ResourceProvider<ec2.IVpc> {
            provide(context: blueprints.ResourceContext): ec2.IVpc {
                const vpc = new ec2.Vpc(context.scope, 'ComfyuiVPC', {
                    ipAddresses: ec2.IpAddresses.cidr('10.2.0.0/16'),
                    maxAzs: 3,
                    subnetConfiguration: [
                        {
                            cidrMask: 20,
                            name: 'public',
                            subnetType: ec2.SubnetType.PUBLIC,
                        },
                        {
                            cidrMask: 20,
                            name: 'private',
                            subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
                        }
                    ],
                    natGateways: 3, // 3 NAT Gateways for 3 AZs
                    gatewayEndpoints: {
                        s3: {
                            service: ec2.GatewayVpcEndpointAwsService.S3
                        }
                    }
                });
                return vpc;
            }
        }

        // Instance profiles of K8S node EC2
        const nodeRole = new blueprints.CreateRoleProvider("blueprint-node-role", new iam.ServicePrincipal("ec2.amazonaws.com"),
        [
            iam.ManagedPolicy.fromAwsManagedPolicyName("AmazonEKS_CNI_Policy"),
            iam.ManagedPolicy.fromAwsManagedPolicyName("AmazonEKSWorkerNodePolicy"),
            iam.ManagedPolicy.fromAwsManagedPolicyName("AmazonEC2ContainerRegistryReadOnly"),
            iam.ManagedPolicy.fromAwsManagedPolicyName("AmazonSSMManagedInstanceCore"),
        ]);

        // Add-ons
        const karpenterAddOn = new blueprints.addons.KarpenterV1AddOn({
            version: '1.9.0',
            values: {replicas: 1}
        });
        const addOns: Array<blueprints.ClusterAddOn> = [
            new blueprints.addons.VpcCniAddOn({
                version: 'v1.22.2-eksbuild.1',
            }),
            new blueprints.addons.AwsLoadBalancerControllerAddOn(),
            new blueprints.addons.SSMAgentAddOn(),
            new blueprints.addons.EksPodIdentityAgentAddOn(),
            karpenterAddOn,
            new blueprints.addons.S3CSIDriverAddOn({
                version: '2.7.0',
                bucketNames: [
                    `comfyui-inputs-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
                    `comfyui-outputs-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
                ],
            }),
            new blueprints.GpuOperatorAddon({
                version: 'v26.3.2',
                values:{
                    driver: {
                      enabled: false
                    },
                    toolkit: {
                      enabled: false
                    },
                    mig: {
                      strategy: 'mixed'
                    },
                    devicePlugin: {
                      enabled: true,
                      version: 'v0.17.0'
                    },
                    migManager: {
                      enabled: true,
                      WITH_REBOOT: true
                    },
                    operator: {
                      defaultRuntime: 'containerd'
                    },
                    gfd: {
                      version: 'v0.17.0'
                    }
                  }
            }),
        ];

        const clusterProvider = new blueprints.GenericClusterProvider({
            version: KubernetesVersion.V1_35,
            tags: {
                "Name": "comfyui-on-eks-cluster",
                "Type": "generic-cluster"
            },
            mastersRole: blueprints.getResource(context => {
                return new iam.Role(context.scope, 'AdminRole', { assumedBy: new iam.AccountRootPrincipal() });
            }),
            managedNodeGroups: [
                addLightWeightNodeGroup()
            ]
        });

        blueprints.EksBlueprint.builder()
            .addOns(...addOns)
            .resourceProvider(blueprints.GlobalResources.Vpc, new CustomVpcProvider())
            .resourceProvider("node-role", nodeRole)
            .clusterProvider(clusterProvider)
            .teams()
            .build(scope, stackName, {
                ...props,
                description: 'ComfyUI on EKS - EKS cluster with GPU nodes and Karpenter autoscaling',
            });
    }
}

function addLightWeightNodeGroup(): blueprints.ManagedNodeGroup {
    return {
        id: 'comfyui-on-eks-mng-lw',
        amiType: NodegroupAmiType.AL2023_X86_64_STANDARD,
        instanceTypes: [new ec2.InstanceType('t3a.xlarge')],
        nodeRole: blueprints.getNamedResource("node-role") as iam.Role,
        minSize: 1,
        desiredSize: 2,
        maxSize: 5,
        forceUpdate: true,
        nodeGroupSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
        launchTemplate: {
            tags: {
                "Name": "comfyui-on-eks-lw-node"
            }
        }
    };
}
