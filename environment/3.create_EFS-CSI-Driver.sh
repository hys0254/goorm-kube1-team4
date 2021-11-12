################################# EFS 파일 시스템 생성 스크립트 시작

# https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/efs-csi.html 참고

CLUSTER_NAME=`eksctl get cluster --output json | jq -r '.[0].metadata.name'`
AWS_REGION=`eksctl get cluster --output json | jq -r '.[0].metadata.region'`
VPC_ID=`eksctl get cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --output json | jq -r '.[0].ResourcesVpcConfig.VpcId'`
NG_ROLE=`kubectl -n kube-system describe configmap aws-auth | grep rolearn`
ACCOUNT=${NG_ROLE:24:12}
echo 'Print Var Before Making CSI-Driver-Controller  '
echo 'CLUSTER_NAME : '${CLUSTER_NAME}
echo 'AWS_REGION : '${AWS_REGION}
echo 'VPC_ID : '${VPC_ID}
echo 'NG_ROLE : '${NG_ROLE}
echo 'ACCOUNT : '${ACCOUNT}
echo ''

mkdir -p CSI/EFS

# 단계1 : CSI 컨트롤러 IAM 정책 다운로드
echo '> Step1 : Download CSIControllerIAMPolicy  '
curl -o CSI/EFS/iam-policy-example.json https://raw.githubusercontent.com/kubernetes-sigs/aws-efs-csi-driver/v1.3.2/docs/iam-policy-example.json
echo ''

# 단계2 : 단계1에서 다운로드한 정책으로 IAM 정책 만듦. - 기존에 만들어진 정책이 존재할 시, 단계 스킵하도록 if문 구성
echo '>> Step2 : CREATE AmazonEKS_EFS_CSI_Driver_Policy  '
if [ "`aws iam list-policies | grep AmazonEKS_EFS_CSI_Driver_Policy`" ]
then
  echo '>> AmazonEKS_EFS_CSI_Driver_Policy was installed continue next step '
else
  aws iam create-policy --policy-name AmazonEKS_EFS_CSI_Driver_Policy --policy-document file://CSI/EFS/iam-policy-example.json | grep AmazonEKS_EFS_CSI_Driver_Policy
fi
echo ''

# 단계3 : 기존 OIDC 공급자 여부 확인 및 없을 시 생성.
echo '>>> Step3 : Check AmazonEKS_EBS_CSI_Driver_Policy associate with OIDCProvider '
OIDCisuser=`aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text`
OIDCProvider=${OIDCisuser:49}
echo 'OIDCisuser : '${OIDCisuser}
echo 'OIDCProvider : '${OIDCProvider}

if [ "`aws iam list-open-id-connect-providers | grep ${OIDCProvider}`" ]
then
  echo 'IAM OIDC is exist... Create iamserviceaccount with AmazonEKS_EFS_CSI_Driver_Policy  '
  eksctl create iamserviceaccount --cluster=${CLUSTER_NAME} --namespace=kube-system --name=efs-csi-controller-sa --attach-policy-arn=arn:aws:iam::${ACCOUNT}:policy/AmazonEKS_EFS_CSI_Driver_Policy --override-existing-serviceaccounts --approve
  echo 'Create iamserviceaccount with AmazonEKS_EBS_CSI_Driver_Policy success'
else
  echo 'IAM OIDC is not exist... Create IAM OIDC Provider  '
  eksctl utils associate-iam-oidc-provider --region=ap-northeast-2 --cluster=${CLUSTER_NAME} --approve
  eksctl create iamserviceaccount --cluster=${CLUSTER_NAME} --namespace=kube-system --name=efs-csi-controller-sa --attach-policy-arn=arn:aws:iam::${ACCOUNT}:policy/AmazonEKS_EFS_CSI_Driver_Policy --override-existing-serviceaccounts --approve
  echo 'Create iamserviceaccount with AmazonEKS_EBS_CSI_Driver_Policy success'
fi
echo ''

# 단계 4 : EFS 드라이버 파일 다운 및 수정, 실행
echo '>>> Step4 : Download EFS-Driver.yaml & Edit & Run!'
kubectl kustomize \
    "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/ecr?ref=release-1.3" > CSI/EFS/driver.yaml
echo ''
sed -i '1,7d' CSI/EFS/driver.yaml
echo '>>> apply driver.yaml'
kubectl apply -f CSI/EFS/driver.yaml
echo ''


# 단계 5 : EFS 생성용 보안그룹 생성
CIDR_RANGE=`aws ec2 describe-vpcs --vpc-ids ${VPC_ID} --query "Vpcs[].CidrBlock" --output text`
SG_ID=`aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" | jq '.[][] | select(.GroupName=="MyEfsSecurityGroup")' | jq -r '.GroupId'`
if [[ -z ${SG_ID} ]]
then
SG_ID=`aws ec2 create-security-group --group-name MyEfsSecurityGroup --description "EFS security group EKClusterS" --vpc-id ${VPC_ID} --tag --output text`
  echo 'Create Security-group... Name = MyEfsSecurityGroup'
else
  echo 'Using existing Security-group for Making EFS'
fi

echo '>>> Print Var for EFS'
echo 'CIDR_RANGE : '${CIDR_RANGE}
echo 'SG_ID : '${SG_ID}

aws ec2 authorize-security-group-ingress --group-id ${SG_ID} --protocol tcp --port 2049 --cidr ${CIDR_RANGE} | grep SecurityGroupRuleId

FS_ID=`aws efs create-file-system --region ${AWS_REGION} --performance-mode generalPurpose --query 'FileSystemId' --output text | grep fs`

## 단계 6 : 파일시스템 생성용 반복문
# TEMPNUM=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query 'Subnets[*].{SubnetId: SubnetId,AvailabilityZone: AvailabilityZone,CidrBlock: CidrBlock,MapPublicIpOnLaunch:MapPublicIpOnLaunch}' --output json | jq '.[] | select(.MapPublicIpOnLaunch==false)' | grep SubnetId | wc -l`
TEMPNUM=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query 'Subnets[*].{SubnetId: SubnetId,AvailabilityZone: AvailabilityZone,CidrBlock: CidrBlock,MapPublicIpOnLaunch:MapPublicIpOnLaunch}' --output json | jq -r "[.[] | select(.MapPublicIpOnLaunch==false)] | length"`

echo 'TEMPNUM : '${TEMPNUM}

for ((i=0; i<${TEMPNUM}; i++)); do
# subnetId=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query 'Subnets[*].{SubnetId: SubnetId,AvailabilityZone: AvailabilityZone,CidrBlock: CidrBlock,MapPublicIpOnLaunch:MapPublicIpOnLaunch}' --output json | jq -r ".[${i}] | select(.MapPublicIpOnLaunch==false) | .SubnetId"`
subnetId=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query 'Subnets[*].{SubnetId: SubnetId,AvailabilityZone: AvailabilityZone,CidrBlock: CidrBlock,MapPublicIpOnLaunch:MapPublicIpOnLaunch}' --output json | jq -r "[.[] | select(.MapPublicIpOnLaunch==false)] | .[${i}].SubnetId"`
# avZone=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query 'Subnets[*].{SubnetId: SubnetId,AvailabilityZone: AvailabilityZone,CidrBlock: CidrBlock,MapPublicIpOnLaunch:MapPublicIpOnLaunch}' --output json | jq -r ".[${i}] | select(.MapPublicIpOnLaunch==false) | .AvailabilityZone"`
avZone=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query 'Subnets[*].{SubnetId: SubnetId,AvailabilityZone: AvailabilityZone,CidrBlock: CidrBlock,MapPublicIpOnLaunch:MapPublicIpOnLaunch}' --output json | jq -r "[.[] | select(.MapPublicIpOnLaunch==false)] | .[${i}].AvailabilityZone"`
echo ${subnetId}' - '${avZone}
#aws efs create-mount-target --file-system-id ${FS_ID} --subnet-id ${subnetId} --security-groups ${SG_ID}
`aws efs create-mount-target \
              --file-system-id ${FS_ID} \
              --subnet-id ${subnetId} \
              --security-groups ${SG_ID} > mount_target_${subnetId}.txt`
sleep 2
done
## 파일시스템 생성용 반복문 끝

## 단계 7 : StorageClass, PVC 배포
echo '>>> Download storageclass.yaml & Edit <<<'
curl -o CSI/EFS/storageclass.yaml https://raw.githubusercontent.com/kubernetes-sigs/aws-efs-csi-driver/master/examples/kubernetes/dynamic_provisioning/specs/storageclass.yaml
sed -i "/fileSystemId/c\\  fileSystemId: ${FS_ID}" CSI/EFS/storageclass.yaml
cat CSI/EFS/storageclass.yaml

kubectl apply -f CSI/EFS/storageclass.yaml

