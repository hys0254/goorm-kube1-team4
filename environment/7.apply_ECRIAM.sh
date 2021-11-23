#/bin/bash

CLUSTER_NAME=`eksctl get cluster --output json | jq -r '.[0].metadata.name'`
AWS_REGION=`eksctl get cluster --output json | jq -r '.[0].metadata.region'`
VPC_ID=`eksctl get cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --output json | jq -r '.[0].ResourcesVpcConfig.VpcId'`
NG_ROLE=`kubectl -n kube-system describe configmap aws-auth | grep rolearn`
ACCOUNT=${NG_ROLE:24:12}

INS_NUM=`aws iam list-roles | jq '.[][].RoleName' | grep NodeInstanceRole | wc -l`
for ((i=1; i<=${INS_NUM}; i++)); do
INS_ROLENAME=`aws iam list-roles | jq -r '.[][].RoleName' | grep nodegroup | sed -n ${i}p`
aws iam attach-role-policy \
 --role-name ${INS_ROLENAME} \
 --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess
echo ${i}'번째 Node ECR-Node 권한 연결 성공'
done
