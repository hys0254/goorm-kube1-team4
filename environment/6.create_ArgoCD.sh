#/bin/bash

# 윤식씨 Confluence argocd 배포 방법 글 참고

# ArgoCD Pod 배포
echo '>>>>>> Install ArgoCD Start'
echo ''
## argocd namespace 생성
kubectl create namespace argocd

## argocd 작업 디렉토리생성
mkdir -p ArgoCD

## argocd pod 배포
echo '>>> Deploy argocd pod'
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
echo ''


## argocd CLI 설치 시작
VERSION=`curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'`
echo 'ArgoCD Version : '${VERSION}
echo ''
echo '>> Install ArgoCD CLI'
sudo curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/${VERSION}/argocd-linux-amd64
sudo chmod +x /usr/local/bin/argocd
echo ''

echo '>> Check PATH for ArgoCD CLI'
if [[ `grep 'PATH=/usr/local/bin:$PATH' ~/.bashrc` ]];
then
  echo 'export PATH exist';
else
  echo 'export PATH not exist / export PATH will be inserted';
  echo 'export PATH=/usr/local/bin:$PATH' >> ~/.bashrc
fi
echo ''

if [[ `grep '# export PATH=$HOME/bin:/usr/local/bin:$PATH' ~/.zshrc` ]];
then
  echo 'export PATH not exist & edit ~/.zshrc';
  sed -i 's/# export PATH/export PATH/' ~/.zshrc
else
  echo 'export PATH exist';
fi
echo ''

echo '>> Mapping argocd and ALB with type, ingress'
kubectl patch svc argocd-server -n argocd -p '{"spec" : {"type" : "NodePort"}}'

if [[ `grep "hostzone" ~/.zshrc` ]];
then
  domain=`grep "hostzone" ~/.zshrc | cut -f 2 -d "="`
else
  domain=`grep "hostzone" ~/.bashrc | cut -f 2 -d "="`
fi

domainId=`aws route53 list-hosted-zones | jq -r '.HostedZones[] | select(.Name=="'${domain}'.") | .Id'`
ACM_ARN=`aws acm list-certificates | jq -r '.CertificateSummaryList | select(.[].DomainName=="'${domain}'") | .[].CertificateArn'`

echo ''
echo 'Domain = '${domain}
echo 'Domain_Id = '${domainId}
echo 'ACM ARN = '${ACM_ARN}
echo ''

cat > ArgoCD/ingress.yaml <<EOF
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: argocd-ingress
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/certificate-arn: ${ACM_ARN}
    alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-2016-08
    alb.ingress.kubernetes.io/backend-protocol: HTTPS
    alb.ingress.kubernetes.io/healthcheck-path: /login
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80,"HTTPS": 443}]'
    alb.ingress.kubernetes.io/actions.ssl-redirect: '{"Type": "redirect", "RedirectConfig": { "Protocol": "HTTPS", "Port": "443", "StatusCode": "HTTP_301"}}'
  labels:
    app: argocd-ingress
spec:
  rules:
    - http:
        paths:
          - backend:
              serviceName: ssl-redirect
              servicePort: use-annotation
    - host: argocd.${domain}
      http:
        paths:
          - backend:
              serviceName: argocd-server
              servicePort: 443
EOF

kubectl apply -f ArgoCD/ingress.yaml

echo ''

## argocd에 admin 권한 부여
echo '>> Create Admin cluterrole for ArgoCD '
kubectl create clusterrolebinding default-admin --clusterrole=admin --serviceaccount=argocd:default

