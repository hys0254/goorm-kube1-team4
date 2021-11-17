#/bin/bash

# 클러스터 스택 삭제 직전, 리소스 삭제용 
## 스택 이름 얻기
ALBStackName=`aws cloudformation list-stacks --stack-status-filter "CREATE_COMPLETE" --query='StackSummaries[].StackName' --output json | jq -r '.[]' | grep 'aws-load-balancer-controller'`
EBSStackName=`aws cloudformation list-stacks --stack-status-filter "CREATE_COMPLETE" --query='StackSummaries[].StackName' --output json | jq -r '.[]' | grep 'ebs-csi-controller-sa'`
# EFSStackName=`aws cloudformation list-stacks --stack-status-filter "CREATE_COMPLETE" --query='StackSummaries[].StackName' --output json | jq -r '.[]' | grep 'efs-csi-controller-sa'`
DNSStackName=`aws cloudformation list-stacks --stack-status-filter "CREATE_COMPLETE" --query='StackSummaries[].StackName' --output json | jq -r '.[]' | grep 'external-dns'`

echo 'ALBStackName : '${ALBStackName}
echo 'EBSStackName : '${EBSStackName}
# echo 'EFSStackName : '${EFSStackName}
echo 'DNSStackName : '${DNSStackName}

## ARN 정보 얻기
ALBARN=`aws cloudformation describe-stacks --stack-name ${ALBStackName} --query='Stacks[].Outputs[?OutputKey==\`Role1\`].OutputValue' --output json | jq -r '.[0] | .[0]'`
EBSARN=`aws cloudformation describe-stacks --stack-name ${EBSStackName} --query='Stacks[].Outputs[?OutputKey==\`Role1\`].OutputValue' --output json | jq -r '.[0] | .[0]'`
# EFSARN=`aws cloudformation describe-stacks --stack-name ${EFSStackName} --query='Stacks[].Outputs[?OutputKey==\`Role1\`].OutputValue' --output json | jq -r '.[0] | .[0]'`
DNSARN=`aws cloudformation describe-stacks --stack-name ${DNSStackName} --query='Stacks[].Outputs[?OutputKey==\`Role1\`].OutputValue' --output json | jq -r '.[0] | .[0]'`
echo 'ALBARN : '${ALBARN}
echo 'EBSARN : '${EBSARN}
# echo 'EFSARN : '${EFSARN}
echo 'DNSARN : '${DNSARN}

## RoleName 얻는 명령문 개별적으로 실행해 볼 땐, 감싸고 있는 ``를 제거하고 OutputKey=='Role1' 으로 수정하고 해야됩니다!
ALBRoleName=`aws cloudformation describe-stacks --stack-name ${ALBStackName} --query='Stacks[].Outputs[?OutputKey==\`Role1\`].OutputValue' --output json | jq -r '.[0] | .[0]' | cut -f 2 -d "/"`
EBSRoleName=`aws cloudformation describe-stacks --stack-name ${EBSStackName} --query='Stacks[].Outputs[?OutputKey==\`Role1\`].OutputValue' --output json | jq -r '.[0] | .[0]' | cut -f 2 -d "/"`
# EFSRoleName=`aws cloudformation describe-stacks --stack-name ${EFSStackName} --query='Stacks[].Outputs[?OutputKey==\`Role1\`].OutputValue' --output json | jq -r '.[0] | .[0]' | cut -f 2 -d "/"`
DNSRoleName=`aws cloudformation describe-stacks --stack-name ${DNSStackName} --query='Stacks[].Outputs[?OutputKey==\`Role1\`].OutputValue' --output json | jq -r '.[0] | .[0]' | cut -f 2 -d "/"`
echo 'ALBRoleName : '${ALBRoleName}
echo 'EBSRoleName : '${EBSRoleName}
# echo 'EFSRoleName : '${EFSRoleName}
echo 'DNSRoleName : '${DNSRoleName}

echo '>>>> Delete Resources Start '
# 단계 1 - ArgoCD 자원 삭제
echo '>> Delete ArgoCD'
kubectl delete clusterrolebinding default-admin
kubectl delete -f ArgoCD/ingress.yaml
echo ''
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
echo ''
kubectl delete namespace argocd

# 단계 2 - Jenkins 자원 삭제
echo '>> Delete Jenkins'
helm uninstall jenkins -n jenkins

kubectl delete -f Jenkins/jenkins-sa.yaml -f Jenkins/jenkins-pvc.yaml

# 단계 3 - External_DNS 리소스 삭제
kubectl delete -f EX_DNS/external-dns-account.yaml

# 단계 4 - csi 드라이버 관련 리소스 삭제
echo '> Step 1 : Delete EBS-Driver Resource Start '
## kubernetes 리소스 삭제
echo '>> delete storageclass.yaml'
kubectl delete -f CSI/EFS/storageclass.yaml -f CSI/EFS/driver.yaml -f CSI/EFS/efs-service-account.yaml

echo '>> delete EBS-csi-controller '
kubectl delete -k CSI/EBS/aws-ebs-csi-driver/deploy/kubernetes/base/

# 단계 5 - alb 드라이버 관련 리소스 삭제
echo '> Step 2 : Delete ALB Resource Start '
## kubernetes alb controller deployment 삭제
kubectl delete -f ALB/v2_2_0_full.yaml

kubectl delete -f https://github.com/jetstack/cert-manager/releases/download/v1.1.1/cert-manager.yaml
echo '>>>> Delete Resources Finished '

# 단계 6 - 스택 삭제
echo '>> Delete Resources stack Start'
`aws cloudformation delete-stack --stack-name "${DNSStackName}" --role-arn "${DNSARN}"`
# aws cloudformation delete-stack --stack-name ${EFSStackName} --role-arn ${EFSARN}
`aws cloudformation delete-stack --stack-name "${EBSStackName}" --role-arn "${EBSARN}"`
`aws cloudformation delete-stack --stack-name "${ALBStackName}" --role-arn "${ALBARN}"`

# 단계 5 - EBS, ALB 관련 폴더 삭제
echo '> Step 3 : Delete Download Resources associated with ArgoCD, Jenkins, EX_DNS, EBS, ALB <'
rm -rf ArgoCD
rm -rf Jenkins
rm -rf EX_DNS
rm -rf CSI
rm -rf ALB

echo '>> Delete Resource, Stack Finished -> Delete Cluster Able'
