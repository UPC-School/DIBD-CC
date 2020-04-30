import json
import uuid

import boto3

api_gateway_client = boto3.client('apigatewayv2')


def create_policy(iam_client) -> str:
    dynamo_policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "dynamodb:DeleteItem",
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:Scan",
                    "dynamodb:UpdateItem"
                ],
                "Resource": ("arn:aws:dynamodb:%s:%s:table/shopping-list" % (region, account_id))
            }
        ]
    }
    policy_name = 'lambda-dynamo-db-shopping-list'
    try:
        response = iam_client.create_policy(
            PolicyName=policy_name,
            PolicyDocument=json.dumps(dynamo_policy),
            Description='Policy document to get and update items in shopping list table'
        )
    except Exception as error:
        if error.response['Error']['Code'] == 'EntityAlreadyExists':
            policies_response = iam_client.list_policies(Scope='Local')
            for policy in policies_response['Policies']:
                if policy['PolicyName'] == policy_name:
                    return policy['Arn']
        print(error)

    return response['Policy']['Arn']


def create_role_for_lambda(iam_client, role_name: str) -> str:
    try:
        response = iam_client.create_role(
            RoleName=role_name,
            AssumeRolePolicyDocument=json.dumps({
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "lambda.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            }),
            Description='Role to be used by lambda for accessing DynamoDB',
            Tags=[
                {
                    'Key': 'CreatedBy',
                    'Value': 'PythonScript'
                },
            ]
        )
    except Exception as error:
        if error.response['Error']['Code'] == 'EntityAlreadyExists':
            response = iam_client.get_role(RoleName=role_name)
        else:
            print(error)

    return response['Role']['Arn']


def create_api(target_lambda_arn: str):
    response = api_gateway_client.create_api(
        CorsConfiguration={
            'AllowHeaders': [
                '*',
            ],
            'AllowMethods': [
                '*',
            ],
            'AllowOrigins': [
                '*',
            ],
        },
        Description='API Gateway to expose Lambda',
        Name='shopping-list-api',
        RouteKey='ANY /shopping-list',
        ProtocolType='HTTP',
        Tags={
            'CreatedBy': 'PythonScript'
        },
        Target=target_lambda_arn,
    )
    return response['ApiId'], response['ApiEndpoint']


def create_lamda(role: str):
    client = boto3.client('lambda')
    function_name = 'shopping-list-controller'
    try:
        client.delete_function(FunctionName=function_name)
    except Exception as e:
        print(e)
    with open('lamda_code.zip', 'rb') as code:
        zip_data = code.read()
    response = client.create_function(
        FunctionName=function_name,
        Runtime='python3.7',
        Role=role,
        Handler='lamda_code.lambda_handler',
        Code={
            'ZipFile': zip_data
        },
        Description='controller for shopping list',
        Timeout=60,
        Publish=True,
        Tags={
            'CreatedBy': 'PythonScript'
        }
    )
    return response['FunctionArn']


def permit_api_to_invoke_lambda(function_arn, api_id):
    client = boto3.client('lambda')
    response = client.add_permission(
        FunctionName=function_arn,
        StatementId=str(uuid.uuid4()),
        Action="lambda:InvokeFunction",
        Principal='apigateway.amazonaws.com',
        SourceArn="arn:aws:execute-api:%s:%s:%s/*/*/shopping-list" % (region, account_id, api_id),
    )
    return response


if __name__ == '__main__':
    lambda_execution_role = 'lambda-dynamo-shopping'
    region = boto3.session.Session().region_name
    account_id = boto3.client('sts').get_caller_identity().get('Account')
    iam_client = boto3.client('iam')
    role_arn = create_role_for_lambda(iam_client, lambda_execution_role)
    policy_arn = create_policy(iam_client)
    response = iam_client.attach_role_policy(
        RoleName=lambda_execution_role,
        PolicyArn=policy_arn
    )
    function_arn = create_lamda(role_arn)

    api_id, end_point = create_api(function_arn)
    permit_api_to_invoke_lambda(function_arn, api_id)
    print("Lambda can be accessed from: ", end_point + "/shopping-list")