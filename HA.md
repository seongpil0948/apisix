# 1. 개요

**목적**  
- Apache APISIX가 Auto Scaling, Route53 Weighted Routing, ETCD 클러스터를 활용하여 고가용성(HA)으로 운영되는지 검증합니다.  
- API Gateway 간 설정 동기화, 분산 트래픽 및 장애 발생 시 복구(예: 인스턴스/ETCD 노드 스케일 조정)를 테스트합니다.  
- ETCD 클러스터 구성 시 모든 노드가 leader로 표시되는 문제에 대해 원인을 파악하고, 해결 방안을 제시합니다.

**적용 범위**  
- **Test GW**: APISIX 게이트웨스 인스턴스 간 설정 동기화 및 라우팅 테스트  
- **ETCD 클러스터**: 구성 데이터 저장 및 동기화, 클러스터 상태(leader/peer) 확인  
  - 1년 예약 인스턴스 검토(https://www.youtube.com/watch?v=Bg6BJcn9t0s)
- **Auto Scaling Group (ASG)**: APISIX 및 ETCD 노드의 스케일 조정 및 HA 검증  
- **CloudFormation 템플릿**: EC2, ASG, SSM, NLB 등 생성 자원의 정상 동작 여부 점검

---

# 2. 환경 구성 및 주요 설정

### 2.1 APISIX 게이트웨이 구성
- **환경 변수**  
  - `GW_INST_1` 및 `GW_INST_2` 등으로 각각의 APISIX 인스턴스(IP)를 지정  
  - `ADMIN_KEY`를 이용하여 API 관리 권한 부여  
- **포트**  
  - Admin API: 9180  
  - Gateway 서비스: 9080 (HTTP), 기타 포트 80, 443, 9090 등 필요에 따라 오픈

### 2.2 ETCD 클러스터
- **역할**:  
  - APISIX의 설정 정보를 저장하고 동기화하는 백엔드로 사용  
- **문제점**:  
  - 현재 구성에서는 ETCD 클러스터 내 모든 멤버가 leader로 표시되는 현상이 발생함  
    - **해결 방안**:  
      - ETCD를 클러스터 모드로 구성할 때, 각 노드에 대해 올바른 `--initial-cluster` 및 `--initial-cluster-state` 옵션을 지정하여 단일 leader와 다수의 follower가 구성되도록 합니다.  
      - 사용 중인 Docker 이미지(예: Bitnami 등)의 경우 기본 실행 옵션을 재검토하고, 클러스터 모드로 전환하는 추가 옵션을 적용합니다.  
      - 만약 자동 구성이 어려운 경우, `etcdctl member add` 명령어를 이용하여 수동으로 하나씩 클러스터 멤버를 추가하는 방법을 고려합니다.

### 2.3 Auto Scaling 및 CloudFormation 템플릿
- APISIX와 ETCD는 CloudFormation 템플릿으로 생성된 ASG, Launch Template, NLB 등을 통해 자동 확장 및 헬스체크가 구성됩니다.
- Route53을 통해 Weighted Routing 및 Health Check를 수행하여 분산 트래픽을 확인합니다.

---

# 3. 테스트 시나리오

본 섹션에서는 APISIX HA 환경의 주요 테스트 항목과 명령어를 단계별로 제시합니다.

## 3.1 설정 동기화 테스트 (Test GW)

### 목적
- ETCD 클러스터를 통해 두 APISIX 게이트웨이 간 설정(라우트)이 올바르게 동기화되는지 확인합니다.

### 테스트 절차
1. **APISIX 인스턴스 1에 라우트 추가**  
   ```bash
   export GW_INST_1=43.203.226.152
   export ADMIN_KEY="12345"
   curl -i -X PUT http://$GW_INST_1:9180/apisix/admin/routes/1 \
     -H "X-API-KEY: $ADMIN_KEY" \
     -d '{
       "uri": "/ip",
       "methods": ["GET"],
       "upstream": {
         "type": "roundrobin",
         "scheme": "https",
         "nodes": {
           "httpbin.org/ip": 1
         }
       }
     }'
   ```
2. **APISIX 인스턴스 1에서 라우트 호출 확인**  
   ```bash
   curl http://$GW_INST_1:9080/ip
   ```
3. **APISIX 인스턴스 2에서 설정 확인**  
   ```bash
   export GW_INST_2=43.203.142.87
   curl -i -X GET http://$GW_INST_2:9180/apisix/admin/routes/1 \
     -H "X-API-KEY: $ADMIN_KEY"
   ```
4. **APISIX 인스턴스 2에서 라우트 호출 테스트**  
   ```bash
   curl http://$GW_INST_2:9080/ip
   ```
5. **ETCD 키 확인**  
   ```bash
   etcdctl get /apisix/routes/1
   etcdctl get /apisix/ --prefix
   ```

### 기대 결과
- 인스턴스 1에 추가한 라우트 정보가 인스턴스 2에서도 조회 가능해야 하며, 각 인스턴스에서 `/ip` 엔드포인트가 정상 응답해야 합니다.

---

## 3.2 Route53 분산 트래픽 테스트

### 목적
- Route53의 Health Check 및 Weighted Routing을 이용하여 트래픽이 두 APISIX 게이트웨이 인스턴스에 균등하게 분산되는지 확인합니다.

### 테스트 절차
```bash
for i in {1..10}; do dig gw.dwoong.com; done
```
- 반환된 **Answer Section**에서 두 인스턴스(IP)가 균등하게 분산되어 있는지 확인합니다.

### 기대 결과
- DNS 조회 결과가 두 인스턴스의 IP(예: 43.203.226.152, 43.203.142.87)로 번갈아 나오며, 분산 트래픽이 확인되어야 합니다.

---

## 3.3 ETCD 클러스터 테스트

### 목적
- ETCD 클러스터의 상태, 데이터 쓰기/읽기, 로그 및 클러스터 멤버 상태를 확인합니다.
- **주의**: 현재 ETCD 클러스터 구성 시 모든 노드가 leader로 표시되는 문제가 있으므로, 이를 확인하고 해결 방안을 적용합니다.

### 테스트 절차

1. **환경변수 설정 및 버전 확인**
   ```bash
   export ETCDCTL_ENDPOINTS="etcd-EtcdNLB-4bbc0961cb6e07b5.elb.ap-northeast-2.amazonaws.com:2379"
   export ETCDCTL_API=3
   etcdctl version
   ```
2. **ETCD 엔드포인트 헬스 체크**
   ```bash
   etcdctl endpoint health
   ```
3. **데이터 쓰기/읽기 테스트**
   ```bash
   etcdctl put mykey "Hello etcd"
   etcdctl get mykey
   ```
4. **로그 확인**
   ```bash
   journalctl -u etcd -f
   ```
5. **클러스터 상태 확인**
   ```bash
   etcdctl endpoint status --write-out=table
   etcdctl member list
   ```
   
   - **문제점 확인**: 만약 모든 멤버가 leader로 표시된다면, 이는 클러스터 구성 옵션(예: `--initial-cluster`)에 문제가 있을 수 있습니다.
   - **해결 방안**:  
     - ETCD 실행 시 각 노드에 대해 **클러스터 모드**로 올바르게 초기화하도록 다음과 같은 옵션들을 검토합니다.  
       예)
       ```bash
       --initial-cluster "node1=http://<node1-ip>:2380,node2=http://<node2-ip>:2380,node3=http://<node3-ip>:2380" \
       --initial-cluster-state new \
       --initial-advertise-peer-urls http://<current-node-ip>:2380 \
       --listen-peer-urls http://0.0.0.0:2380 \
       --advertise-client-urls http://<current-node-ip>:2379 \
       --listen-client-urls http://0.0.0.0:2379
       ```
     - 만약 자동 구성이 어려울 경우, `etcdctl member add` 명령어를 이용하여 수동으로 노드를 하나씩 추가해 클러스터가 올바르게 형성되도록 합니다.

---

## 3.4 클러스터 HA 검증 (ASG 및 스케일링)

### 목적
- ASG(Auto Scaling Group)를 통한 인스턴스 수 조정(스케일 인/아웃)과 정상 동작 여부를 확인합니다.

### 테스트 절차

#### ASG 인스턴스 확인
```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --profile $AWS_PROFILE
```
- ASG의 인스턴스 상태, Desired, Min, Max 크기 등을 확인합니다.

#### 인스턴스 수 축소 (1로 줄이기)
```bash
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name $ASG_NAME \
  --min-size 1 \
  --max-size 1 \
  --desired-capacity 1 \
  --profile $AWS_PROFILE

etcdctl member list
```
- **기대 결과**: ASG 인스턴스가 1대로 축소되고, ETCD 클러스터 및 APISIX 서비스가 1개 노드로 정상 동작해야 합니다.

#### 인스턴스 수 확장 (3으로 늘리기)
```bash
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name $ASG_NAME \
  --min-size 3 \
  --max-size 3 \
  --desired-capacity 3 \
  --profile $AWS_PROFILE
```
- **기대 결과**: 인스턴스가 3대로 확장되고, 각 노드가 정상적으로 클러스터에 참여하여 서비스 연속성이 보장되어야 합니다.

---

# 4. CloudFormation 템플릿 및 구성 자원 검증

본 템플릿은 APISIX와 ETCD 클러스터를 위한 자원(EC2, ASG, Launch Template, NLB, Route53 RecordSet 등)을 자동으로 생성합니다.

### 4.1 APISIX CloudFormation 템플릿
- **구성 항목**  
  - APISIX 인스턴스용 Launch Template  
  - Auto Scaling Group (ASG)  
  - 보안 그룹, IAM Role/Instance Profile  
  - Route53 RecordSet (HealthCheck, Weighted Routing)  
- **테스트 방법**  
  - 템플릿 배포 후, 생성된 리소스(ASG, NLB, EC2 인스턴스 등)의 상태를 AWS 콘솔 및 CLI로 확인합니다.
  - APISIX 인스턴스의 로그와 HealthCheck 결과를 검증합니다.

### 4.2 ETCD CloudFormation 템플릿
- **구성 항목**  
  - ETCD 인스턴스용 Launch Template  
  - ETCD 클러스터를 구성하는 ASG  
  - NLB 및 Target Group 설정  
- **테스트 방법**  
  - 템플릿 배포 후, ETCD 클러스터의 구성 상태(멤버 목록, 각 노드의 역할 등)를 `etcdctl member list` 등으로 확인합니다.
  - 앞서 언급한 등 leader 문제 해결 방안을 적용하여 클러스터가 정상적으로 단일 leader와 다수의 follower로 구성되는지 검증합니다.

---

# 5. 추가 검증 항목 및 시스템 정보 확인

### 5.1 시스템 정보 및 서비스 상태
- **OS 및 패키지 확인**  
  ```bash
  uname -a
  cat /etc/os-release
  ```
- **서비스 상태 확인 (예: amazon-ssm-agent)**  
  ```bash
  sudo systemctl status amazon-ssm-agent
  sudo dnf updateinfo summary
  ```

### 5.2 Cloud-Init 로그 확인
- User Data 실행 로그는 `/var/log/cloud-init-output.log`에 기록됩니다.
  ```bash
  sudo cat /var/log/cloud-init-output.log
  ```

### 5.3 Systems Manager Automation 기능 테스트
- AWS Systems Manager 콘솔의 **Automation** 메뉴에서 “Run Command” 또는 표준 문서(예: `AWS-UpdateSSMAgent`)를 실행하여 AutomationServiceRole이 올바르게 작동하는지 확인합니다.

### 5.4 CloudWatch 모니터링 테스트
- **EC2 기본 지표**: 인스턴스별 CPUUtilization, 네트워크 트래픽 등  
- **ASG 지표**: GroupDesiredCapacity, InServiceInstances 등을 통해 스케일링 정책 동작을 확인합니다.

### 5.5 스케일링 정책 (Scaling Policies) 동작 테스트
1. **인위적 CPU 부하 생성 (SSM 또는 SSH 접속)**
   ```bash
   sudo yum install -y stress
   stress --cpu 2 --timeout 300
   ```
2. CloudWatch에서 CPU 지표 상승을 확인하고, ASG DesiredCapacity가 정책에 따라 증가하는지 모니터링합니다.

---

# 6. 문제 및 해결 방안: ETCD 클러스터 리더 문제

현재 ETCD 클러스터에서 모든 멤버가 leader로 표시되는 문제는 다음과 같은 원인 및 해결 방안을 검토합니다.

- **원인**:  
  - ETCD가 클러스터 모드로 올바르게 초기화되지 않은 경우, 각 인스턴스가 독립적으로 동작하면서 leader 역할을 수행할 수 있음  
  - Docker 컨테이너 실행 시, 클러스터 관련 옵션(예: `--initial-cluster`, `--initial-cluster-state`)이 누락되었거나 잘못 구성된 경우

- **해결 방안**:  
  1. 각 ETCD 노드에 대해 클러스터 모드로 실행되도록 아래와 같은 옵션을 적용합니다.
     - 예시:
       ```bash
       etcd --initial-cluster "node1=http://<node1-ip>:2380,node2=http://<node2-ip>:2380,node3=http://<node3-ip>:2380" \
            --initial-cluster-state new \
            --initial-advertise-peer-urls http://<current-node-ip>:2380 \
            --listen-peer-urls http://0.0.0.0:2380 \
            --advertise-client-urls http://<current-node-ip>:2379 \
            --listen-client-urls http://0.0.0.0:2379
       ```
  2. 기존 클러스터가 모두 leader로 표시된다면, `etcdctl member add` 명령어를 사용하여 신규 노드를 수동으로 추가한 후, 정상적인 leader/follower 구성이 이루어지도록 재구성합니다.
  3. Docker 이미지(예: Bitnami 등)를 사용하는 경우, 클러스터 모드 전환을 위한 추가 환경 변수나 커맨드를 확인하고 적용합니다.

---

# 7. 결론

본 문서에서는 API_SIX HA 구성 환경에서 APISIX 게이트웨이 간의 설정 동기화, 분산 트래픽, ETCD 클러스터 상태 및 ASG 스케일링 정책의 동작을 단계별로 테스트하는 절차를 제시하였습니다.  
특히 ETCD 클러스터에서 모든 노드가 leader로 표시되는 문제에 대해 원인을 분석하고, 클러스터 모드로 올바르게 초기화하거나, 수동으로 노드를 추가하는 방법을 제시하였습니다.  
이러한 테스트와 검증 절차를 통해, 운영 환경에서 API_SIX가 고가용성 및 안정성을 갖춘 서비스로 동작할 수 있도록 점검하고 개선할 수 있습니다.
