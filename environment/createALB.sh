#/bin/bash
echo '>>> CREATE ALBIngressControllerIAMPolicy '
aws iam create-policy \
--policy-name ALBIngressControllerIAMPolicy \
--policy-document https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.3/docs/examples/iam-policy.json
echo ''
echo '>>> Connecting ALBIngressControllerIAMPolicy To WorkerNode Role'
NG_ROLE=`kubectl -n kube-system describe configmap aws-auth | grep rolearn`
ACCOUNT=${NG_ROLE:24:12}
WN_ROLE=${NG_ROLE:42}
echo "ACCOUNT          : $ACCOUNT"
echo "WORKER NODE ROLE : $WN_ROLE"
echo "NODE GROUP ROLE  : $NG_ROLE"
aws iam attach-role-policy \
--policy-arn arn:aws:iam::${ACCOUNT}:policy/ALBIngressControllerIAMPolicy \
--role-name ${WN_ROLE}
echo ''
echo '>>> Create ClusterRole for ALB Ingress Controller'
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.3/docs/examples/rbac-role.yaml
echo ''
echo '>>> Create ALB Ingress Controller'
CLUSTER_NAME='t4ClusterEKS' # 클러스터명
AWS_REGION='ap-northeast-2' # 클러스터 리젼
VPC_ID=`eksctl get cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --output json | jq -r '.[0].ResourcesVpcConfig.VpcId'`
echo "CLUSTER NAME : $CLUSTER_NAME"
echo "VPC ID       : $VPC_ID"
echo "AWS REGION   : $AWS_REGION"
echo ''
echo '>>> Remove Old alb-ingress-controller.yaml file && New alb-ingress-controller.yaml file Download'
rm -rf alb-ingress-controller.yaml* &&
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.3/docs/examples/alb-ingress-controller.yaml &&
# alb-ingress-controller.yaml
sed -i -e "s/# - --cluster-name=devCluster/- --cluster-name=$CLUSTER_NAME/g" alb-ingress-controller.yaml &&
sed -i -e "s/# - --aws-vpc-id=vpc-xxxxxx/- --aws-vpc-id=$VPC_ID/g" alb-ingress-controller.yaml &&
sed -i -e "s/# - --aws-region=us-west-1/- --aws-region=$AWS_REGION/g" alb-ingress-controller.yaml &&
kubectl apply -f ./alb-ingress-controller.yaml
echo '>>> FINISH'
sleep 5
echo '>>> Checking Create ALB Ingress Controller'
kubectl get pods -n kube-system | grep alb
echo ''
echo '====== Connect POLICY-EKS-IAM with Ingress Controller ======'
