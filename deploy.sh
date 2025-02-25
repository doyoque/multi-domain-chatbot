#!/bin/bash

set -e  # Exit on any error

# --- CONFIGURATION ---
STACK_NAME="ChatbotLambdaStack"
BUCKET_NAME="my-chatbot-bucket-$(aws sts get-caller-identity --query Account --output text)"
LAMBDA_ZIP="chatbot.zip"
LAMBDA_FUNCTION_NAME="ChatbotLambda"
CF_TEMPLATE="infra/cloudformation.yml"

export AWS_PAGER=""

# 1. Check if the bucket exists, create if not
echo "Checking if bucket '$BUCKET_NAME' exists..."
if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "Bucket does not exist. Creating bucket: $BUCKET_NAME"
  aws s3 mb "s3://$BUCKET_NAME"
else
  echo "Bucket $BUCKET_NAME already exists. Skipping creation."
fi

# 2. Package Lambda function with dependencies
echo "Packaging Lambda function..."
cd lambda

# Install dependencies into a `package/` directory
rm -rf package && mkdir package
pip3 install --target ./package -r requirements.txt

# Zip the package folder first, then add the chatbot script
cd package
zip -r9 ../../$LAMBDA_ZIP .
cd ..
zip -g ../$LAMBDA_ZIP chatbot.py
cd ..

echo "Lambda function packaged successfully."

# 3. Upload the code to S3
echo "Uploading $LAMBDA_ZIP to s3://$BUCKET_NAME/$LAMBDA_ZIP"
aws s3 cp $LAMBDA_ZIP "s3://$BUCKET_NAME/$LAMBDA_ZIP"

# 4. Deploy the CloudFormation stack (Update if exists)
echo "Deploying CloudFormation stack: $STACK_NAME"

if aws cloudformation describe-stacks --stack-name $STACK_NAME &>/dev/null; then
  echo "Stack already exists, updating..."
  aws cloudformation update-stack \
    --stack-name $STACK_NAME \
    --template-body file://$CF_TEMPLATE \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=S3Bucket,ParameterValue=$BUCKET_NAME \
    --no-cli-pager
  echo "Waiting for stack update to complete..."
  aws cloudformation wait stack-update-complete --stack-name $STACK_NAME
else
  echo "Stack does not exist, creating..."
  aws cloudformation create-stack \
    --stack-name $STACK_NAME \
    --template-body file://$CF_TEMPLATE \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=S3Bucket,ParameterValue=$BUCKET_NAME \
    --no-cli-pager
  echo "Waiting for stack creation to complete..."
  aws cloudformation wait stack-create-complete --stack-name $STACK_NAME
fi

echo "Stack deployment finished."

# 5. Fetch API Gateway Invoke URL
echo "Fetching API Gateway URL..."
CHATBOT_API_URL=$(aws cloudformation describe-stacks --stack-name $STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='ChatbotApiGatewayInvokeURL'].OutputValue" --output text)

if [[ -z "$CHATBOT_API_URL" ]]; then
  echo "Error: API Gateway URL not found. Check CloudFormation stack."
  exit 1
fi

# 6. Test API Gateway
echo "Testing chatbot API Gateway..."
curl -s -X POST "$CHATBOT_API_URL" -d '{"query": "What is the weather in London,uk?"}' -H "Content-Type: application/json" | jq .

echo "Deployment completed successfully!"
echo "Chatbot API Gateway URL: $CHATBOT_API_URL"
