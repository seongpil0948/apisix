STACK_NAME="stack-gw"
aws cloudformation create-stack --stack-name  \
  --template-body file://template.yaml \
  --parameters ParameterKey=AMIId,ParameterValue=ami-0abcd1234efgh5678 \
               ParameterKey=VPC,ParameterValue=vpc-0123456789abcdef \
               ParameterKey=Subnets,ParameterValue="subnet-12345abcde,subnet-67890fghij" \
               ParameterKey=HostedZoneId,ParameterValue=Z1234567890ABC
