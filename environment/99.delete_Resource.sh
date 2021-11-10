#/bin/bash

# 클러스터 스택 삭제 직전, 리소스 삭제용 
## 스택 이름 얻기
ALBStackName=`aws cloudformation list-stacks --stack-status-filter "CREATE_COMPLETE" --query='StackSummaries[].StackName' --output json | jq -r '.[]' | grep 'aws-load-balancer-controller'`
CSIStackName=`aws cloudformation list-stacks --stack-status-filter "CREATE_COMPLETE" --query='StackSummaries[].StackName' --output json | jq -r '.[]' | grep 'ebs-csi-controller-sa'`

## RoleName 얻는 명령문 개별적으로 실행해 볼 땐, 감싸고 있는 ``를 제거하고 OutputKey=='Role1' 으로 수정하고 해야됩니다!
ALBRoleName=`aws cloudformation describe-stacks --stack-name ${ALBStackName} --query='Stacks[].Outputs[?OutputKey==\`Role1\`].OutputValue' --output json | jq -r '.[0] | .[0]' | cut -f 2 -d "/"`
CSIRoleName=`aws cloudformation describe-stacks --stack-name ${CSIStackName} --query='Stacks[].Outputs[?OutputKey==\`Role1\`].OutputValue' --output json | jq -r '.[0] | .[0]' | cut -f 2 -d "/"`


echo '>>>> Delete Resources Start '

# 단계 1 - csi 드라이버 관련 리소스 삭제
echo '> Step 1 : Delete CSI-Driver Resource Start '
## kubernetes 리소스 삭제
echo '>> delete csi-controller '
kubectl delete -k CSI/aws-ebs-csi-driver/deploy/kubernetes/base/
## CSI Policy attach Role 삭제
echo '>> delete CSI Role '
aws iam delete-role --role-name ${CSIRoleName}
echo ' Delete CSI-Driver Resource Finished '

# 단계 2 - alb 드라이버 관련 리소스 삭제
echo '> Step 2 : Delete ALB Resource Start '
## kubernetes alb controller deployment 삭제
kubectl delete deployment -n kube-system aws-load-balancer-controller
## ALB Policy attach Role 삭제
echo '>> delete ALB Role '
aws iam delete-role --role-name ${ALBRoleName}
echo ' Delete ALB Resource Finished '

echo '>>>> Delete Resources Finished '

# 단계 3 - CSI, ALB 관련 폴더 삭제
echo '> Step 3 : Delete Download Resources associated with CSI, ALB <'
rm -rf CSI
rm -rf ALB

