################################# EXTERNAL_DNS 정책, 역할 생성 

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

mkdir -p EX_DNS

# 단계1 : DNS 정책 다운로드
echo '> Step1 : Create EX_ENS_Policy.json   '
cat > EX_DNS/AllowExternalDNSUpdates.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": [
        "arn:aws:route53:::hostedzone/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF

aws iam create-policy --policy-name AllowExternalDNSUpdates --policy-document file://EX_DNS/AllowExternalDNSUpdates.json | grep AllowExternalDNSUpdates
echo ''

# 단계 2 : 기존 OIDC 공급자 여부 확인 및 없을 시 생성. -> 공식 가이드문서 상의 AWS CLI탭의 trust_policy.json 형식으로 변경
echo '>>> Step 2 : Check AllowExternalDNSUpdates associate with OIDCProvider '
OIDCisuser=`aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.identity.oidc.issuer" --output text`
OIDCProvider=${OIDCisuser:49}
echo 'OIDCisuser : '${OIDCisuser}
echo 'OIDCProvider : '${OIDCProvider}
echo ''

if [ "`aws iam list-open-id-connect-providers | grep ${OIDCProvider}`" ]
then
  echo 'IAM OIDC is exist... Create iamserviceaccount with AllowExternalDNSUpdates  '
  eksctl create iamserviceaccount --cluster=${CLUSTER_NAME} --namespace=default --name=external-dns --attach-policy-arn=arn:aws:iam::${ACCOUNT}:policy/AllowExternalDNSUpdates --override-existing-serviceaccounts --approve
  echo 'Create iamserviceaccount with AllowExternalDNSUpdates success'
else
  echo 'IAM OIDC is not exist... Create IAM OIDC Provider  '
  eksctl utils associate-iam-oidc-provider --region=ap-northeast-2 --cluster=${CLUSTER_NAME} --approve
  eksctl create iamserviceaccount --cluster=${CLUSTER_NAME} --namespace=default --name=external-dns --attach-policy-arn=arn:aws:iam::${ACCOUNT}:policy/AllowExternalDNSUpdates --override-existing-serviceaccounts --approve
  echo 'Create iamserviceaccount with AllowExternalDNSUpdates success'
fi
echo ''

sleep 10

echo '>> ServiceAccount for AllowExternalDNSUpdates'
while true; do
  read -p ">>>>> 사용하실 도메인을 입력해 주세요 : " hostzone
  echo ''
  read -p "입력하신 도메인 : [$hostzone] 이 맞습니까?[y/N]" answer
  echo ''
  case $answer in
  [Yy]* ) echo "[$hostzone] 주소로 ServiceAccount를 생성합니다."; break;;
  [Nn]* ) continue;;
  * ) echo "y 또는 n으로 입력해 주세요.";;
  esac
done

DNSStackName=`aws cloudformation list-stacks | jq -r '.StackSummaries[0].StackName'`
DNSRoleName=`aws cloudformation describe-stacks --stack-name ${DNSStackName} --query='Stacks[].Outputs[?OutputKey==\`Role1\`].OutputValue' --output json | jq -r '.[0] | .[0]'`
echo 'DNSStackName : ' ${DNSStackName}
echo 'DNSRoleName : ' ${DNSRoleName}
echo ''

hostzoneId=`aws route53 list-hosted-zones | jq -r '.HostedZones[] | select(.Name=="'${hostzone}'.") | .Id' | cut -f 3 -d "/"` # select 조건의 hostzone + . 이 있습니다. 참고
echo 'hostzoneId = '${hostzoneId}
if [[ `grep "hostzone" ~/.zshrc` ]];
then
  echo 'export hostzone exist';
else
  echo 'export hostzone not exist / alias hostzone will be inserted';
  echo 'export hostzone='${hostzone} >> ~/.zshrc
fi
echo ''

if [[ `grep "hostzone" ~/.bashrc` ]];
then
  echo 'export hostzone exist';
else
  echo 'export hostzone not exist / alias hostzone will be inserted';
  echo 'export hostzone='${hostzone} >> ~/.bashrc
fi
echo ''

echo '>> Make external-dns-account.yaml'
cat > EX_DNS/external-dns-account.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
  # If you're using Amazon EKS with IAM Roles for Service Accounts, specify the following annotation.
  # Otherwise, you may safely omit it.
  annotations:
    # Substitute your account ID and IAM service role name below.
    eks.amazonaws.com/role-arn: ${DNSRoleName}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-dns
rules:
- apiGroups: [""]
  resources: ["services","endpoints","pods"]
  verbs: ["get","watch","list"]
- apiGroups: ["extensions","networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get","watch","list"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["list","watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-dns-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
- kind: ServiceAccount
  name: external-dns
  namespace: default 
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
spec:
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: external-dns
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      serviceAccountName: external-dns
      containers:
      - name: external-dns
        image: k8s.gcr.io/external-dns/external-dns:v0.7.6
        args:
        - --source=service
        - --source=ingress
        - --domain-filter=${hostzone}
        - --provider=aws
        - --policy=upsert-only # would prevent ExternalDNS from deleting any records, omit to enable full synchronization
        - --aws-zone-type=public # only look at public hosted zones (valid values are public, private or no value for both)
        - --registry=txt
        - --txt-owner-id=${hostzoneId}
      securityContext:
        fsGroup: 65534 # For ExternalDNS to be able to read Kubernetes and AWS token files
EOF
echo ''

echo 'Apply external-dns-account.yaml'
kubectl apply -f EX_DNS/external-dns-account.yaml 

INS_NUM=`aws iam list-roles | jq '.[][].RoleName' | grep NodeInstanceRole | wc -l`
for ((i=1; i<=${INS_NUM}; i++)); do
INS_ROLENAME=`aws iam list-roles | jq -r '.[][].RoleName' | grep nodegroup | sed -n ${i}p`
aws iam attach-role-policy \
 --role-name ${INS_ROLENAME} \
 --policy-arn arn:aws:iam::${ACCOUNT}:policy/AllowExternalDNSUpdates
echo ${i}'번째 Node 권한 연결 성공'
done

echo ''

echo '>>>> Make & Apply External-dns-account Finished'
