#!/bin/bash

answer=$(aws lambda create-function \
                --function-name serverless-2 \
                --runtime python3.7 \
                --role arn:aws:iam::366557250991:role/service-role/serverless-controller-role \
                --handler lambda_function.lambda_handler \
                --zip-file fileb:///home/ricardohb/Documents/CC/lab6/CLOUD-COMPUTING-CLASS-2020-Lab6/lambda_function.zip)

lambda_arn=$(echo $answer | jq -r '.FunctionArn')

sleep 30

answer=$(aws apigatewayv2 create-api \
                --cors-configuration AllowOrigins="*" \
                --name apigateway-serverless-2 \
                --protocol-type HTTP \
                --target $lambda_arn)

ApiId=$(echo $answer | jq -r '.ApiId')

sleep 30

aws lambda add-permission \
                --function-name serverless-2 \
                --statement-id apigateway-serverless-2-permission \
                --action "lambda:InvokeFunction" \
                --principal 'apigateway.amazonaws.com' \
                --source-arn "arn:aws:execute-api:eu-west-1:366557250991:$ApiId/*/*/shopping-list"