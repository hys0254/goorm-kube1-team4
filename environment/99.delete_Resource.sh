#/bin/bash

CLUSTER_NAME=`eksctl get cluster --output json | jq -r '.[0].metadata.name'`
AWS_REGION=`eksctl get cluster --output json | jq -r '.[0].metadata.region'`
VPC_ID=`eksctl get cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --output json | jq -r '.[0].ResourcesVpcConfig.VpcId'`
NG_ROLE=`kubectl -n kube-system describe configmap aws-auth | grep rolearn`
ACCOUNT=${NG_ROLE:24:12}

# 클러스터 스택 삭제 직전, 리소스 삭제용 
## 스택 이름 얻기
ALBStackName=`aws cloudformation list-stacks --stack-status-filter "CREATE_COMPLETE" --query='StackSummaries[].StackName' --output json | jq -r '.[]' | grep 'aws-load-balancer-controller'`
EBSStackName=`aws cloudformation list-stacks --stack-status-filter "CREATE_COMPLETE" --query='StackSummaries[].StackName' --output json | jq -r '.[]' | grep 'ebs-csi-controller-sa'`
DNSStackName=`aws cloudformation list-stacks --stack-status-filter "CREATE_COMPLETE" --query='StackSummaries[].StackName' --output json | jq -r '.[]' | grep 'external-dns'`

echo 'ALBStackName : '${ALBStackName}
echo 'EBSStackName : '${EBSStackName}
echo 'DNSStackName : '${DNSStackName}

## ARN 정보 얻기
ALBARN=`aws cloudformation describe-stacks --stack-name ${ALBStackName} --query='Stacks[].Outputs[?OutputKey==\`Role1\`].OutputValue' --output json | jq -r '.[0] | .[0]'`
EBSARN=`aws cloudformation describe-stacks --stack-name ${EBSStackName} --query='Stacks[].Outputs[?OutputKey==\`Role1\`].OutputValue' --output json | jq -r '.[0] | .[0]'`
DNSARN=`aws cloudformation describe-stacks --stack-name ${DNSStackName} --query='Stacks[].Outputs[?OutputKey==\`Role1\`].OutputValue' --output json | jq -r '.[0] | .[0]'`
echo 'ALBARN : '${ALBARN}
echo 'EBSARN : '${EBSARN}
# echo 'EFSARN : '${EFSARN}
echo 'DNSARN : '${DNSARN}

## RoleName 얻는 명령문 개별적으로 실행해 볼 땐, 감싸고 있는 ``를 제거하고 OutputKey=='Role1' 으로 수정하고 해야됩니다!
ALBRoleName=`aws cloudformation describe-stacks --stack-name ${ALBStackName} --query='Stacks[].Outputs[?OutputKey==\`Role1\`].OutputValue' --output json | jq -r '.[0] | .[0]' | cut -f 2 -d "/"`
EBSRoleName=`aws cloudformation describe-stacks --stack-name ${EBSStackName} --query='Stacks[].Outputs[?OutputKey==\`Role1\`].OutputValue' --output json | jq -r '.[0] | .[0]' | cut -f 2 -d "/"`
DNSRoleName=`aws cloudformation describe-stacks --stack-name ${DNSStackName} --query='Stacks[].Outputs[?OutputKey==\`Role1\`].OutputValue' --output json | jq -r '.[0] | .[0]' | cut -f 2 -d "/"`
echo 'ALBRoleName : '${ALBRoleName}
echo 'EBSRoleName : '${EBSRoleName}
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

# 단계 3 - External_DNS 리소스, 스택 삭제
kubectl delete -f EX_DNS/external-dns-account.yaml

aws iam detach-role-policy --role-name ${DNSRoleName} --policy-arn arn:aws:iam::${ACCOUNT}:policy/AllowExternalDNSUpdates

aws cloudformation delete-stack --stack-name ${DNSStackName}
echo '======= Delete EX_DNS Stack Finished'
echo ''

# 단계 4 - EFS 드라이버 관련 리소스 삭제
## kubernetes 리소스 삭제
echo '>> delete storageclass.yaml'
kubectl delete -f CSI/EFS/storageclass.yaml -f CSI/EFS/driver.yaml -f CSI/EFS/efs-service-account.yaml

EFS_ATTACHARN=`aws iam get-role --role-name AmazonEKS_EFS_CSI_DriverRole | jq -r '.Role.AssumeRolePolicyDocument.Statement[].Principal.Federated'`

aws iam detach-role-policy --role-name AmazonEKS_EFS_CSI_DriverRole --policy-arn arn:aws:iam::${ACCOUNT}:policy/AmazonEKS_EFS_CSI_Driver_Policy
aws iam delete-role --role-name AmazonEKS_EFS_CSI_DriverRole
echo ''

# 단계 5 - EBS 드라이버 관련 리소스, 스택 삭제
echo '>> delete EBS-csi-controller '
kubectl delete -k CSI/EBS/aws-ebs-csi-driver/deploy/kubernetes/base/

aws iam detach-role-policy --role-name ${EBSRoleName} --policy-arn arn:aws:iam::${ACCOUNT}:policy/AmazonEKS_EBS_CSI_Driver_Policy

aws iam delete-policy --policy-arn arn:aws:iam::${ACCOUNT}:policy/AmazonEKS_EBS_CSI_Driver_Policy

aws cloudformation delete-stack --stack-name ${EBSStackName}
echo '======= Delete EFS Stack Finished'
echo ''

# 단계 5 - alb 드라이버 관련 리소스 삭제
## kubernetes alb controller deployment 삭제
kubectl delete -f ALB/v2_2_0_full.yaml

kubectl delete -f https://github.com/jetstack/cert-manager/releases/download/v1.1.1/cert-manager.yaml

aws iam detach-role-policy --role-name ${ALBRoleName} --policy-arn arn:aws:iam::${ACCOUNT}:policy/AWSLoadBalancerControllerAdditionalIAMPolicy
aws iam detach-role-policy --role-name ${ALBRoleName} --policy-arn arn:aws:iam::${ACCOUNT}:policy/AWSLoadBalancerControllerIAMPolicy
aws iam delete-policy --policy-arn arn:aws:iam::${ACCOUNT}:policy/AWSLoadBalancerControllerAdditionalIAMPolicy
aws iam delete-policy --policy-arn arn:aws:iam::${ACCOUNT}:policy/AWSLoadBalancerControllerIAMPolicy

aws cloudformation delete-stack --stack-name ${ALBStackName}
echo '>>>> Delete Resources Finished '
echo ''

# 단계 6 - 노드 스택 권한 분리
NODE_NUM=`aws cloudformation list-stacks --stack-status-filter "CREATE_COMPLETE" --query='StackSummaries[].StackName' --output json | jq -r '.[]' | grep nodegroup | wc -l`
for ((i=1; i<=${NODE_NUM}; i++)); do
NODE_ROLENAME=`aws iam list-roles | jq -r '.[][].RoleName' | grep nodegroup | sed -n ${i}p`

aws iam detach-role-policy \
 --role-name ${NODE_ROLENAME} \
 --policy-arn arn:aws:iam::${ACCOUNT}:policy/AllowExternalDNSUpdates

aws iam detach-role-policy \
 --role-name ${NODE_ROLENAME} \
 --policy-arn arn:aws:iam::${ACCOUNT}:policy/AmazonEKS_EFS_CSI_Driver_Policy
echo ${i}'번째 Node 권한 삭제 성공'
done
echo ''

echo '******************* Delete Cluster Start!! '
eksctl delte cluster -f t4_cluster.yaml
echo ''
echo '******************* Delete Cluster Finished!! '

function delete_EFS() {
  # 단계 6 - EFS 삭제
  ## 6-1 마운트 타켓 삭제
  FS_ID=`aws efs describe-file-systems | jq -r '.FileSystems[].FileSystemId'`
  FSMT_NUM=`aws efs describe-mount-targets --file-system-id ${FS_ID} | jq -r '.MountTargets[].MountTargetId' | wc -l`
  for ((i=1; i<=${NODE_NUM}; i++)); do
  FSMT_ID=`aws efs describe-mount-targets --file-system-id ${FS_ID} | jq -r "[.MountTargets[].MountTargetId][${i}]"`
  aws efs delete-mount-target --mount-target-id ${FSMT_ID}
  echo ${i}'번째 마운트 타겟 삭제'
  done
  
  ## 6-2 영구 EBS 볼륨 삭제
  EBS_NUM=`aws ec2 describe-volumes | jq -r '.[][] | select(.VolumeType=="gp3") | .VolumeId' | wc -l`
  for ((i=1; i<=${EBS_NUM}; i++)); do
  EBS_ID=`aws ec2 describe-volumes | jq -r "[.[][] | select(.VolumeType==\"gp3\")] | .[${i}].VolumeId"`
  aws ec2 delete-volume --volume-id ${EBS_ID}
  echo ${i}'번째 gp3 타입 EBS 삭제'
  done
  
  aws efs delete-file-system --file-system-id ${FS_ID}
  
  SG_ID=`aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" | jq '.[][] | select(.GroupName=="MyEfsSecurityGroup")' | jq -r '.GroupId'`
  aws ec2 delete-security-group --group-id ${SG_ID}
}

while true; do
  read -p "EFS와 EFS 보안그룹, 그리고 영구 EBS를 삭제하시겠습니까? [Y/n] " answer
  echo ''
  case $answer in
    [yY]* ) delete_EFS; break;;
    [nN]* ) break;;
    *) echo 'Y 또는 N으로 입력해 주세요.';;
  esac
done

# 단계 7 - 작업 폴더 삭제
echo '>>>>>  Delete Download Resources associated with ArgoCD, Jenkins, EX_DNS, EBS, ALB <'
rm -rf ArgoCD
rm -rf Jenkins
rm -rf EX_DNS
rm -rf CSI
rm -rf ALB

eksctl delete cluster -f t4_cluster.yaml

echo '>> Delete Resource, Stack Finished '
