#!/bin/bash

# Create the web server
aws ec2 run-instances   --image-id ami-0422debc396704918 \
                        --count 1 --instance-type t2.micro \
                        --key-name NewKeyPairEurope \
                        --security-group-ids sg-037e4ebc7a1d46a5e \
                        --subnet-id subnet-ecd58c8a

#Create the load balancer
aws elb create-load-balancer \
                        --load-balancer-name load-balancer \
                        --listeners "Protocol=HTTP,LoadBalancerPort=80,InstanceProtocol=HTTP,InstancePort=80"\
                                    "Protocol=HTTPS,LoadBalancerPort=443,InstanceProtocol=HTTP,InstancePort=80,SSLCertificateId= arn:aws:acm:eu-west-1:366557250991:certificate/6d751545-b899-4579-b1eb-939eb180264f"\
                        --subnets subnet-ecd58c8a subnet-9d361ed5 subnet-a28913f8 \
                        --security-groups sg-07eb2333f459f346a
# Register the instance in the load balancer
aws elb register-instances-with-load-balancer \
                        --load-balancer-name load-balancer \
                        --instances i-0fe8de4d4034ba947

#Create the autoscaling group
aws autoscaling create-auto-scaling-group \
                        --auto-scaling-group-name web-server-auto-scaling-group \
                        --launch-configuration-name web-server-auto-scaling-configuration \
                        --load-balancer-names load-balancer \
                        --min-size 2 \
                        --max-size 2 \
                        --vpc-zone-identifier "subnet-ecd58c8a,subnet-9d361ed5,subnet-a28913f8" \
                        --target-group-arns "arn:aws:elasticloadbalancing:eu-west-1:366557250991:targetgroup/primary-apache-web-server-target/1e07db587e4ea509"