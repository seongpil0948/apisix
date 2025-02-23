아래는 공식 문서를 참고하여 기존 가이드를 검증하고 보완한, Bitnami Etcd (v3) 클러스터의 백업 및 복구(Disaster Recovery)와 APISIX 연동 가이드입니다.  
이 가이드는 TLS/CERT 없이 사용자 인증(ETCD_ROOT_PASSWORD)을 사용하는 환경에서, 정적 부트스트랩(및 추가 옵션: revision bump, 멤버십 업데이트)을 포함하여 클러스터를 백업하고 복구하는 전체 프로세스를 설명합니다.

---

# Bitnami Etcd 클러스터 백업, 복구 및 APISIX 연동 (Disaster Recovery) 가이드

**목표:**  
- 두 서버(10.101.99.100, 10.101.99.101)에 걸쳐 5개 노드로 구성된 Etcd 클러스터를 도커 컨테이너로 배포하고,  
- 클러스터의 데이터 백업 및 복구(Disaster Recovery)를 통해, 예상치 못한 장애 발생 시에도 데이터 손실 없이 클러스터를 재구성하며,  
- APISIX가 Etcd 클러스터와 연동하여 설정 정보를 관리할 수 있도록 구성합니다.

> **참고:**  
> - etcd는 (N-1)/2까지의 영구 장애를 견딜 수 있으나, 쿼럼 손실 시 클러스터는 복구가 필요합니다.  
> - 복구 시 스냅샷 복원은 백업 시점 이후의 업데이트가 포함되지 않으므로, 특히 Kubernetes와 같이 캐시(Informer)를 사용하는 환경에서는 “revision bump” 및 “mark compacted” 옵션을 고려해야 합니다.  
> - 모든 컨테이너 실행 시 반드시 유효한 ETCD_ROOT_PASSWORD (예: `"1234qwer!!"`)를 설정하고, 비루트 사용자(예: UID 1003)로 실행하세요.

---

## 1. 클러스터 부트스트랩 개요

etcd 클러스터 부트스트랩 방식은 사전에 멤버들의 IP와 포트를 알고 있는 **정적 부트스트랩** 방식을 기본으로 하며,  
필요에 따라 etcd Discovery 또는 DNS Discovery 옵션도 적용할 수 있습니다.

### 1.1 정적 부트스트랩 초기 설정

모든 노드는 동일한 초기 구성 정보를 사용합니다.

```bash
export ETCD_INITIAL_CLUSTER="etcd1=http://10.101.99.100:2380,etcd2=http://10.101.99.100:3380,etcd3=http://10.101.99.101:2380,etcd4=http://10.101.99.101:3380,etcd5=http://10.101.99.101:4380"
export ETCD_INITIAL_CLUSTER_STATE="new"
export ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-1"
```

> **주의:**  
> 모든 노드는 동시에 기동되어야 하며, 나중에 노드를 추가할 경우 `ETCD_INITIAL_CLUSTER_STATE`를 `"existing"`으로 변경한 후 `etcdctl member add`를 사용합니다.

---

## 2. 클러스터 구성 및 APISIX 연동

### 2.1 클러스터 구성 개요

- **서버 A (10.101.99.100):**  
  - **etcd1:** 클라이언트: 2379, 피어: 2380  
  - **etcd2:** 클라이언트: 3379, 피어: 3380

- **서버 B (10.101.99.101):**  
  - **etcd3:** 클라이언트: 2379, 피어: 2380  
  - **etcd4:** 클라이언트: 3379, 피어: 3380  
  - **etcd5:** 클라이언트: 4379, 피어: 4380

### 2.2 APISIX 연동

APISIX는 Etcd v3 클러스터의 클라이언트 엔드포인트를 통해 설정 정보를 관리합니다.  
APISIX 설정 파일 (config.yaml) 예시는 아래와 같습니다.

```yaml
etcd:
  # Etcd v3 클라이언트 엔드포인트 (TLS 없이 HTTP 사용)
  host:
    - "http://10.101.99.100:2379"
    - "http://10.101.99.100:3379"
    - "http://10.101.99.101:2379"
    - "http://10.101.99.101:3379"
    - "http://10.101.99.101:4379"
  prefix: "/apisix"
  # etcdctl로 생성한 사용자 정보 (여기서는 root 계정 사용)
  user: "root"
  password: "1234qwer!!"

apisix:
  node_listen: 9080
  admin_key:
    - name: "admin"
      key: "1234qwer!!"
```

APISIX 컨테이너는 config.yaml 파일과 ETCDCTL_API=3 환경변수를 사용해 실행합니다.

```bash
docker run -d \
  -p 9080:9080 \
  -v /path/to/config.yaml:/usr/local/apisix/conf/config.yaml \
  -e ETCDCTL_API=3 \
  apache/apisix:latest
```

---

## 3. 백업 수행

### 3.1 스냅샷 백업

클러스터에서 정상 노드(예: etcd1)에 접속하여, etcdctl snapshot save 명령어로 스냅샷 파일을 생성합니다.

```bash
ETCDCTL_API=3 etcdctl --user="root:1234qwer!!" --endpoints=http://10.101.99.100:2379 snapshot save ~/etcd-backup/backup.db
```

> **참고:**  
> 스냅샷은 etcd 데이터와 함께 WAL(Write-Ahead Log)에 포함된 아직 디스크에 기록되지 않은 데이터는 반영하지 않을 수 있으므로, 라이브 멤버에서 스냅샷을 생성하는 것이 권장됩니다.

### 3.2 백업 파일 검증

백업 파일의 상태(해시, revision, 총 키 수, 총 크기 등)를 확인합니다.

```bash
ETCDCTL_API=3 etcdctl snapshot status ~/etcd-backup/backup.db --write-out=table
```

출력 예시:

```
+---------+----------+------------+------------+
|  HASH   | REVISION | TOTAL KEYS | TOTAL SIZE |
+---------+----------+------------+------------+
| 7ef846e |   485261 |      11642 |      94 MB |
+---------+----------+------------+------------+
```

---

## 4. 복구 (Snapshot Restore) 수행

클러스터가 심각한 장애로 인해 쿼럼을 잃은 경우, 스냅샷 복원 기능을 사용해 새로운 클러스터를 구성할 수 있습니다.

### 4.1 기본 Snapshot 복원

단순 복원의 경우, 백업 파일을 기반으로 새로운 데이터 디렉토리를 생성합니다.

```bash
etcdctl snapshot restore ~/etcd-backup/backup.db \
  --data-dir ~/etcd-backup/restored-data \
  --initial-cluster "$ETCD_INITIAL_CLUSTER" \
  --initial-advertise-peer-urls "http://10.101.99.100:2380" \
  --initial-cluster-token "$ETCD_INITIAL_CLUSTER_TOKEN" \
  --name "etcd-restored"
```

> **설명:**  
> 복원 시 복원된 데이터 디렉토리는 기존 클러스터와 완전히 분리된 새로운 클러스터로 동작하게 됩니다.  
> 복원 과정 중 기존 snapshot 메타데이터(멤버 ID, 클러스터 ID)는 덮어쓰여집니다.

### 4.2 Revision Bump 및 Mark Compacted 옵션

특히 Kubernetes와 같이 watch API를 사용하는 환경에서 복원 시 revision이 크게 뒤로 떨어지면 캐시 불일치 문제가 발생할 수 있습니다.  
이 경우, --bump-revision와 --mark-compacted 옵션을 사용하여 모든 revision을 올려 복원합니다.

```bash
etcdctl snapshot restore ~/etcd-backup/backup.db \
  --bump-revision 1000000000 \
  --mark-compacted \
  --data-dir ~/etcd-backup/restored-data \
  --initial-cluster "$ETCD_INITIAL_CLUSTER" \
  --initial-advertise-peer-urls "http://10.101.99.100:2380" \
  --initial-cluster-token "$ETCD_INITIAL_CLUSTER_TOKEN" \
  --name "etcd-restored"
```

> **참고:**  
> --bump-revision 옵션은 현재 스냅샷의 revision에 정해진 값을 더하여, 클라이언트(예: 컨트롤러)가 watch를 통해 알림을 받지 못하는 문제를 방지합니다.

### 4.3 복원 후 도커 컨테이너 기동

복원된 데이터 디렉토리를 각 노드에 마운트하여 도커 컨테이너를 실행합니다.  
아래는 서버 A의 etcd1 노드를 복원하여 기동하는 예시입니다.

```bash
# 복원된 데이터 디렉토리의 소유권 변경 (UID 1003)
sudo chown -R 1003:1003 ~/etcd-backup/restored-data

docker run -d \
  --restart unless-stopped \
  --user 1003:1003 \
  -p 2379:2379 \
  -p 2380:2380 \
  -v /home/<사용자>/etcd-backup/restored-data:/bitnami/etcd \
  -e ETCD_NAME="etcd-restored" \
  -e ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379" \
  -e ETCD_ADVERTISE_CLIENT_URLS="http://10.101.99.100:2379" \
  -e ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380" \
  -e ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.101.99.100:2380" \
  -e ETCD_INITIAL_CLUSTER="$ETCD_INITIAL_CLUSTER" \
  -e ETCD_INITIAL_CLUSTER_STATE="new" \
  -e ETCD_INITIAL_CLUSTER_TOKEN="$ETCD_INITIAL_CLUSTER_TOKEN" \
  -e ETCD_ROOT_PASSWORD="1234qwer!!" \
  bitnami/etcd:3.5.18
```

> **주의:**  
> 각 노드를 복원할 때 백업 시점의 초기 구성 정보와 동일하게 설정해야 하며, 모든 노드를 동시에 기동해야 정적 부트스트랩이 올바르게 완료됩니다.

---

## 5. 복구 후 검증

복구된 클러스터의 정상 동작 여부를 아래 단계로 확인합니다.

### 5.1 클러스터 상태 확인

인증 정보를 포함하여 etcdctl 명령어로 멤버 목록을 조회합니다.

```bash
alias ec='ETCDCTL_API=3 etcdctl --user="root:1234qwer!!" --endpoints=http://10.101.99.100:2379'
ec member list -w=table
```

모든 복원된 노드가 정상적으로 목록에 나타나야 합니다.

### 5.2 데이터 일관성 확인

기존에 기록된 키(예: `/test/message`)를 조회하여 데이터 일관성을 확인합니다.

```bash
ec get /test/message
```

### 5.3 APISIX 관련 데이터 확인

APISIX가 사용하는 `/apisix` 접두어의 키들이 복원되었는지 확인합니다.

```bash
ec get --prefix /apisix
```

---

## 6. 데이터 손상 및 복구 옵션 (추가 내용)

etcd는 내부적으로 데이터 손상을 감지하기 위한 기능을 제공합니다.  
만약 멤버 간 상태 불일치(데이터 부패)가 감지되면, 다음과 같은 복구 방법을 고려할 수 있습니다.

### 6.1 멤버 상태 초기화 (Purge Member Persistent State)

- **절차:**  
  1. 해당 멤버를 중지합니다.  
  2. etcd 데이터 디렉토리에서 snap 하위 디렉토리를 백업 후 제거합니다.  
  3. --initial-cluster-state=existing 옵션으로 해당 멤버를 재기동하면, 클러스터 리더로부터 최신 스냅샷을 다운로드합니다.

### 6.2 멤버 교체 (Replace Member)

- **절차:**  
  1. 해당 멤버를 중지하고 데이터 디렉토리를 제거합니다.  
  2. etcdctl member remove 명령어로 클러스터에서 제거합니다.  
  3. etcdctl member add 명령어로 새 멤버를 추가한 후, 새 데이터 디렉토리로 기동합니다.

### 6.3 전체 클러스터 복원 (Restore Whole Cluster)

- **절차:**  
  1. 리더 노드에서 스냅샷을 생성합니다.  
  2. 각 노드에서 스냅샷 복원 절차를 통해 새로운 데이터 디렉토리를 생성합니다.  
  3. 모든 노드를 새 클러스터로 기동하여 복원합니다.

> **참고:**  
> 복원 작업 후 클러스터 내 데이터 일관성과 손상 여부를 반드시 확인하고, 정기적인 스냅샷과 데이터 검증을 통해 DR(Disaster Recovery) 계획을 유지하세요.

---

## 7. 결론

본 가이드를 통해 다음 사항을 달성할 수 있습니다:

- **백업:**  
  - etcdctl snapshot save 명령어를 사용하여 클러스터 전체 스냅샷을 생성하고, snapshot status로 검증합니다.
- **복구:**  
  - 스냅샷 복원 명령어(기본 또는 --bump-revision/--mark-compacted 옵션 포함)를 사용하여 새로운 데이터 디렉토리에 데이터를 재구성합니다.
  - 복원된 데이터를 각 노드에 마운트하고, 정적 부트스트랩 방식으로 도커 컨테이너를 기동합니다.
- **검증:**  
  - etcdctl 명령어를 이용해 클러스터 멤버 목록, 데이터 및 APISIX 관련 키의 일관성을 확인합니다.
- **데이터 손상 복구:**  
  - 부패된 멤버의 복구 또는 전체 클러스터 복원 옵션을 통해 DR 상황에 대응할 수 있습니다.
- **APISIX 연동:**  
  - APISIX는 Etcd의 클라이언트 엔드포인트와 인증 정보를 포함한 설정으로 연동되어, 클러스터 내 키-값 데이터를 관리합니다.

이와 같이 구성하면, 두 서버에 걸쳐 5개 노드로 안정적인 Bitnami Etcd 클러스터를 도커 컨테이너로 구동하고,  
Disaster Recovery 시나리오에 따라 데이터를 백업 및 복구할 수 있으며, APISIX와의 연동도 문제없이 유지할 수 있습니다.
