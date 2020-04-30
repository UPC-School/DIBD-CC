
aws iam create-role
role-name serverless-controller-role \

aws iam attach-role-policy
--policy-arn arn:aws:iam::610237208110:policy/service-role/AWSLambdaMicroserviceExecutionRole-d89a21df-b628-49d8-9a53-e4358bb71700 \

zip function.zip lambda_function.py

aws lambda create-function \
--function-name serverless-controller \
--runtime python3.7
--role arn:aws:iam::610237208110:role/service-role/serverless-controller-role
--zip-file fileb://funtion.zip \
--handler lambda_function.lambda_handler \

aws apigateway create-rest-api
--name serverless-controller-API \
--tags Key="Project",Value="ccbda bootstrap" Key="Cost-center",Value="laboratory"

aws s3 mb s3://lab6

aws s3 cp script.js s3://lab6 --acl public-read
aws s3 cp index.html s3://lab6 --acl public-read
aws s3 cp styles.css s3://lab6 --acl public-read