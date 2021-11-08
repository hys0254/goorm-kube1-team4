#/bin/bash

#  https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/aws-load-balancer-controller.html 참고

#CLUSTER_NAME=`eksctl get cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --output json | jq -r '.[0].Name'`
CLUSTER_NAME=`eksctl get cluster --output json | jq -r '.[0].metadata.name'`
AWS_REGION=`eksctl get cluster --output json | jq -r '.[0].metadata.region'`
VPC_ID=`eksctl get cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --output json | jq -r '.[0].ResourcesVpcConfig.VpcId'`
NG_ROLE=`kubectl -n kube-system describe configmap aws-auth | grep rolearn`
ACCOUNT=${NG_ROLE:24:12}
echo 'Variable Print Before Making AWSLoadBalancerController  '
echo 'CLUSTER_NAME : '${CLUSTER_NAME}
echo 'AWS_REGION : '${AWS_REGION}
echo 'VPC_ID : '${VPC_ID}
echo 'NG_ROLE : '${NG_ROLE}
echo 'ACCOUNT : '${ACCOUNT}
echo ''

# 단계1 : AWS 로드밸런서 컨트롤러 IAM 정책 다운로드
echo '> Step1 : Download AWSLoadBalancerControllerIAMPolicy  '
mkdir ALB
curl -o ALB/iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.2.0/docs/install/iam_policy.json
echo ''

# 단계2 : 단계1에서 다운로드한 정책으로 IAM 정책 만듦. - 기존에 만들어진 정책이 존재할 시, 단계 스킵하도록 if문 구성
echo '>> Step2 : CREATE AWSLoadBalancerControllerIAMPolicy  '
# if [ "`aws iam list-policies | grep AWSLoadBalancerControllerIAMPolicy`" ];then echo '>> AWSLoadBalancerControllerIAMPolicy was installed continue next step ';else `aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy.json`;fi
if [ "`aws iam list-policies | grep AWSLoadBalancerControllerIAMPolicy`" ]
then
  echo '>> AWSLoadBalancerControllerIAMPolicy was installed continue next step '
else
  aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy.json | grep AWSLoadBalancerControllerIAMPolicy
fi
echo ''

# 단계3 : 기존 OIDC 공급자 생성 여부 확인 -> aws-load-balancer 공급자와 공급자를 통한 ALB 컨트롤러 생성.
echo '>>> Step3 : Create iamserviceaccount with AWSLoadBalancerControllerIAMPolicy  '
OIDCisuser=`aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text`
OIDCProvider=${OIDCisuser:49}
echo 'OIDCisuser : '${OIDCisuser}
echo 'OIDCProvider : '${OIDCProvider}

if [ "`aws iam list-open-id-connect-providers | grep ${OIDCProvider}`" ]
then
  echo 'IAM OIDC is exist... Create iamserviceaccount with AWSLoadBalancerControllerIAMPolicy  '
  eksctl create iamserviceaccount --cluster=${CLUSTER_NAME} --namespace=kube-system --name=aws-load-balancer-controller --attach-policy-arn=arn:aws:iam::${ACCOUNT}:policy/AWSLoadBalancerControllerIAMPolicy --override-existing-serviceaccounts --approve
  echo 'Create iamserviceaccount with AWSLoadBalancerControllerIAMPolicy success'
else
  echo 'IAM OIDC is not exist... Create IAM OIDC Provider  '
  eksctl utils associate-iam-oidc-provider --region=ap-northeast-2 --cluster=t4ClusterEKS --approve
  eksctl create iamserviceaccount --cluster=${CLUSTER_NAME} --namespace=kube-system --name=aws-load-balancer-controller --attach-policy-arn=arn:aws:iam::${ACCOUNT}:policy/AWSLoadBalancerControllerIAMPolicy --override-existing-serviceaccounts --approve
  echo 'Create iamserviceaccount with AWSLoadBalancerControllerIAMPolicy success'
fi
echo ''

# 단계4 : 단계4 중 a, b 두 단계의 kubernets용 수신 컨트롤러 설치 제거는 건너뜀. 구성하지 않을 것 같아서..! 우선은 패스 | 하단에는 c 단계3에서 생성한 IAM 역할에 정책 추가 부분만 넣음.
# 단계4-c-1 : IAM 정책 다운로드
echo '>>>> Step4 : Download AWSLoadBalancerControllerAdditionalIAMPolicy  '
curl -o ALB/iam_policy_v1_to_v2_additional.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.2.0/docs/install/iam_policy_v1_to_v2_additional.json
echo ''

# 단계4-c-2 : IAM 정책 생성 | 기존에 생성된 정책이 존재할 시, 다음 단계로 넘어가도록 if문 구성
echo '>>> Create iamserviceaccount with AWSLoadBalancerControllerAdditionalIAMPolicy  '
if [ "`aws iam list-policies | grep AWSLoadBalancerControllerAdditionalIAMPolicy`" ]
then
  echo '>>> AWSLoadBalancerControllerAdditionalIAMPolicy was installed continue next step '
else
  aws iam create-policy --policy-name AWSLoadBalancerControllerAdditionalIAMPolicy --policy-document file://iam_policy_v1_to_v2_additional.json | grep AWSLoadBalancerControllerAdditionalIAMPolicy
fi
echo ''

# 단계4-c-3 : 단계4-c-2에서 생성한 정책과 단계3에서 생성한 OIDC 공급자 역할 연결
echo '>>> AWSLoadBalancerControllerAdditionalIAMPolicy Attach to Role '
ALBCloudStackName=`aws cloudformation list-stacks | jq -r '.StackSummaries[0].StackName'`
ALBRoleName=`aws cloudformation describe-stacks --stack-name ${ALBCloudStackName} --query='Stacks[].Outputs[?OutputKey==\`Role1\`].OutputValue' --output json | jq -r '.[0] | .[0]' | cut -f 2 -d "/"`
aws iam attach-role-policy --role-name ${ALBRoleName} --policy-arn arn:aws:iam::${ACCOUNT}:policy/AWSLoadBalancerControllerAdditionalIAMPolicy
echo ''


# 단계5 :  Kubernetes 매니페스트를 적용하여 AWS 로드 밸런서 컨트롤러를 설치
# 단계5-a : cert-manager를 설치하여 인증서 구성 Webhook에 주입.(Webhook주입이 무엇인지는 알아보는 중..)
echo '>>>>> Step5 : Install AWS Load Balancer Controller... '
echo '>>> Install cert-manager '
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.1.1/cert-manager.yaml
echo ''
# 단계5-b-1 : 컨트롤러 사양 다운로드
echo '>>> Download Controller Spec '
curl -o ALB/v2_2_0_full.yaml https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.2.0/docs/install/v2_2_0_full.yaml
echo ''
# 단계5-b-2 : 컨트롤러 사양 파일 편집 -> your-cluster-name 항목 편집 / ServiceAccount 섹션 삭제(545~553라인)
echo '>>> Edit Controller Spec -> ClusterName & Delete ServiceAccount Spec '
sed -i 's/your-cluster-name/'${CLUSTER_NAME}'/g' ALB/v2_2_0_full.yaml
sed -i '545,553d' ALB/v2_2_0_full.yaml
# 545~553번 라인 내용
#---
#apiVersion: v1
#kind: ServiceAccount
#metadata:
#  labels:
#    app.kubernetes.io/component: controller
#    app.kubernetes.io/name: aws-load-balancer-controller
#  name: aws-load-balancer-controller
#  namespace: kube-system

# 단계5-b-3 : 컨트롤러 사양 적용
echo '>>> apply v2_2_0_full.yaml '
kubectl apply -f v2_2_0_full.yaml
echo ''

echo '===================== ALB Controller creation Success ====================='
echo "if you want to check aws-load-balancer-controller run well, type command'  kubectl get deployment -n kube-system aws-load-balancer-controller  ' "
echo ''
#ㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡ 기존 Ingress Controller#
#echo ''
#echo '>>> Check if ALB-Ingress-Controller Installed  '
#if [ `kubectl get deployment -n kube-system alb-ingress-controller` ]
#then
# `curl -o iam_policy_v1_to_v2_additional.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.2.0/docs/install/iam_policy_v1_to_v2_additional.json`
# `aws iam create-policy \
#    --policy-name AWSLoadBalancerControllerAdditionalIAMPolicy \
#    --policy-document file://iam_policy_v1_to_v2_additional.json`
#else
# `kubectl delete -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.8/docs/examples/alb-ingress-controller.yaml`
# `kubectl delete -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.8/docs/examples/rbac-role.yaml`
#fi
#
#
#NG_ROLE=`kubectl -n kube-system describe configmap aws-auth | grep rolearn`
#ACCOUNT=${NG_ROLE:24:12}
#WN_ROLE=${NG_ROLE:42}
#echo "ACCOUNT          : $ACCOUNT"
#echo "WORKER NODE ROLE : $WN_ROLE"
#echo "NODE GROUP ROLE  : $NG_ROLE"
#aws iam attach-role-policy \
#--policy-arn arn:aws:iam::${ACCOUNT}:policy/AWSLoadBalancerControllerIAMPolicy \
#--role-name ${WN_ROLE}
#
#
#echo ''
#echo '>>> Create AWSLoadBalancerControllerIAMPolicy To WorkerNode Role'
#NG_ROLE=`kubectl -n kube-system describe configmap aws-auth | grep rolearn`
#ACCOUNT=${NG_ROLE:24:12}
#WN_ROLE=${NG_ROLE:42}
#echo "ACCOUNT          : $ACCOUNT"
#echo "WORKER NODE ROLE : $WN_ROLE"
#echo "NODE GROUP ROLE  : $NG_ROLE"
#aws iam attach-role-policy \
#--policy-arn arn:aws:iam::${ACCOUNT}:policy/AWSLoadBalancerControllerIAMPolicy \
#--role-name ${WN_ROLE}
#echo ''
#echo '>>> Create ClusterRole for ALB Ingress Controller'
#kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.3/docs/examples/rbac-role.yaml
#echo ''
#echo '>>> Create ALB Ingress Controller'
#CLUSTER_NAME='t4ClusterEKS' # 클러스터명
#AWS_REGION='ap-northeast-2' # 클러스터 리젼
#VPC_ID=`eksctl get cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --output json | jq -r '.[0].ResourcesVpcConfig.VpcId'`
#echo "CLUSTER NAME : $CLUSTER_NAME"
#echo "VPC ID       : $VPC_ID"
#echo "AWS REGION   : $AWS_REGION"
#echo ''
#echo '>>> Remove Old alb-ingress-controller.yaml file && New alb-ingress-controller.yaml file Download'
#rm -rf alb-ingress-controller.yaml* &&
#curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.3/docs/examples/alb-ingress-controller.yaml &&
## alb-ingress-controller.yaml
#sed -i -e "s/# - --cluster-name=devCluster/- --cluster-name=$CLUSTER_NAME/g" alb-ingress-controller.yaml &&
#sed -i -e "s/# - --aws-vpc-id=vpc-xxxxxx/- --aws-vpc-id=$VPC_ID/g" alb-ingress-controller.yaml &&
#sed -i -e "s/# - --aws-region=us-west-1/- --aws-region=$AWS_REGION/g" alb-ingress-controller.yaml &&
#kubectl apply -f ./alb-ingress-controller.yaml
#echo '>>> FINISH'
#sleep 5
#echo '>>> Checking Create ALB Ingress Controller'
#kubectl get pods -n kube-system | grep alb
#echo ''
#echo '====== Connect POLICY-EKS-IAM with Ingress Controller ======'
