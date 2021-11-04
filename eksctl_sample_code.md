

내 코드

```yaml
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: t4ClusterEKS
  region: ap-northeast-2
  version: "1.20"

vpc:
  id: "vpc-0120cb38b9cb01faf"  # (optional, must match VPC ID used for each subnet below)
  cidr: "192.168.0.0/16"       # (optional, must match CIDR used by the given VPC)
  nat:
    gateway: "Disable"
  subnets:
    public: 
      ap-northeast-2a: 
        id: "subnet-0a74dc9eb91068769"
        cidr: "192.168.0.0/24"
      ap-northeast-2c: 
        id: "subnet-09d4a8108e12031bb"
        cidr: "192.168.32.0/24"
    private:
      ap-northeast-2a:
        id: "subnet-05c2b2cdcde7c0454"
        cidr: "192.168.64.0/24" # (optional, must match CIDR used by the given subnet)
      ap-northeast-2c:
        id: "subnet-073d68063f1a6604f"
        cidr: "192.168.96.0/24"  # (optional, must match CIDR used by the given subnet)

# 기존 생성된 vpc 영역을 사용하는 경우, 사용할 수 없는 속성
#availabilityZones: 
#  - "ap-northeast-2a"
#  - "ap-northeast-2b"
 
managedNodeGroups:
  - name: dbNode
    instanceType: t2.small
    instanceName: "dbIns"
    minSize: 2
    desiredCapacity: 2
    maxSize: 3
    volumeSize: 10
    privateNetworking: true
    iam:
      withAddonPolicies:
        ebs: true
        autoScaler: true
    availabilityZones: 
      - "ap-northeast-2a"
      - "ap-northeast-2c"
#    subnets:
#      - private-2a
#      - private-2c

  - name: wordpressNode
    instanceType: t2.small
    instanceName: "wordPressIns"
    minSize: 2
    desiredCapacity: 2
    maxSize: 3
    privateNetworking: true
    iam:
      withAddonPolicies:
        autoScaler: true
    availabilityZones: 
      - "ap-northeast-2a"
      - "ap-northeast-2c"
#    subnets:
#      - private-2a
#      - private-2b

  - name: nginxNode
    instanceType: t2.small
    instanceName: "nginxIns"
    minSize: 2
    desiredCapacity: 2
    maxSize: 3
    privateNetworking: true
    iam:
      withAddonPolicies:
        autoScaler: true
    availabilityZones: 
      - "ap-northeast-2a"
      - "ap-northeast-2c"
#    subnets:
#      - private-2a
#      - private-2b

#cloudWatch:
#    clusterLogging:
#        enableTypes: ["*"]

iam:
  withOIDC: true
  serviceAccounts:
  - metadata:
      name: s3-reader
      # if no namespace is set, "default" will be used;
      # the namespace will be created if it doesn't exist already
      namespace: backend-apps
      labels: {aws-usage: "application"}
    attachPolicyARNs:
    - "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  - metadata:
      name: aws-load-balancer-controller
      namespace: kube-system
    wellKnownPolicies:
      awsLoadBalancerController: true
  - metadata:
      name: ebs-csi-controller-sa
      namespace: kube-system
    wellKnownPolicies:
      ebsCSIController: true
  - metadata:
      name: efs-csi-controller-sa
      namespace: kube-system
    wellKnownPolicies:
      efsCSIController: true
  - metadata:
      name: cert-manager
      namespace: cert-manager
    wellKnownPolicies:
      certManager: true
  - metadata:
      name: cluster-autoscaler
      namespace: kube-system
      labels: {aws-usage: "cluster-ops"}
    wellKnownPolicies:
      autoScaler: true
  - metadata:
      name: cache-access
      namespace: backend-apps
      labels: {aws-usage: "application"}
    attachPolicyARNs:
    - "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"
    - "arn:aws:iam::aws:policy/AmazonElastiCacheFullAccess"
  - metadata:
      name: autoscaler-service
      namespace: kube-system
    attachPolicy: # inline policy can be defined along with `attachPolicyARNs`
      Version: "2012-10-17"
      Statement:
      - Effect: Allow
        Action:
        - "autoscaling:DescribeAutoScalingGroups"
        - "autoscaling:DescribeAutoScalingInstances"
        - "autoscaling:DescribeLaunchConfigurations"
        - "autoscaling:DescribeTags"
        - "autoscaling:SetDesiredCapacity"
        - "autoscaling:TerminateInstanceInAutoScalingGroup"
        - "ec2:DescribeLaunchTemplateVersions"
        Resource: '*'

```



*** 네트워크 구성 확인용 샘플 코드

```yaml
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata: 
  name: team4-cluster # 생성할 EKS 클러스터명
  region: ap-northeast-2 # 클러스터를 생성할 리젼
  version: "1.20"

vpc: 
  cidr: "192.168.0.0/16" # 클러스터에서 사용할 VPC의 CIDR
  nat:
  	gateway: "HighlyAvailable"

availabilityZones:
  - ap-northeast-2a
  - ap-northeast-2c

managedNodeGroups: 
  - name: db-Node # 클러스터의 노드 그룹명
    instanceName: "dbIns"
    instanceType: t2.small # 클러스터 워커 노드의 인스턴스 타입
    desiredCapacity: 2 # 클러스터 워커 노드의 갯수
    volumeSize: 15  # 클러스터 워커 노드의 EBS 용량 (단위: GiB)
    privateNetworking: true
    availabilityZones: 
      - ap-northeast-2a
      - ap-northeast-2c
    iam: 
      withAddonPolicies: 
        albIngress: true  # albIngress에 대한 권한 추가
        cloudWatch: true # cloudWatch에 대한 권한 추가
        autoScaler: true # auto scaling에 대한 권한 추가
```



*** 쿠버네티스 대시보드

```shell
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.3.1/aio/deploy/recommended.yaml
```

```shell
kubectl proxy --port=8080 --address=0.0.0.0 --disable-filter=true &
```

```shell
ec2-13-209-77-168.ap-northeast-2.compute.amazonaws.com/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```



*** Ingress Controller 생성

```shell
cd ~/environment

mkdir -p manifests/alb-controller && cd manifests/alb-controller

# 최종 폴더 위치
/home/ec2-user/environment/manifests/alb-controller
```

```shell
eksctl utils associate-iam-oidc-provider \
    --region ap-northeast-2 \
    --cluster team4-demo \
    --approve
```





- Application Load Balancer

```shell
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
CLUSTER_NAME='eks-cluster-demo' # 클러스터명
AWS_REGION='ap-southeast-1' # 클러스터 리젼
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

```



2) Ingress Controller 

   (1) POLICY-EKS-IAM 정책

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "acm:DescribeCertificate",
           "acm:ListCertificates",
           "acm:GetCertificate"
         ],
         "Resource": "*"
       },
       {
         "Effect": "Allow",
         "Action": [
           "ec2:AuthorizeSecurityGroupIngress",
           "ec2:CreateSecurityGroup",
           "ec2:CreateTags",
           "ec2:DeleteTags",
           "ec2:DeleteSecurityGroup",
           "ec2:DescribeAccountAttributes",
           "ec2:DescribeAddresses",
           "ec2:DescribeInstances",
           "ec2:DescribeInstanceStatus",
           "ec2:DescribeInternetGateways",
           "ec2:DescribeNetworkInterfaces",
           "ec2:DescribeSecurityGroups",
           "ec2:DescribeSubnets",
           "ec2:DescribeTags",
           "ec2:DescribeVpcs",
           "ec2:ModifyInstanceAttribute",
           "ec2:ModifyNetworkInterfaceAttribute",
           "ec2:RevokeSecurityGroupIngress"
         ],
         "Resource": "*"
       },
       {
         "Effect": "Allow",
         "Action": [
           "elasticloadbalancing:AddListenerCertificates",
           "elasticloadbalancing:AddTags",
           "elasticloadbalancing:CreateListener",
           "elasticloadbalancing:CreateLoadBalancer",
           "elasticloadbalancing:CreateRule",
           "elasticloadbalancing:CreateTargetGroup",
           "elasticloadbalancing:DeleteListener",
           "elasticloadbalancing:DeleteLoadBalancer",
           "elasticloadbalancing:DeleteRule",
           "elasticloadbalancing:DeleteTargetGroup",
           "elasticloadbalancing:DeregisterTargets",
           "elasticloadbalancing:DescribeListenerCertificates",
           "elasticloadbalancing:DescribeListeners",
           "elasticloadbalancing:DescribeLoadBalancers",
           "elasticloadbalancing:DescribeLoadBalancerAttributes",
           "elasticloadbalancing:DescribeRules",
           "elasticloadbalancing:DescribeSSLPolicies",
           "elasticloadbalancing:DescribeTags",
           "elasticloadbalancing:DescribeTargetGroups",
           "elasticloadbalancing:DescribeTargetGroupAttributes",
           "elasticloadbalancing:DescribeTargetHealth",
           "elasticloadbalancing:ModifyListener",
           "elasticloadbalancing:ModifyLoadBalancerAttributes",
           "elasticloadbalancing:ModifyRule",
           "elasticloadbalancing:ModifyTargetGroup",
           "elasticloadbalancing:ModifyTargetGroupAttributes",
           "elasticloadbalancing:RegisterTargets",
           "elasticloadbalancing:RemoveListenerCertificates",
           "elasticloadbalancing:RemoveTags",
           "elasticloadbalancing:SetIpAddressType",
           "elasticloadbalancing:SetSecurityGroups",
           "elasticloadbalancing:SetSubnets",
           "elasticloadbalancing:SetWebAcl"
         ],
         "Resource": "*"
       },
       {
         "Effect": "Allow",
         "Action": [
           "iam:CreateServiceLinkedRole",
           "iam:GetServerCertificate",
           "iam:ListServerCertificates"
         ],
         "Resource": "*"
       },
       {
         "Effect": "Allow",
         "Action": [
           "cognito-idp:DescribeUserPoolClient"
         ],
         "Resource": "*"
       },
       {
         "Effect": "Allow",
         "Action": [
           "waf-regional:GetWebACLForResource",
           "waf-regional:GetWebACL",
           "waf-regional:AssociateWebACL",
           "waf-regional:DisassociateWebACL"
         ],
         "Resource": "*"
       },
       {
         "Effect": "Allow",
         "Action": [
           "tag:GetResources",
           "tag:TagResources"
         ],
         "Resource": "*"
       },
       {
         "Effect": "Allow",
         "Action": [
           "waf:GetWebACL"
         ],
         "Resource": "*"
       },
       {
         "Effect": "Allow",
         "Action": [
           "wafv2:GetWebACL",
           "wafv2:GetWebACLForResource",
           "wafv2:AssociateWebACL",
           "wafv2:DisassociateWebACL"
         ],
         "Resource": "*"
       },
       {
         "Effect": "Allow",
         "Action": [
           "shield:DescribeProtection",
           "shield:GetSubscriptionState",
           "shield:DeleteProtection",
           "shield:CreateProtection",
           "shield:DescribeSubscription",
           "shield:ListProtections"
         ],
         "Resource": "*"
       }
     ]
   }
   ```

   (2) Ingress Controller 생성

   ```yaml
   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRole
   metadata:
     labels:
       app.kubernetes.io/name: alb-ingress-controller
     name: alb-ingress-controller
   rules:
     - apiGroups:
         - ""
         - extensions
       resources:
         - configmaps
         - endpoints
         - events
         - ingresses
         - ingresses/status
         - services
         - pods/status
       verbs:
         - create
         - get
         - list
         - update
         - watch
         - patch
     - apiGroups:
         - ""
         - extensions
       resources:
         - nodes
         - pods
         - secrets
         - services
         - namespaces
       verbs:
         - get
         - list
         - watch
   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRoleBinding
   metadata:
     labels:
       app.kubernetes.io/name: alb-ingress-controller
     name: alb-ingress-controller
   roleRef:
     apiGroup: rbac.authorization.k8s.io
     kind: ClusterRole
     name: alb-ingress-controller
   subjects:
     - kind: ServiceAccount
       name: alb-ingress-controller
       namespace: kube-system
   ---
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     labels:
       app.kubernetes.io/name: alb-ingress-controller
     name: alb-ingress-controller
     namespace: kube-system
   ```

   (3) POLICY-EKS-IAM 정책을 Ingress Controller와 연결

   ```shell
   eksctl create iamserviceaccount --region $AWS_REGION --name alb-ingress-controller --namespace kube-system --cluster $CLUSTER_NAME --attach-policy-arn arn:aws:iam::104818303680:policy/POLICY-EKS-IAM --override-existing-serviceaccounts --approve
   ```

   (4) Ingress Controller 배포

   ```yaml
   # Application Load Balancer (ALB) Ingress Controller Deployment Manifest.
   # This manifest details sensible defaults for deploying an ALB Ingress Controller.
   # GitHub: https://github.com/kubernetes-sigs/aws-alb-ingress-controller
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     labels:
       app.kubernetes.io/name: alb-ingress-controller
     name: alb-ingress-controller
     # Namespace the ALB Ingress Controller should run in. Does not impact which
     # namespaces it's able to resolve ingress resource for. For limiting ingress
     # namespace scope, see --watch-namespace.
     namespace: kube-system
   spec:
     selector:
       matchLabels:
         app.kubernetes.io/name: alb-ingress-controller
     template:
       metadata:
         labels:
           app.kubernetes.io/name: alb-ingress-controller
       spec:
         containers:
           - name: alb-ingress-controller
             args:
               # Limit the namespace where this ALB Ingress Controller deployment will
               # resolve ingress resources. If left commented, all namespaces are used.
               # - --watch-namespace=your-k8s-namespace
   
               # Setting the ingress-class flag below ensures that only ingress resources with the
               # annotation kubernetes.io/ingress.class: "alb" are respected by the controller. You may
               # choose any class you'd like for this controller to respect.
               - --ingress-class=alb
   
               # REQUIRED
               # Name of your cluster. Used when naming resources created
               # by the ALB Ingress Controller, providing distinction between
               # clusters.
               # - --cluster-name=devCluster
   
               # AWS VPC ID this ingress controller will use to create AWS resources.
               # If unspecified, it will be discovered from ec2metadata.
               # - --aws-vpc-id=vpc-xxxxxx
   
               # AWS region this ingress controller will operate in.
               # If unspecified, it will be discovered from ec2metadata.
               # List of regions: http://docs.aws.amazon.com/general/latest/gr/rande.html#vpc_region
               # - --aws-region=us-west-1
   
               # Enables logging on all outbound requests sent to the AWS API.
               # If logging is desired, set to true.
               # - --aws-api-debug
   
               # Maximum number of times to retry the aws calls.
               # defaults to 10.
               # - --aws-max-retries=10
             env:
               # AWS key id for authenticating with the AWS API.
               # This is only here for examples. It's recommended you instead use
               # a project like kube2iam for granting access.
               # - name: AWS_ACCESS_KEY_ID
               #   value: KEYVALUE
   
               # AWS key secret for authenticating with the AWS API.
               # This is only here for examples. It's recommended you instead use
               # a project like kube2iam for granting access.
               # - name: AWS_SECRET_ACCESS_KEY
               #   value: SECRETVALUE
             # Repository location of the ALB Ingress Controller.
             image: docker.io/amazon/aws-alb-ingress-controller:v1.1.8
         serviceAccountName: alb-ingress-controller
   ```

