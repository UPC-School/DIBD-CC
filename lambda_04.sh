#!/bin/sh
set -e

randbytes () {
    head -c 8 /dev/urandom | xxd -p
}

unquote () {
    cut -d '"' -f 2
}

# Take parameters from environment or use defaults
HTML_FILE=${HTML_FILE-index.html}
CSS_FILE=${CSS_FILE-styles.css}
JSCRIPT_FILE=${JSCRIPT_FILE-script.js}
LAMBDA_ZIP_FILE=${LAMBDA_ZIP_FILE-lambda.zip}
LAMBDA_HANDLER=${LAMBDA_CODE_FILE-lambda.lambda_handler}
TABLE_NAME=${TABLE_NAME-shopping-list-$(randbytes)}
FIELD_NAME=${FIELD_NAME-thingid}
LAMBDA_NAME=${LAMBDA_NAME-serverless-controller-$(randbytes)}
EXECUTION_ROLE_NAME=${EXECUTION_ROLE_NAME-serverless-controller-role-$(randbytes)}
API_NAME=${API_NAME-serverless-controller-API-$(randbytes)}
BUCKET_NAME=${BUCKET_NAME-static-website-bucket-ccbda-lab06-$(randbytes)}

echo "Fetching default region..."
region=$(aws configure get region)

echo "Fetching account id..."
account_id=$(aws sts get-caller-identity --query Account | unquote)

echo "Creating dynamodb table $TABLE_NAME..."
table_arn=$(aws dynamodb create-table \
                --attribute-definitions "AttributeName=$FIELD_NAME,AttributeType=S" \
                --table-name $TABLE_NAME \
                --key-schema "AttributeName=$FIELD_NAME,KeyType=HASH" \
                --provisioned-throughput "ReadCapacityUnits=5,WriteCapacityUnits=5" \
                --tags \
                "Key=Cost-center,Value=laboratory" \
                "Key=Project,Value=ccbda serverless" \
                --query TableDescription.TableArn |
                unquote)

echo "Creating log group..."
aws logs create-log-group \
    --log-group-name /aws/lambda/$LAMBDA_NAME
log_arn=$(aws logs describe-log-groups \
              --log-group-name-prefix /aws/lambda/$LAMBDA_NAME \
              --query "logGroups[0].arn" |
              unquote)

echo "Creating execution role $EXECUTION_ROLE_NAME..."
role_arn=$(aws iam create-role \
    --path /service-role/ \
    --role-name $EXECUTION_ROLE_NAME \
    --assume-role-policy-document "{
\"Version\": \"2012-10-17\",
\"Statement\":
[
        {
                \"Effect\": \"Allow\",
                \"Principal\":
                {
                        \"Service\": \"lambda.amazonaws.com\"
                },
                \"Action\": \"sts:AssumeRole\"
        }
]}" \
    --query "Role.Arn" |
               unquote)

echo "Waiting ten seconds to make sure role is actually created..."
sleep 10

echo "Creating lambda function $LAMBDA_NAME..."
lambda_arn=$(aws lambda create-function \
                 --function-name $LAMBDA_NAME \
                 --runtime python3.7 \
                 --role $role_arn \
                 --handler $LAMBDA_HANDLER \
                 --publish \
                 --tags "Cost-center=laboratory,Project=ccbda serverless" \
                 --zip-file fileb://$LAMBDA_ZIP_FILE \
                 --query FunctionArn |
                 unquote)

echo "Creating Lambda Basic Execution Role policy"
basic_policy_arn=$(aws iam create-policy \
                       --policy-name AWSLambdaBasicExecutionRole-$(randbytes) \
                       --path /service-role/ \
                       --policy-document "{
\"Version\": \"2012-10-17\",
\"Statement\":
[
        {
                \"Effect\": \"Allow\",
                \"Action\": \"logs:CreateLogGroup\",
                \"Resource\": \"arn:aws:logs:eu-west-1:690323806957:*\"
        },
        {
                \"Effect\": \"Allow\",
                \"Action\":
                [
                        \"logs:CreateLogStream\",
                        \"logs:PutLogEvents\"
                ],
                \"Resource\":
                [
                        \"$log_arn\"
                ]
        }
]}" \
                       --query Policy.Arn |
                       unquote)

echo "Creating Lambda Microservice Execution Role policy"
microservice_policy_arn=$(aws iam create-policy \
                              --policy-name AWSLambdaMicroserviceExecutionRole-$(randbytes) \
                              --path /service-role/ \
                              --policy-document "{
\"Version\": \"2012-10-17\",
\"Statement\":
[
        {
                \"Effect\": \"Allow\",
                \"Action\":
                [
                        \"dynamodb:DeleteItem\",
                        \"dynamodb:GetItem\",
                        \"dynamodb:PutItem\",
                        \"dynamodb:Scan\",
                        \"dynamodb:UpdateItem\"
                ],
                \"Resource\": \"$table_arn\"
        }
]}" \
                              --query Policy.Arn |
                              unquote)

echo "Attaching policies..."
aws iam attach-role-policy \
    --role-name $EXECUTION_ROLE_NAME \
    --policy-arn $basic_policy_arn
aws iam attach-role-policy \
    --role-name $EXECUTION_ROLE_NAME \
    --policy-arn $microservice_policy_arn

echo "Creating API $API_NAME..."
api_id=$(aws apigatewayv2 create-api \
             --name $API_NAME \
             --protocol-type HTTP \
             --query ApiId |
             unquote)

echo "Creating API integration..."
integration_id=$(aws apigatewayv2 create-integration \
                     --api-id $api_id \
                     --connection-type INTERNET \
                     --integration-method POST \
                     --integration-type AWS_PROXY \
                     --integration-uri "arn:aws:apigateway:$region:lambda:path/2015-03-31/functions/$lambda_arn/invocations" \
                     --payload-format-version 2.0 \
                     --query IntegrationId |
                     unquote)

echo "Creating API route..."
aws apigatewayv2 create-route \
    --api-id $api_id \
    --authorization-type NONE \
    --route-key "ANY /$LAMBDA_NAME" \
    --target "integrations/$integration_id" > /dev/null

echo "Creating API deployment..."
deployment_id=$(aws apigatewayv2 create-deployment \
                    --api-id $api_id \
                    --query DeploymentId |
                    unquote)

echo "Creating API stage..."
aws apigatewayv2 create-stage \
    --api-id $api_id \
    --auto-deploy \
    --default-route-settings "DetailedMetricsEnabled=false" \
    --deployment-id $deployment_id \
    --stage-name '$default' > /dev/null

echo "Adding lambda permission..."
aws lambda add-permission \
    --function-name $lambda_arn \
    --statement-id lambda-$(randbytes) \
    --action "lambda:InvokeFunction" \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:$region:$account_id:$api_id/*/*/$LAMBDA_NAME" > /dev/null

echo "Creating bucket for static website..."
aws s3api create-bucket \
    --bucket $BUCKET_NAME \
    --region $region \
    --create-bucket-configuration "LocationConstraint=$region" > /dev/null

echo "Copying files to bucket..."

# Replace apiUrl, tableName and possibly thingid in script
modified_script=$(mktemp)
cat $JSCRIPT_FILE | sed "s|apiUrl = 'https://YOUR-API-HOST/test/serverless-controller'|apiUrl = 'https://$api_id.execute-api.$region.amazonaws.com/$LAMBDA_NAME'|;s|tableName = 'shopping-list'|tableName = '$TABLE_NAME'|;s|thingid|$FIELD_NAME|g" > $modified_script

# Upload files
aws s3 cp $HTML_FILE s3://$BUCKET_NAME/index.html --acl public-read > /dev/null
aws s3 cp $CSS_FILE s3://$BUCKET_NAME/styles.css --acl public-read > /dev/null
aws s3 cp $modified_script s3://$BUCKET_NAME/script.js --acl public-read > /dev/null

# Cleanup
rm -f $modified_script

echo "Setting up website in bucket..."
aws s3api put-bucket-website \
    --bucket $BUCKET_NAME \
    --website-configuration "{
\"IndexDocument\": {
        \"Suffix\": \"index.html\"
}}"

echo "Tagging bucket..."
aws s3api put-bucket-tagging \
    --bucket $BUCKET_NAME \
    --tagging "TagSet=[{Key=Cost-center,Value=laboratory},{Key=Project,Value=ccbda serverless}]"

echo "All done."