import boto3
from botocore.exceptions import ClientError

SERVER_AMI = 'ami-07c47b4b311ddee52'

DEFAULT_VPC_ID = "vpc-7518290f"


def file_read(file_name: str) -> str:
    with open(file_name, "r") as f:
        return f.read()


def import_certificate() -> str:
    client = boto3.client('acm')
    private_key = file_read('myserver.info.key')
    certificate = file_read('myserver.info.cert')
    response = client.import_certificate(
        Certificate=certificate.encode(),
        PrivateKey=private_key.encode(),
        Tags=[
            {
                'Key': 'Name',
                'Value': 'ccdba-lab'
            },
        ]
    )
    return response['CertificateArn']


def create_security_group(group_name: str, desc: str) -> str:
    ec2 = boto3.resource('ec2')
    vpc = ec2.Vpc(DEFAULT_VPC_ID)
    ec2.security_groups.filter(group_name=group_name)
    security_groups = ec2.security_groups.filter(Filters=[{'Name': 'vpc-id', 'Values': [DEFAULT_VPC_ID, ]}, ])
    for sg in security_groups:
        if sg.group_name == group_name:
            return sg.id
    security_group = vpc.create_security_group(
        Description=desc,
        GroupName=group_name)
    return security_group.id


def load_balancer_sg_config(group_id: str):
    ec2 = boto3.resource('ec2')
    sg = ec2.SecurityGroup(group_id)
    sg_config_idempotent(sg.authorize_ingress, CidrIp='0.0.0.0/0', FromPort=80, IpProtocol='TCP', ToPort=80)
    sg_config_idempotent(sg.authorize_ingress, CidrIp='0.0.0.0/0', FromPort=443, IpProtocol='TCP', ToPort=443)


def sg_config_idempotent(config_call, **args):
    try:
        config_call(**args)
    except ClientError as error:
        if error.response['Error']['Code'] == 'InvalidPermission.Duplicate':
            print("Configuration exists skipping: ", args)
        else:
            print(error)


def create_target_group(elb_client) -> str:
    response = elb_client.create_target_group(
        Name='web-server-group',
        Protocol='HTTP',
        Port=80,
        VpcId=DEFAULT_VPC_ID,
        HealthCheckEnabled=True,
        TargetType='instance'
    )
    return response['TargetGroups'][0]['TargetGroupArn']


def create_load_balancer(elb_client, security_group: str) -> (str, str):
    response = elb_client.create_load_balancer(
        Name='load-balancer',
        Subnets=subnets,
        SecurityGroups=[
            security_group,
        ],
        Scheme='internet-facing',
        Type='application',
        Tags=[
            {
                'Key': 'Name',
                'Value': 'load-balancer'
            },
            {
                'Key': 'CreatedBy',
                'Value': 'PythonScript',
            },
        ]
    )
    balancer = response['LoadBalancers'][0]
    return balancer['LoadBalancerArn'], balancer['DNSName']


def get_subnets():
    ec2 = boto3.resource('ec2')
    vpc = ec2.Vpc(DEFAULT_VPC_ID)
    local_nets = []
    for subnet in vpc.subnets.all():
        local_nets.append(subnet.id)
    return local_nets


def create_listeners(elb_client, balancer_arn: str, target_grp_arn: str):
    response = elb_client.create_listener(
        LoadBalancerArn=balancer_arn,
        Protocol='HTTP',
        Port=80,
        DefaultActions=[
            {
                'Type': 'forward',
                'TargetGroupArn': target_grp_arn,
            },
        ]
    )
    return response['Listeners'][0]['ListenerArn']


def configure_load_balancer(security_group: str) -> (str, str):
    elb_client = boto3.client('elbv2')
    target_grp_arn = create_target_group(elb_client)
    balancer_arn, dns_name = create_load_balancer(elb_client, security_group)
    create_listeners(elb_client, balancer_arn, target_grp_arn)
    return dns_name, target_grp_arn


def web_sb_config(web_sg: str, load_balancer_sg_id: str):
    ec2 = boto3.resource('ec2')
    sg = ec2.SecurityGroup(web_sg)
    sg_config_idempotent(sg.authorize_ingress, IpPermissions=[
        {
            'FromPort': 80,
            'IpProtocol': 'TCP',
            'ToPort': 80,
            'UserIdGroupPairs': [
                {
                    'Description': 'Allow traffic from load balancer',
                    'GroupId': load_balancer_sg_id,
                },
            ]
        },
    ])


def create_launch_config(client, web_sg_id: str, launch_config_name: str):
    try:
        client.delete_launch_configuration(
            LaunchConfigurationName=launch_config_name
        )
    except:
        pass
    response = client.create_launch_configuration(
        LaunchConfigurationName=launch_config_name,
        ImageId=SERVER_AMI,
        KeyName='ec2Demo',
        SecurityGroups=[
            web_sg_id
        ],
        InstanceType='t2.micro',
        InstanceMonitoring={
            'Enabled': False
        },
        AssociatePublicIpAddress=True,
    )
    return response


def create_auto_scaling_group(client, target_group_arn: str, launch_config_name: str):
    auto_scaler_name = 'webserver-auto-scaling'
    try:
        response = client.delete_auto_scaling_group(
            AutoScalingGroupName=auto_scaler_name,
            ForceDelete=True
        )
    except:
        pass

    client.create_auto_scaling_group(
        AutoScalingGroupName=auto_scaler_name,
        LaunchConfigurationName=launch_config_name,
        MinSize=2,
        MaxSize=2,
        DesiredCapacity=2,
        DefaultCooldown=200,
        TargetGroupARNs=[target_group_arn, ],
        HealthCheckType='EC2',
        HealthCheckGracePeriod=60,
        VPCZoneIdentifier=",".join(subnets),
        Tags=[
            {
                'Key': 'CreatedBy',
                'Value': 'PythonScript',
            },
        ],
    )


def configure_auto_scaling_group(load_balancer_sg_id: str, target_group_arn: str):
    web_sg = create_security_group('web-sg', 'SG for server instances')
    web_sb_config(web_sg, load_balancer_sg_id)
    client = boto3.client('autoscaling')
    launch_config_name = 'web-server-launch-config'
    create_launch_config(client, web_sg, launch_config_name)
    create_auto_scaling_group(client, target_group_arn, launch_config_name)


if __name__ == '__main__':
    subnets = get_subnets()
    load_balancer_sg = create_security_group('loadbalancer-sg', 'Security Group to allow traffic to Load Balancer')
    load_balancer_sg_config(load_balancer_sg)
    domain_url, target_group_arn = configure_load_balancer(load_balancer_sg)
    configure_auto_scaling_group(load_balancer_sg, target_group_arn)
    print("The server has been deployed and available at: ", domain_url)