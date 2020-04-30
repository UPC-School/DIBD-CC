#!/bin/bash

set $AWS_ACCOUNT = 610237208110

aws elbv2 create-load-balancer \
--name load-balancer \
--scheme internet-facing \
--subnets subnet-0613775c subnet-5acc973c subnet-c8351f80 \
--type application \
--security-groups load-balancer-sg\
--tags Key="Project",Value="ccbda bootstrap" Key="Cost-center",Value="laboratory"

aws elbv2 create-target-group \
--name primary-apache-web-server-target \
--protocol HTTP \
--port 80 \
--vpc-id vpc-fbbe5782 \
--target-type instance

aws elbv2 register-targets \
--target-group-arn arn:aws:elasticloadbalancing:eu-west-1:${AWS_ACCOUNT}:targetgroup/primary-apache-web-server-target/6ea8084a866381d0 \
--targets Id=i-093cf78de689790a2

aws elbv2 create-listener \
--load-balancer-arn arn:aws:elasticloadbalancing:eu-west-1:${AWS_ACCOUNT}:loadbalancer/app/load-balancer/75204be6712079a4
--protocol HTTP \
--port 80 \
--ssl-policy ELBSecurityPolicy-TLS-1-2-2017-01 \
--certificates arn:aws:iam::${AWS_ACCOUNT}:server-certificate/myserver.info