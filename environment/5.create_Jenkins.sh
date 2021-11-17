#/bin/bash

# https://velog.io/@aylee5/EKS-Helm%EC%9C%BC%EB%A1%9C-Jenkins-%EB%B0%B0%ED%8F%AC-MasterSlave-%EA%B5%AC%EC%A1%B0-with-Persistent-VolumeEBS  참고

# Jenkins Pod 배포

## jenkins namespace 생성
kubectl create namespace jenkins

## jenkins 작업 디렉토리
mkdir -p Jenkins

#####  StorageClass 와 PersistentVolumeClaim 생성 (jenkins-pvc.yaml 생성 및 실행)
# jenkins-pvc.yaml 파일 생성
cat > Jenkins/jenkins-pvc.yaml <<EOF
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: jenkins-sc
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jenkins-pvc
  namespace: jenkins
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: jenkins-sc
  resources:
    requests:
      storage: 30Gi
EOF

# jenkins-pvc.yaml 실행
kubectl apply -f Jenkins/jenkins-pvc.yaml

sleep 5

#####  jenkins serviceAccount 생성 -> jenkins pod가 API 서버와 상호작용 할 수 있도록 생성
cat > Jenkins/jenkins-sa.yaml <<EOF
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins
  namespace: jenkins
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: jenkins
rules:
- apiGroups:
  - '*'
  resources:
  - statefulsets
  - services
  - replicationcontrollers
  - replicasets
  - podtemplates
  - podsecuritypolicies
  - pods
  - pods/log
  - pods/exec
  - podpreset
  - poddisruptionbudget
  - persistentvolumes
  - persistentvolumeclaims
  - jobs
  - endpoints
  - deployments
  - deployments/scale
  - daemonsets
  - cronjobs
  - configmaps
  - namespaces
  - events
  - secrets
  verbs:
  - create
  - get
  - watch
  - delete
  - list
  - patch
  - update
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - get
  - list
  - watch
  - update
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: jenkins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: jenkins
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:serviceaccounts:jenkins
EOF

# jenkins-sa.yaml 실행
kubectl apply -f Jenkins/jenkins-sa.yaml

sleep 5

# jenkins DNS 세팅용
if [[ `grep "hostzone" ~/.zshrc` ]];
then
  hostzone=`grep "hostzone" ~/.zshrc | cut -f 2 -d "="`
else
  hostzone=`grep "hostzone" ~/.bashrc | cut -f 2 -d "="`  
fi

hostzoneId=`aws route53 list-hosted-zones | jq -r '.HostedZones[] | select(.Name=="'${hostzone}'.") | .Id'`
ACM_ARN=`aws acm list-certificates | jq -r '.CertificateSummaryList | select(.[].DomainName=="'${hostzone}'") | .[].CertificateArn'`

echo ''
echo 'Domain = '${hostzone}
echo 'Domain_Id = '${hostzoneId}
echo 'ACM ARN = '${ACM_ARN}
echo ''

###### jenkins-values.yaml 생성
cat > Jenkins/jenkins-values.yaml <<EOF
---
clusterZone: "cluster.local"
renderHelmLabels: true
controller:
  componentName: "jenkins-controller"
  image: "jenkins/jenkins"
  tagLabel: jdk11
  imagePullPolicy: "Always"
  imagePullSecretName:
  lifecycle:
  disableRememberMe: false
  numExecutors: 0
  executorMode: "NORMAL"
  markupFormatter: plainText
  customJenkinsLabels: []
  adminSecret: true
  hostNetworking: false
  adminUser: "admin"
  admin:
    existingSecret: ""
    userKey: jenkins-admin-user
    passwordKey: jenkins-admin-password
  jenkinsHome: "/var/jenkins_home"
  jenkinsRef: "/usr/share/jenkins/ref"
  jenkinsWar: "/usr/share/jenkins/jenkins.war"
  resources:
    requests:
      cpu: "50m"
      memory: "256Mi"
    limits:
      cpu: "2000m"
      memory: "4096Mi"
  usePodSecurityContext: true
  runAsUser: 1000
  fsGroup: 1000
  securityContextCapabilities: {}
  servicePort: 80
  targetPort: 8080
  serviceType: "NodePort"
  serviceExternalTrafficPolicy:
  serviceAnnotations: 
    external-dns.alpha.kubernetes.io/hostname: jenkins.${hostzone}
  ingress:
    enabled: true
    paths: []
    apiVersion: networking.k8s.io/v1
    labels: {}
  #    app: jenkins-ingress
    annotations:
  # Route53 서비스용 annotation 추가
      external-dns.alpha.kubernetes.io/hostname: jenkins.${hostzone}
      kubernetes.io/ingress.class: alb
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: instance
      alb.ingress.kubernetes.io/certificate-arn: ${ACM_ARN}
      alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-2016-08
      alb.ingress.kubernetes.io/backend-protocol: HTTP
      alb.ingress.kubernetes.io/healthcheck-path: /login
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80,"HTTPS": 443}]'
      alb.ingress.kubernetes.io/actions.ssl-redirect: '{"Type": "redirect", "RedirectConfig": { "Protocol": "HTTPS", "Port": "443", "StatusCode": "HTTP_301"}}'
    hostName: jenkins.${hostzone}
    tls:
  secondaryingress:
    enabled: false
    paths: []
    apiVersion: extensions/v1beta1
    labels: {}
    annotations: {}
    hostName: 
    tls:
  statefulSetLabels: {}
  serviceLabels: {}
  podLabels: {}
  healthProbes: true
  probes:
    startupProbe:
      httpGet:
        path: '{{ default "" .Values.controller.jenkinsUriPrefix }}/login'
        port: http
      periodSeconds: 10
      timeoutSeconds: 5
      failureThreshold: 12
      initialDelaySeconds: 60
    livenessProbe:
      failureThreshold: 5
      httpGet:
        path: '{{ default "" .Values.controller.jenkinsUriPrefix }}/login'
        port: http
      periodSeconds: 10
      timeoutSeconds: 5
      initialDelaySeconds: 120 # https://github.com/kubernetes/kubernetes/issues/62594 참고
    readinessProbe:
      failureThreshold: 3
      httpGet:
        path: '{{ default "" .Values.controller.jenkinsUriPrefix }}/login'
        port: http
      periodSeconds: 10
      timeoutSeconds: 10
      initialDelaySeconds: 60
  podDisruptionBudget:
    enabled: false
    apiVersion: "policy/v1beta1"
    annotations: {}
    labels: {}
  agentListenerEnabled: true
  agentListenerPort: 50000
  agentListenerHostPort:
  agentListenerNodePort:
  disabledAgentProtocols:
    - JNLP-connect
    - JNLP2-connect
  csrf:
    defaultCrumbIssuer:
      enabled: true
      proxyCompatability: true
  agentListenerServiceType: "NodePort"
  agentListenerLoadBalancerIP:
  agentListenerServiceAnnotations: {}
#    service.beta.kubernetes.io/aws-load-balancer-internal: "True"
#    service.beta.kubernetes.io/load-balancer-source-ranges: "172.0.0.0/8, 10.0.0.0/8"
  loadBalancerSourceRanges:
    - 0.0.0.0/0
  extraPorts: []
  installPlugins:
    - kubernetes:1.30.1
    - workflow-aggregator:2.6
    - git:4.9.0
    - configuration-as-code:1.53
  installLatestPlugins: true
  installLatestSpecifiedPlugins: false
  additionalPlugins: []
  initializeOnce: false
  overwritePluginsFromImage: true
  enableRawHtmlMarkupFormatter: false
  scriptApproval: []
  initScripts: []
  additionalExistingSecrets: []
  additionalSecrets: []
  secretClaims: []
  cloudName: "kubernetes"
  JCasC:
    defaultConfig: true
    configScripts: {}
    securityRealm: |-
      local:
        allowsSignup: false
        enableCaptcha: false
        users:
        - id: "\${chart-admin-username}"
          name: "Jenkins Admin"
          password: "\${chart-admin-password}"
    authorizationStrategy: |-
      loggedInUsersCanDoAnything:
        allowAnonymousRead: false
  customInitContainers: []
  sidecars:
    configAutoReload:
      enabled: true
      image: kiwigrid/k8s-sidecar:1.14.2
      imagePullPolicy: IfNotPresent
      resources: {}
      reqRetryConnect: 10
      sshTcpPort: 1044
    other: []
  schedulerName: ''
  nodeSelector: 
    alpha.eksctl.io/nodegroup-name: JenkinsNode
  terminationGracePeriodSeconds:
  terminationMessagePath:
  terminationMessagePolicy:
  tolerations: []
  affinity: {}
  priorityClassName:
  podAnnotations: {}
  statefulSetAnnotations: {}
  updateStrategy: {}
  backendconfig:
    enabled: false
    apiVersion: "extensions/v1beta1"
    name:
    labels: {}
    annotations: {}
    spec: {}
  route:
    enabled: false
    labels: {}
    annotations: {}
  hostAliases: []
  prometheus:
    enabled: false
    serviceMonitorAdditionalLabels: {}
    scrapeInterval: 60s
    scrapeEndpoint: /prometheus
    alertingRulesAdditionalLabels: {}
    alertingrules: []
    prometheusRuleNamespace: ''
  testEnabled: true
  httpsKeyStore:
    jenkinsHttpsJksSecretName: ''
    enable: false
    httpPort: 8081
    path: "/var/jenkins_keystore"
    fileName: "keystore.jks"
    password: "password"
    jenkinsKeyStoreBase64Encoded: |
        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
agent:
  enabled: true
  defaultsProviderTemplate: ''
  jenkinsUrl:
  jenkinsTunnel:
  kubernetesConnectTimeout: 5
  kubernetesReadTimeout: 15
  maxRequestsPerHostStr: "32"
  namespace:
  image: "jenkins/inbound-agent"
  tag: "4.11-1"
  workingDir: "/home/jenkins/agent"
  nodeUsageMode: "NORMAL"
  customJenkinsLabels: []
  imagePullSecretName:
  componentName: "jenkins-agent"
  websocket: false
  privileged: false
  runAsUser:
  runAsGroup:
  resources:
    requests:
      cpu: "512m"
      memory: "512Mi"
    limits:
      cpu: "512m"
      memory: "512Mi"
  alwaysPullImage: false
  podRetention: "Never"
  showRawYaml: true
  volumes: 
  - type: PVC
    claimName: jenkins-pvc
    mountPath: /home/jenkins/agent
    readOnly: false
  workspaceVolume: 
    type: PVC
    claimName: jenkins-pvc
    readOnly: false
  envVars: []
  nodeSelector: 
    alpha.eksctl.io/nodegroup-name: JenkinsNode
  command:
  args: "\${computer.jnlpmac} \${computer.name}"
  sideContainerName: "jnlp"
  TTYEnabled: false
  containerCap: 10
  podName: "default"
  idleMinutes: 0
  yamlTemplate: ''
  yamlMergeStrategy: "override"
  connectTimeout: 100
  annotations: {}
  podTemplates: {}
additionalAgents: {}
persistence:
  enabled: true
  existingClaim: jenkins-pvc
  storageClass: jenkins-sc
  annotations: {}
  labels: {}
  accessMode: "ReadWriteMany"
  size: "8Gi"
  volumes:
  mounts:
networkPolicy:
  enabled: false
  apiVersion: networking.k8s.io/v1
  internalAgents:
    allowed: true
    podLabels: {}
    namespaceLabels: {}
  externalAgents: {}
rbac:
  create: true
  readSecrets: false
serviceAccount:
  create: false
  name: jenkins
  annotations: {}
  imagePullSecretName:
serviceAccountAgent:
  create: false
  name: jenkins
  annotations: {}
  imagePullSecretName:
backup:
  enabled: false
  componentName: "backup"
  schedule: "0 2 * * *"
  labels: {}
  serviceAccount:
    create: true
    name:
    annotations: {}
  activeDeadlineSeconds: ''
  image:
    repository: "maorfr/kube-tasks"
    tag: "0.2.0"
  extraArgs: []
  existingSecret: {}
  env: []
  resources:
    requests:
      memory: 1Gi
      cpu: 1
    limits:
      memory: 1Gi
      cpu: 1
  destination: "s3://jenkins-data/backup"
  onlyJobs: false
  usePodSecurityContext: true
  runAsUser: 1000
  fsGroup: 1000
  securityContextCapabilities: {}
checkDeprecation: true
awsSecurityGroupPolicies:
  enabled: false
  policies:
    - name: ''
      securityGroupIds: []
      podSelector: {}
EOF

## 서브넷 변경 -> 본인의 클러스터 가용 영역이 2곳이 아닌 경우, 하단의 MYSUBNET, sed 명령어 라인을 주석처리하고, 상단의 jenkins-values.yaml EOF 영역에서 subnetid를 수동으로 입력해 사용해 주세요.
echo ''
MYSUBNET=`eksctl get cluster -n ${CLUSTER_NAME} -o json | jq '.[].ResourcesVpcConfig.SubnetIds[]' | sed 's/\"//g' | sed '/$/N;s/\n/,/' | tail -1`
sed -i 's/service.beta.kubernetes.io\/aws-load-balancer-subnets:\ /service.beta.kubernetes.io\/aws-load-balancer-subnets\:\ '${MYSUBNET}'/g' Jenkins/jenkins-values.yaml
echo ''

## jenkins 레퍼지토리 추가
echo '>>> Adding jenkins Repo with helm'
helm repo add jenkinsci https://charts.jenkins.io
helm repo update
echo ''
echo '> jenkins Repo update Finished '

## jenkins-values.yaml에 정의한 내용으로 클러스터에 jenkins 배포
echo ''
echo '>>>>>> Install jenkins with Helm <<<<<<'
helm install jenkins -n jenkins -f Jenkins/jenkins-values.yaml jenkinsci/jenkins
echo ''
echo '## Install Jenkins Finished ##'

