#!/bin/bash


# launch the EC2 instances
aws ec2 run-instances --image-id ${AMI_ID} --count ${N_INSTANCES} --instance-type t2.micro \
	--key-name ${KEY_PAIR} --security-group-ids ${SECURITY_GROUP_ID} --subnet-id ${SUBNET_ID}


# Create an HTTP/HTTPS load-balancer
aws elb create-load-balancer --load-balancer-name load-balancer \
	--listeners "Protocol=HTTP,LoadBalancerPort=80,InstanceProtocol=HTTP,InstancePort=80" \
	"Protocol=HTTPS,LoadBalancerPort=443,InstanceProtocol=HTTP,InstancePort=80,SSLCertificateId=arn:aws:iam::123456789012:server-certificate/my-server-cert" \
	--subnets "subnet-111e3459,subnet-14c09b72,subnet-d141258b" --security-groups sg-0171dbe3907edc46a


sleep 30

# Attach EC2 instance to the load-balancer
aws elb register-instances-with-load-balancer \
                        --load-balancer-name load-balancer \
                        --instances {instanceId}

# Create auto-scaling group
aws autoscaling create-auto-scaling-group --auto-scaling-group-name web-server-auto-scaling-group \
	--launch-configuration-name web-server-auto-scaling-group --load-balancer-names load-balancer \
	--health-check-type ELB --health-check-grace-period 300 --min-size 2 --max-size 2 \
	--vpc-zone-identifier "subnet-111e3459,subnet-14c09b72,subnet-d141258b" \
	--target-group-arns "arn:aws:elasticloadbalancing:region:123456789012:targetgroup/my-targets/1234567890123456"

sleep 60

# Get the instances running in AWS in order to stop them
output=$(aws ec2 describe-instances)
instance_ids=$($output | grep "InstanceId" | awk '{print $2}' | cut -d"," -f1)
for instance_id in instance_ids;
do
	aws ec2 stop-instances --instance-ids ${instance_id}
done

sleep 300 # we wait for 5 min so the health check will re-launch the 2 EC2 instances


# Get the new instances running in AWS in order to terminate them
output=$(aws ec2 describe-instances)
instance_ids=$($output | grep "InstanceId" | awk '{print $2}' | cut -d"," -f1)
for instance_id in instance_ids;
do
        aws ec2 stop-instances --instance-ids ${instance_id}
done

sleep 300


# After waiting for 5 more minutes, the 2 instances will be re-deployed.
# We need to disable the auto-scaling process "LAUNCH" and terminate the instances again
aws autoscaling suspend-processes --auto-scaling-group-name web-server-auto-scaling-group --scaling-processes Launch
output=$(aws ec2 describe-instances)
instance_ids=$($output | grep "InstanceId" | awk '{print $2}' | cut -d"," -f1)
for instance_id in instance_ids;
do
        aws ec2 stop-instances --instance-ids ${instance_id}
done

sleep 60

output=$(aws ec2 describe-instances | grep "running")
if [ -z "$output" ];
then
	echo "[ERROR] There has been an error as there is still some instance running in EC2."
else
	echo "All instances have been correctly terminated."
fi