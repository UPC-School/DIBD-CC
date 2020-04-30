#!/bin/bash

# Create the execution role needed to access AWS resources. trust-policy.json is a file located in the same folder
# as this script.
aws iam create-role --role-name lambda-ex --assume-role-policy-document file://trust-policy.json

# OR it can be replaced by the two following lines, thus avoiding the use of the json file
#aws iam create-role --role-name lambda-ex --assume-role-policy-document '{"Version": "2012-10-17","Statement": [{ "Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}'
#aws iam attach-role-policy --role-name lambda-ex --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole


# Create a zip file with the python code
zip function.zip lambda_api.py


# Create the lambda function
aws lambda create-function --function-name serverless-controller \
--zip-file fileb://function.zip --handler lambda_function.lambda_handler --runtime python3.7 \
--role arn:aws:iam::123456789012:role/lambda-ex


# Invoke the lambda function
output=$(aws lambda invoke --function-name serverless-controller out --log-type Tail)
endpoint=$($output | grep "Location" | awk '{print $2}')

# Open firefox for 60 seconds with the endpoint returned to check that
# it works
timeout 60 firefox $endpoint


# Create an S3 bucket
aws s3 mb s3://lab6-ccbda

aws s3 cp script.js s3://lab6-ccbda --acl public-read
aws s3 cp index.html s3://lab6-ccbda --acl public-read
aws s3 cp styles.css s3://lab6-ccbda --acl public-read

# After enabling website hosting by using the Amazon S3 console and obtaining the endpoint in ${BUCKET_ENDPOINT}

firefox ${BUCKET_ENDPOINT} &

# once it opens, we can play with the APIs as we did in the lab