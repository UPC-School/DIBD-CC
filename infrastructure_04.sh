#!/bin/sh
set -e

randbytes () {
    head -c 8 /dev/urandom | xxd -p
}

unquote () {
    cut -d '"' -f 2
}

# Take parameters from environment or use defaults
AUTO_SCALING_GROUP_NAME=${AUTO_SCALING_GROUP_NAME-auto-scaling-group-$(randbytes)}
MINIMUM_GROUP_SIZE=${MINIMUM_GROUP_SIZE-2}
MAXIMUM_GROUP_SIZE=${MAXIMUM_GROUP_SIZE-2}
DESIRED_GROUP_CAPACITY=${DESIRED_GROUP_CAPACITY-$MINIMUM_GROUP_SIZE}
DEFAULT_GROUP_COOLDOWN=${DEFAULT_GROUP_COOLDOWN-300}
TARGET_AUTOSCALING_CPU=${TARGET_AUTOSCALING_CPU-70}
LAUNCH_CONFIGURATION_NAME=${LAUNCH_CONFIGURATION_NAME-launch-configuration-$(randbytes)}
IMAGE_NAME=${IMAGE_NAME-test-web-server-version-1.0}
KEY_NAME=${KEY_NAME-my-ec2-keypair}
TARGET_GROUP_NAME=${TARGET_GROUP_NAME-target-group-$(randbytes)}
SCALING_POLICY_NAME=${SCALING_POLICY_NAME-scaling-policy-$(randbytes)}
LOAD_BALANCER_NAME=${LOAD_BALANCER_NAME-load-balancer-$(randbytes)}
SECURITY_GROUP_NAME=${SECURITY_GROUP_NAME-web-sg-$(randbytes)}
LOAD_BALANCER_SECURITY_GROUP_NAME=${LOAD_BALANCER_SECURITY_GROUP_NAME-load-balancer-sg-$(randbytes)}
SNS_TOPIC_NAME=${SNS_TOPIC_NAME-scaling-topic-$(randbytes)}
SNS_EMAIL_NOTIFICATIONS=${SNS_EMAIL_NOTIFICATIONS-"david.carrera@est.fib.upc.edu"}

echo "Fetching corresponding ImageId..."
image_id=$(aws ec2 describe-images \
               --owners self \
               --filters=Name=name,Values=$IMAGE_NAME \
               --query "Images[0].ImageId" |
               unquote)

echo "Fetching VpcId..."
vpc_id=$(aws ec2 describe-vpcs \
         --no-paginate \
         --query "Vpcs[0].VpcId" |
             unquote)

echo "Fetching vpc subnets..."
vpc_subnets=$(aws ec2 describe-subnets \
                  --no-paginate \
                  --query "Subnets[*].SubnetId" |
                  sed 's/^[ \t]*"//;s/"//' |
                  tr -d '\n' |
                  tail -c +2 | head -c -1)

echo "Creating security group $LOAD_BALANCER_SECURITY_GROUP_NAME for load balancer..."
load_balancer_security_group_id=$(aws ec2 create-security-group \
                                      --description "Load balancer security group" \
                                      --group-name $LOAD_BALANCER_SECURITY_GROUP_NAME \
                                      --vpc-id $vpc_id \
                                      --query GroupId |
                                      unquote)

echo "Authorizing security group for load balancer..."
aws ec2 authorize-security-group-ingress \
    --group-id $load_balancer_security_group_id \
    --ip-permissions IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges="[{CidrIp=0.0.0.0/0}]"
aws ec2 authorize-security-group-ingress \
    --group-id $load_balancer_security_group_id \
    --ip-permissions IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges="[{CidrIp=0.0.0.0/0}]"

echo "Creating security group $SECURITY_GROUP_NAME for web..."
security_group_id=$(aws ec2 create-security-group \
                        --description "Web security group" \
                        --group-name $SECURITY_GROUP_NAME \
                        --vpc-id $vpc_id \
                        --query GroupId |
                        unquote)

echo "Authorizing security group for web..."
aws ec2 authorize-security-group-ingress \
    --group-id $security_group_id \
    --ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges="[{CidrIp=$(dig +short myip.opendns.com @resolver1.opendns.com)/32}]"
aws ec2 authorize-security-group-ingress \
    --group-id $security_group_id \
    --ip-permissions IpProtocol=tcp,FromPort=80,ToPort=80,UserIdGroupPairs="[{GroupId=$load_balancer_security_group_id}]"

echo "Creatig launch configuration $LAUNCH_CONFIGURATION_NAME..."
aws autoscaling create-launch-configuration \
    --launch-configuration-name $LAUNCH_CONFIGURATION_NAME \
    --image-id $image_id \
    --key-name $KEY_NAME \
    --security-groups $security_group_id \
    --instance-type t2.micro \
    --instance-monitoring "Enabled=false" \
    --block-device-mappings "
[
        {
                \"DeviceName\": \"/dev/sda1\",
                \"Ebs\": {
                        \"VolumeSize\": 8,
                        \"VolumeType\": \"gp2\",
                        \"DeleteOnTermination\": true
                }
        }
]"

echo "Creatig the target group $TARGET_GROUP_NAME..."
target_group_arn=$(aws elbv2 create-target-group \
                       --name $TARGET_GROUP_NAME \
                       --protocol HTTP \
                       --port 80 \
                       --vpc-id $vpc_id \
                       --target-type instance \
                       --query "TargetGroups[0].TargetGroupArn" |
                       unquote)

echo "Creating load balancer $LOAD_BALANCER_NAME..."
load_balancer_arn=$(echo $vpc_subnets |
                        sed 's/,/ /g' |
                        xargs aws elbv2 create-load-balancer \
                              --name $LOAD_BALANCER_NAME \
                              --security-groups $load_balancer_security_group_id \
                              --scheme internet-facing \
                              --tags \
                              "Key=Cost-center,Value=laboratory" \
                              "Key=Project,Value=ccbda bootstrap" \
                              --type application \
                              --ip-address-type ipv4 \
                              --query LoadBalancers[0].LoadBalancerArn \
                              --subnets)
load_balancer_arn=$(echo $load_balancer_arn | unquote)

echo "Creating load balancer HTTP listener..."
aws elbv2 create-listener \
    --load-balancer-arn $load_balancer_arn \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=$target_group_arn > /dev/null

echo "Generating self-signed certificate..."
certificate_file=$(mktemp)
certificate_private_key_file=$(mktemp)
openssl req \
        -x509 \
        -newkey \
        rsa:2048 \
        -keyout $certificate_private_key_file \
        -out $certificate_file \
        -days 365 \
        -nodes \
        -subj "/C=ES/CN=myserver.info"

echo "Importing certificate..."
https_certificate_arn=$(aws acm import-certificate \
                            --certificate "$(cat $certificate_file)" \
                            --private-key "$(cat $certificate_private_key_file)" \
                            --query CertificateArn |
                            unquote)
rm -f $certificate_file
rm -f $certificate_private_key_file

echo "Creating load balancer HTTPS listener"
aws elbv2 create-listener \
    --load-balancer-arn $load_balancer_arn \
    --protocol HTTPS \
    --port 443 \
    --certificates CertificateArn=$https_certificate_arn \
    --ssl-policy ELBSecurityPolicy-TLS-1-2-2017-01 \
    --default-actions Type=forward,TargetGroupArn=$target_group_arn > /dev/null

echo "Creating auto scaling group $AUTO_SCALING_GROUP_NAME..."
aws autoscaling create-auto-scaling-group \
    --auto-scaling-group-name $AUTO_SCALING_GROUP_NAME \
    --launch-configuration-name $LAUNCH_CONFIGURATION_NAME \
    --min-size $MINIMUM_GROUP_SIZE \
    --max-size $MAXIMUM_GROUP_SIZE \
    --desired-capacity $DESIRED_GROUP_CAPACITY \
    --default-cooldown $DEFAULT_GROUP_COOLDOWN \
    --target-group-arns $target_group_arn \
    --health-check-type ELB \
    --health-check-grace-period 300 \
    --tags \
    "Key=Cost-center,Value=laboratory,PropagateAtLaunch=true" \
    "Key=Project,Value=ccbda bootstrap,PropagateAtLaunch=true" \
    --vpc-zone-identifier $vpc_subnets

echo "Creating auto scaling policy $SCALING_POLICY_NAME..."
aws autoscaling put-scaling-policy \
    --auto-scaling-group-name $AUTO_SCALING_GROUP_NAME \
    --policy-name $SCALING_POLICY_NAME \
    --policy-type TargetTrackingScaling \
    --target-tracking-configuration "
{
        \"PredefinedMetricSpecification\": {
                \"PredefinedMetricType\": \"ASGAverageCPUUtilization\"
        },
        \"TargetValue\": $TARGET_AUTOSCALING_CPU
}" > /dev/null

echo "Creating new notification topic $SNS_TOPIC_NAME..."
sns_topic_arn=$(aws sns create-topic \
                --name $SNS_TOPIC_NAME \
                --query TopicArn |
                    unquote)

echo "Subscribing to topic..."
aws sns subscribe \
    --topic-arn $sns_topic_arn \
    --protocol email \
    --notification-endpoint $SNS_EMAIL_NOTIFICATIONS > /dev/null

echo "Creating notification for auto scaling group..."
aws autoscaling put-notification-configuration \
    --auto-scaling-group-name $AUTO_SCALING_GROUP_NAME \
    --topic-arn $sns_topic_arn \
    --notification-types \
    "autoscaling:EC2_INSTANCE_LAUNCH" \
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR" \
    "autoscaling:EC2_INSTANCE_TERMINATE" \
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR"

echo "All done."