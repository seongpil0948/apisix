# Bitnami Etcd 클러스터 백업 및 복원 정책 문서

<!-- https://claude.ai/chat/552b17e6-8733-4d04-9995-257bd275d5e9 -->

본 문서는 Bitnami Etcd v3 클러스터의 백업 및 복원 정책과 방법을 설명합니다. 두 서버(10.101.99.100, 10.101.99.101)에 걸쳐 총 5개의 Etcd 노드로 구성된 환경에서 안정적인 데이터 관리를 위한 백업, 복원 및 테스트 방안을 제공합니다.

## 목차

1. [환경 개요](#1-환경-개요)
2. [백업 정책](#2-백업-정책)
3. [백업 절차](#3-백업-절차)
4. [복원 절차](#4-복원-절차)
5. [로컬 복원 테스트](#5-로컬-복원-테스트)
6. [장애 시나리오 및 대응 방안](#6-장애-시나리오-및-대응-방안)
7. [백업 및 복원 자동화](#7-백업-및-복원-자동화)
8. [모니터링 및 알림 체계](#8-모니터링-및-알림-체계)
9. [부록: 명령어 참조](#9-부록-명령어-참조)

---

## 1. 환경 개요

### 1.1 인프라 구성

현재 Etcd 클러스터는 다음과 같이 구성되어 있습니다:

- **서버 A (GW-PROD-1, 10.101.99.100)**
  - etcd1: 클라이언트 포트 2379, 피어 포트 2380
  - etcd2: 클라이언트 포트 3379, 피어 포트 3380

- **서버 B (GW-PROD-2, 10.101.99.101)**
  - etcd3: 클라이언트 포트 2379, 피어 포트 2380
  - etcd4: 클라이언트 포트 3379, 피어 포트 3380
  - etcd5: 클라이언트 포트 4379, 피어 포트 4380

### 1.2 데이터 저장 경로

- **컨테이너 내부 데이터 경로**: `/bitnami/etcd`
- **호스트 데이터 마운트 경로**: `/shared/etcd/data/etcd[1-5]`
- **스냅샷 저장 경로**: `/shared/etcd/snapshot/etcd[1-5]`
- **복원 시 스냅샷 초기화 경로**: `/shared/etcd/snapshot-init/etcd[1-5]`

### 1.3 의존성

- **APISIX 게이트웨이**: Etcd 클러스터에 구성 정보를 저장하고 있음
- **APISIX 대시보드**: Etcd 클러스터를 통해 구성 관리

---

## 2. 백업 정책

### 2.1 백업 유형

1. **정기 스냅샷 백업**
   - 정의: `etcdctl snapshot save` 명령을 사용하여 Etcd의 일관된 상태 스냅샷을 생성
   - 주기: 일 1회 (자정)
   - 보관: 최근 7일 백업 유지

2. **증분 백업**
   - 정의: Etcd의 WAL(Write Ahead Log) 파일 백업
   - 주기: 3시간마다
   - 보관: 최근 24시간분 유지

3. **수동 백업**
   - 정의: 주요 구성 변경 전 수행하는 백업
   - 주기: 관리자 판단에 따라 수행
   - 보관: 최소 30일

### 2.2 백업 로테이션 및 보관 정책

| 백업 유형 | 보관 정책 | 스토리지 위치 |
|---------|----------|--------------|
| 일별 스냅샷 | 7일 | 로컬: `/shared/etcd/snapshot/etcd[1-5]/daily/` |
| 증분 백업 | 24시간 | 로컬: `/shared/etcd/snapshot/etcd[1-5]/incremental/` |
| 수동 백업 | 30일 | 로컬: `/shared/etcd/snapshot/etcd[1-5]/manual/` |
| 원격 복제 | 30일 | 원격 스토리지 (별도 구성 필요) |

### 2.3 백업 파일 명명 규칙

```
etcd{노드번호}_{백업유형}_{날짜}_{시간}.snapshot
```

예시: `etcd1_daily_20250208_000000.snapshot`

---

## 3. 백업 절차

### 3.1 스냅샷 백업 생성

스냅샷 백업은 다음 절차에 따라 수행합니다:

```bash
# 환경 변수 설정
export ETCDCTL_API=3
export ETCD_ENDPOINTS="http://10.101.99.100:2379,http://10.101.99.100:3379,http://10.101.99.101:2379,http://10.101.99.101:3379,http://10.101.99.101:4379"
export ETCD_USER="admin"
export ETCD_PASSWORD="1234qwer!!"
export BACKUP_DATE=$(date +%Y%m%d_%H%M%S)

# 백업 디렉토리 생성
mkdir -p /shared/etcd/snapshot/etcd1/daily

# 스냅샷 백업 실행
etcdctl --endpoints=$ETCD_ENDPOINTS \
  --user=$ETCD_USER:$ETCD_PASSWORD \
  snapshot save /shared/etcd/snapshot/etcd1/daily/etcd1_daily_${BACKUP_DATE}.snapshot

# 백업 무결성 검증
etcdctl --endpoints=$ETCD_ENDPOINTS \
  --user=$ETCD_USER:$ETCD_PASSWORD \
  snapshot status /shared/etcd/snapshot/etcd1/daily/etcd1_daily_${BACKUP_DATE}.snapshot -w table
```

### 3.2 증분 백업 생성

증분 백업은 Etcd 데이터 디렉토리의 WAL 파일을 복사하여 수행합니다:

```bash
# 환경 변수 설정
export BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
export NODE_NUM=1  # 백업 대상 노드 번호

# 증분 백업 디렉토리 생성
mkdir -p /shared/etcd/snapshot/etcd${NODE_NUM}/incremental/${BACKUP_DATE}

# WAL 파일 복사
cp -rp /shared/etcd/data/etcd${NODE_NUM}/member/wal \
  /shared/etcd/snapshot/etcd${NODE_NUM}/incremental/${BACKUP_DATE}/
```

### 3.3 백업 파일 압축 및 메타데이터 저장

백업 파일을 압축하고 메타데이터를 함께 저장합니다:

```bash
# 백업 파일 압축
tar -czf /shared/etcd/snapshot/etcd${NODE_NUM}/daily/etcd${NODE_NUM}_daily_${BACKUP_DATE}.tar.gz \
  /shared/etcd/snapshot/etcd${NODE_NUM}/daily/etcd${NODE_NUM}_daily_${BACKUP_DATE}.snapshot

# 메타데이터 저장
cat > /shared/etcd/snapshot/etcd${NODE_NUM}/daily/etcd${NODE_NUM}_daily_${BACKUP_DATE}.meta <<EOF
Backup Type: Daily Snapshot
Date: $(date)
Etcd Version: $(docker exec etcd${NODE_NUM} etcd --version | head -1)
Cluster Size: 5 nodes
Endpoints: $ETCD_ENDPOINTS
EOF

# SHA256 해시 생성
sha256sum /shared/etcd/snapshot/etcd${NODE_NUM}/daily/etcd${NODE_NUM}_daily_${BACKUP_DATE}.tar.gz \
  > /shared/etcd/snapshot/etcd${NODE_NUM}/daily/etcd${NODE_NUM}_daily_${BACKUP_DATE}.sha256
```

### 3.4 백업 로테이션

오래된 백업 파일을 정책에 따라 삭제합니다:

```bash
# 7일 이상 된 일별 백업 삭제
find /shared/etcd/snapshot/etcd${NODE_NUM}/daily/ -name "etcd${NODE_NUM}_daily_*.tar.gz" -mtime +7 -delete
find /shared/etcd/snapshot/etcd${NODE_NUM}/daily/ -name "etcd${NODE_NUM}_daily_*.meta" -mtime +7 -delete
find /shared/etcd/snapshot/etcd${NODE_NUM}/daily/ -name "etcd${NODE_NUM}_daily_*.sha256" -mtime +7 -delete
find /shared/etcd/snapshot/etcd${NODE_NUM}/daily/ -name "etcd${NODE_NUM}_daily_*.snapshot" -mtime +7 -delete

# 24시간 이상 된 증분 백업 삭제
find /shared/etcd/snapshot/etcd${NODE_NUM}/incremental/ -type d -mtime +1 -exec rm -rf {} \;
```

---

## 4. 복원 절차

### 4.1 복원 준비

복원 전 다음 사항을 확인합니다:

1. 모든 Etcd 노드 중지
2. 데이터 디렉토리 백업
3. 복원할 스냅샷 파일 무결성 검증

```bash
# 모든 Etcd 컨테이너 중지
docker stop etcd1 etcd2 etcd3 etcd4 etcd5

# 기존 데이터 디렉토리 백업
RESTORE_DATE=$(date +%Y%m%d_%H%M%S)
for i in {1..5}; do
  mkdir -p /shared/etcd/backup-before-restore/etcd${i}_${RESTORE_DATE}
  cp -rp /shared/etcd/data/etcd${i}/* /shared/etcd/backup-before-restore/etcd${i}_${RESTORE_DATE}/
done

# 스냅샷 무결성 검증
export SNAPSHOT_FILE="/shared/etcd/snapshot/etcd1/daily/etcd1_daily_20250208_000000.snapshot"
etcdctl snapshot status $SNAPSHOT_FILE -w table
```

### 4.2 스냅샷 복원

선택한 스냅샷으로 Etcd 데이터를 복원합니다:

```bash
# 환경 변수 설정
export ETCDCTL_API=3
export SNAPSHOT_FILE="/shared/etcd/snapshot/etcd1/daily/etcd1_daily_20250208_000000.snapshot"
export NODE_NUM=1  # 복원 대상 노드 번호

# 데이터 디렉토리 클리어
rm -rf /shared/etcd/data/etcd${NODE_NUM}/*

# 스냅샷 복원
etcdctl snapshot restore $SNAPSHOT_FILE \
  --name etcd${NODE_NUM} \
  --initial-cluster "etcd1=http://10.101.99.100:2380,etcd2=http://10.101.99.100:3380,etcd3=http://10.101.99.101:2380,etcd4=http://10.101.99.101:3380,etcd5=http://10.101.99.101:4380" \
  --initial-cluster-token etcd-cluster-1 \
  --initial-advertise-peer-urls http://10.101.99.100:2380 \
  --data-dir=/shared/etcd/data/etcd${NODE_NUM}

# 디렉토리 권한 설정
chown -R 1003:1003 /shared/etcd/data/etcd${NODE_NUM}
```

### 4.3 Etcd 클러스터 재시작

복원 후 클러스터를 재시작합니다:

```bash
# 첫 번째 노드 시작 (리더 역할)
docker start etcd1

# 클러스터 상태 확인
sleep 5
export ETCDCTL_API=3
etcdctl --endpoints=http://10.101.99.100:2379 \
  --user=admin:1234qwer!! \
  member list -w table

# 나머지 노드 순차적으로 시작
docker start etcd2
sleep 3
docker start etcd3
sleep 3
docker start etcd4
sleep 3
docker start etcd5
```

### 4.4 복원 검증

복원된 데이터를 검증합니다:

```bash
# 클러스터 상태 확인
export ETCDCTL_API=3
etcdctl --endpoints=http://10.101.99.100:2379 \
  --user=admin:1234qwer!! \
  endpoint health -w table

# 데이터 샘플 확인
etcdctl --endpoints=http://10.101.99.100:2379 \
  --user=admin:1234qwer!! \
  get --prefix /apisix --limit=5
```

### 4.5 APISIX 재시작

복원 후 APISIX 서비스를 재시작합니다:

```bash
# APISIX 컨테이너 재시작
docker restart apisix-gateway
docker restart apisix-dashboard

# APISIX 헬스 체크
curl -I http://10.101.99.100:9080
```

---

## 5. 로컬 복원 테스트

복원 절차의 유효성을 검증하기 위해 정기적으로 로컬 복원 테스트를 수행합니다.

### 5.1 테스트 환경 준비

테스트 용도의 독립된 환경을 준비합니다:

```bash
# 테스트용 디렉토리 생성
mkdir -p /shared/etcd/test-restore/{data,logs}

# 백업 스냅샷 복사
cp /shared/etcd/snapshot/etcd1/daily/etcd1_daily_20250208_000000.snapshot \
  /shared/etcd/test-restore/
```

### 5.2 테스트 복원 실행

테스트 환경에 스냅샷을 복원합니다:

```bash
# 환경 변수 설정
export ETCDCTL_API=3
export SNAPSHOT_FILE="/shared/etcd/test-restore/etcd1_daily_20250208_000000.snapshot"

# 스냅샷 복원
etcdctl snapshot restore $SNAPSHOT_FILE \
  --name test-etcd \
  --initial-cluster "test-etcd=http://127.0.0.1:12380" \
  --initial-advertise-peer-urls http://127.0.0.1:12380 \
  --data-dir=/shared/etcd/test-restore/data

# 디렉토리 권한 설정
chown -R 1003:1003 /shared/etcd/test-restore/data
```

### 5.3 테스트 Etcd 실행

복원된 데이터로 테스트 Etcd 인스턴스를 실행합니다:

```bash
docker run -d --name test-etcd \
  --user 1003:1003 \
  -p 12379:2379 \
  -p 12380:2380 \
  -v /shared/etcd/test-restore/data:/bitnami/etcd \
  -v /shared/etcd/test-restore/logs:/opt/bitnami/etcd/logs \
  -e ETCD_NAME="test-etcd" \
  -e ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379" \
  -e ETCD_ADVERTISE_CLIENT_URLS="http://127.0.0.1:12379" \
  -e ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380" \
  -e ETCD_INITIAL_ADVERTISE_PEER_URLS="http://127.0.0.1:12380" \
  -e ETCD_INITIAL_CLUSTER="test-etcd=http://127.0.0.1:12380" \
  -e ETCD_INITIAL_CLUSTER_STATE="new" \
  -e ETCD_INITIAL_CLUSTER_TOKEN="test-etcd-cluster" \
  -e ETCD_ROOT_PASSWORD="1234qwer!!" \
  bitnami/etcd:3.5.18
```

### 5.4 데이터 검증

복원된 데이터의 무결성을 확인합니다:

```bash
# 데이터 확인
export ETCDCTL_API=3
etcdctl --endpoints=http://127.0.0.1:12379 \
  --user=root:1234qwer!! \
  get --prefix /apisix --limit=10

# 키 개수 확인
etcdctl --endpoints=http://127.0.0.1:12379 \
  --user=root:1234qwer!! \
  get --prefix /apisix --count-only
```

### 5.5 테스트 APISIX 실행 (선택 사항)

복원된 데이터로 테스트 APISIX 인스턴스를 실행합니다:

```bash
# 테스트용 APISIX 설정 파일 생성
cat > /shared/etcd/test-restore/apisix-test.yaml <<EOF
etcd:
  host:
    - "http://127.0.0.1:12379"
  prefix: "/apisix"
  user: "root"
  password: "1234qwer!!"

apisix:
  node_listen: 19080
  admin_key:
    - name: "admin"
      key: "1234qwer!!"
EOF

# 테스트 APISIX 실행
docker run -d --name test-apisix \
  -p 19080:19080 \
  -v /shared/etcd/test-restore/apisix-test.yaml:/usr/local/apisix/conf/config.yaml \
  apache/apisix:latest
```

### 5.6 테스트 정리

테스트 완료 후 리소스를 정리합니다:

```bash
# 테스트 컨테이너 정지 및 삭제
docker stop test-etcd test-apisix
docker rm test-etcd test-apisix

# 테스트 디렉토리 백업 (선택 사항)
tar -czf /shared/etcd/test-restore/test-results-$(date +%Y%m%d_%H%M%S).tar.gz \
  /shared/etcd/test-restore/{data,logs}

# 테스트 데이터 정리
rm -rf /shared/etcd/test-restore/data/*
rm -rf /shared/etcd/test-restore/logs/*
```

---

## 6. 장애 시나리오 및 대응 방안

### 6.1 단일 노드 장애

**시나리오**: 5개 노드 중 1개 노드가 장애 발생

**대응 방안**:

1. 장애 노드 컨테이너 상태 확인
   ```bash
   docker inspect etcd1
   ```

2. 장애 노드 재시작 시도
   ```bash
   docker restart etcd1
   ```

3. 재시작 후 클러스터 상태 확인
   ```bash
   etcdctl --endpoints=$ETCD_ENDPOINTS \
     --user=$ETCD_USER:$ETCD_PASSWORD \
     endpoint health -w table
   ```

4. 재시작으로 해결되지 않을 경우, 노드 교체
   ```bash
   # 장애 노드 제거
   docker stop etcd1
   docker rm etcd1
   
   # 데이터 디렉토리 백업
   mv /shared/etcd/data/etcd1 /shared/etcd/data/etcd1.bak-$(date +%Y%m%d_%H%M%S)
   mkdir -p /shared/etcd/data/etcd1
   chown -R 1003:1003 /shared/etcd/data/etcd1
   
   # 새 노드 추가 (기존 클러스터에 동적 추가)
   MEMBER_ID=$(etcdctl --endpoints=$ETCD_ENDPOINTS --user=$ETCD_USER:$ETCD_PASSWORD \
     member add etcd1 --peer-urls=http://10.101.99.100:2380 | grep 'ID' | awk '{print $2}')
   
   # 새 노드 시작
   docker run -d \
     --restart unless-stopped \
     --user 1003:1003 \
     -p 2379:2379 \
     -p 2380:2380 \
     -v /shared/etcd/data/etcd1:/bitnami/etcd \
     -v /shared/etcd/snapshot/etcd1:/snapshots \
     -v /shared/etcd/snapshot-init/etcd1:/init-snapshot \
     -e ETCD_NAME="etcd1" \
     -e ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379" \
     -e ETCD_ADVERTISE_CLIENT_URLS="http://10.101.99.100:2379" \
     -e ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380" \
     -e ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.101.99.100:2380" \
     -e ETCD_INITIAL_CLUSTER="etcd1=http://10.101.99.100:2380,etcd2=http://10.101.99.100:3380,etcd3=http://10.101.99.101:2380,etcd4=http://10.101.99.101:3380,etcd5=http://10.101.99.101:4380" \
     -e ETCD_INITIAL_CLUSTER_STATE="existing" \
     -e ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-1" \
     -e ETCD_ROOT_PASSWORD="1234qwer!!" \
     -e ALLOW_NONE_AUTHENTICATION=yes \
     bitnami/etcd:3.5.18
   ```

### 6.2 다중 노드 장애 (쿼럼 손실)

**시나리오**: 5개 노드 중 3개 이상 노드가 장애 발생 (쿼럼 손실)

**대응 방안**:

1. 클러스터 상태 확인
   ```bash
   etcdctl --endpoints=$ETCD_ENDPOINTS \
     --user=$ETCD_USER:$ETCD_PASSWORD \
     endpoint health -w table
   ```

2. 모든 노드 중지
   ```bash
   for i in {1..5}; do docker stop etcd$i; done
   ```

3. 최신 스냅샷 파일 확인
   ```bash
   ls -lart /shared/etcd/snapshot/etcd1/daily/
   ```

4. 모든 노드에 스냅샷 복원 (4.2절 참조)

5. 클러스터 재시작 (4.3절 참조)

### 6.3 데이터 손상

**시나리오**: Etcd 데이터 손상 발생

**대응 방안**:

1. 데이터 무결성 확인
   ```bash
   etcdctl --endpoints=$ETCD_ENDPOINTS \
     --user=$ETCD_USER:$ETCD_PASSWORD \
     check perf
   ```

2. 의심되는 노드 식별
   ```bash
   for i in {1..5}; do
     echo "=== Checking etcd$i ==="
     etcdctl --endpoints=http://10.101.99.$([ $i -le 2 ] && echo "100" || echo "101"):$([ $i -le 2 ] && echo "$((i+1))379" || echo "$i379") \
       --user=$ETCD_USER:$ETCD_PASSWORD \
       endpoint status -w table
   done
   ```

3. 손상된 노드 교체 (6.1절 참조) 또는 스냅샷에서 전체 클러스터 복원 (4절 참조)

---

## 7. 백업 및 복원 자동화

### 7.1 백업 자동화 스크립트

백업 작업을 자동화하기 위한 쉘 스크립트입니다:

```bash
#!/bin/bash
# 파일명: /shared/etcd/scripts/backup_etcd.sh

# 환경 변수 설정

```bash
export ETCDCTL_API=3
export ETCD_ENDPOINTS="http://10.101.99.100:2379,http://10.101.99.100:3379,http://10.101.99.101:2379,http://10.101.99.101:3379,http://10.101.99.101:4379"
export ETCD_USER="admin"
export ETCD_PASSWORD="1234qwer!!"
export BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
export BACKUP_TYPE=${1:-daily}  # 인자로 백업 유형 전달 (기본값: daily)
export NODE_NUM=${2:-1}  # 인자로 노드 번호 전달 (기본값: 1)

# 백업 디렉토리 생성
mkdir -p /shared/etcd/snapshot/etcd${NODE_NUM}/${BACKUP_TYPE}

# 로그 설정
LOG_FILE="/shared/etcd/logs/backup_${BACKUP_TYPE}_${BACKUP_DATE}.log"
mkdir -p /shared/etcd/logs

# 로그 함수
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

# 백업 시작
log "Starting ${BACKUP_TYPE} backup for etcd${NODE_NUM}"

# 스냅샷 백업 실행
log "Creating snapshot backup"
etcdctl --endpoints=$ETCD_ENDPOINTS \
  --user=$ETCD_USER:$ETCD_PASSWORD \
  snapshot save /shared/etcd/snapshot/etcd${NODE_NUM}/${BACKUP_TYPE}/etcd${NODE_NUM}_${BACKUP_TYPE}_${BACKUP_DATE}.snapshot >> $LOG_FILE 2>&1

if [ $? -ne 0 ]; then
  log "ERROR: Snapshot backup failed"
  exit 1
fi

# 백업 무결성 검증
log "Verifying snapshot integrity"
SNAPSHOT_STATUS=$(etcdctl --endpoints=$ETCD_ENDPOINTS \
  --user=$ETCD_USER:$ETCD_PASSWORD \
  snapshot status /shared/etcd/snapshot/etcd${NODE_NUM}/${BACKUP_TYPE}/etcd${NODE_NUM}_${BACKUP_TYPE}_${BACKUP_DATE}.snapshot -w json)

echo $SNAPSHOT_STATUS >> $LOG_FILE

# 메타데이터 저장
log "Saving metadata"
cat > /shared/etcd/snapshot/etcd${NODE_NUM}/${BACKUP_TYPE}/etcd${NODE_NUM}_${BACKUP_TYPE}_${BACKUP_DATE}.meta <<EOF
Backup Type: ${BACKUP_TYPE}
Date: $(date)
Etcd Version: $(docker exec -it etcd${NODE_NUM} etcd --version 2>/dev/null | head -1 || echo "N/A")
Cluster Size: 5 nodes
Endpoints: $ETCD_ENDPOINTS
Snapshot Details: 
$SNAPSHOT_STATUS
EOF

# 백업 압축
log "Compressing backup"
tar -czf /shared/etcd/snapshot/etcd${NODE_NUM}/${BACKUP_TYPE}/etcd${NODE_NUM}_${BACKUP_TYPE}_${BACKUP_DATE}.tar.gz \
  /shared/etcd/snapshot/etcd${NODE_NUM}/${BACKUP_TYPE}/etcd${NODE_NUM}_${BACKUP_TYPE}_${BACKUP_DATE}.snapshot

# SHA256 해시 생성
log "Generating SHA256 hash"
sha256sum /shared/etcd/snapshot/etcd${NODE_NUM}/${BACKUP_TYPE}/etcd${NODE_NUM}_${BACKUP_TYPE}_${BACKUP_DATE}.tar.gz \
  > /shared/etcd/snapshot/etcd${NODE_NUM}/${BACKUP_TYPE}/etcd${NODE_NUM}_${BACKUP_TYPE}_${BACKUP_DATE}.sha256

# 백업 로테이션 (유형에 따라 다른 보관 기간 적용)
if [ "$BACKUP_TYPE" = "daily" ]; then
  log "Rotating daily backups (keeping 7 days)"
  find /shared/etcd/snapshot/etcd${NODE_NUM}/${BACKUP_TYPE}/ -name "etcd${NODE_NUM}_${BACKUP_TYPE}_*.tar.gz" -mtime +7 -delete
  find /shared/etcd/snapshot/etcd${NODE_NUM}/${BACKUP_TYPE}/ -name "etcd${NODE_NUM}_${BACKUP_TYPE}_*.meta" -mtime +7 -delete

```