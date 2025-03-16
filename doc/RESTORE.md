# 로컬 환경에서 ETCD 클러스터, APISIX, Dashboard 복구 가이드

https://grok.com/share/bGVnYWN5_e4d501d8-ed81-4b95-be90-0a5035986666  


이 가이드는 S3에 저장된 ETCD 클러스터의 백업 스냅샷을 사용하여 로컬 환경에서 5노드 ETCD 클러스터, APISIX, Dashboard를 Docker Compose를 통해 복구하는 방법을 설명합니다. 백업 데이터가 복구된 ETCD 5, APISIX, Dashboard가 로컬에서 정상적으로 구동될 수 있도록 단계별로 안내합니다.

---

## 사전 준비

- **필요한 도구**:  
  - Docker 및 Docker Compose가 설치되어 있어야 합니다.  
  - AWS CLI가 설치되어 있고, S3 버킷(`s3://theshop-lake/connect/backup/`)에 접근할 수 있는 권한이 설정되어 있어야 합니다.  

- **시스템 요구사항**:  
  - 로컬 머신에 충분한 디스크 공간(ETCD 데이터 디렉토리 및 스냅샷 저장용)과 리소스(5개 ETCD 노드 실행을 위한 CPU/메모리)가 필요합니다.  

- **가정**:  
  - 백업은 ETCD 클러스터의 리더 노드에서 생성된 단일 스냅샷 파일(예: `etcd1_daily_YYYYMMDD_HHmmss.snapshot`)로 S3에 저장되어 있습니다.  
  - 인증 정보는 원본 클러스터와 동일하게 `admin:1234qwer!!`로 설정되어 있습니다.

---

## 복구 프로세스 개요

1. 로컬 디렉토리와 설정 파일을 준비합니다.  
2. S3에서 최신 백업 스냅샷을 다운로드합니다.  
3. 각 ETCD 노드의 데이터 디렉토리에 스냅샷을 복구합니다.  
4. APISIX와 Dashboard 설정 파일을 작성합니다.  
5. Docker Compose 파일을 통해 5노드 ETCD 클러스터, APISIX, Dashboard를 정의하고 실행합니다.  
6. 복구된 클러스터와 서비스의 정상 동작을 확인합니다.

---

## 단계별 가이드

### 1. 로컬 디렉토리 준비

ETCD 데이터 디렉토리와 APISIX, Dashboard 설정 파일을 저장할 디렉토리를 생성합니다.

```bash
mkdir -p ./etcd-data/etcd1 ./etcd-data/etcd2 ./etcd-data/etcd3 ./etcd-data/etcd4 ./etcd-data/etcd5
mkdir -p ./apisix ./dashboard
```

- `./etcd-data/etcd[1-5]`: 각 ETCD 노드의 데이터 디렉토리입니다.  
- `./apisix`, `./dashboard`: APISIX와 Dashboard의 설정 파일을 저장할 디렉토리입니다.

### 2. S3에서 백업 스냅샷 다운로드

AWS CLI를 사용하여 S3에서 최신 백업 스냅샷을 다운로드합니다.

```bash
# S3에서 etcd1의 최신 daily 백업 스냅샷 확인 및 다운로드
aws s3 ls s3://theshop-lake/connect/backup/daily/etcd1/ | sort | tail -n 1 | awk '{print $4}' | xargs -I {} aws s3 cp s3://theshop-lake/connect/backup/daily/etcd1/{} ./snapshot.db
```

- 다운로드된 파일은 `./snapshot.db`로 저장됩니다.  
- **참고**: 실제 환경에서는 백업 날짜와 노드 이름을 확인하여 적절한 스냅샷을 선택하세요.

### 3. 스냅샷을 각 ETCD 노드의 데이터 디렉토리로 복구

`etcdutl snapshot restore` 명령어를 사용하여 스냅샷을 각 ETCD 노드의 데이터 디렉토리에 복구합니다.  
각 노드마다 고유한 `--name`과 `--initial-advertise-peer-urls`를 지정하며, 동일한 `--initial-cluster`를 사용합니다.

```bash
export INITIAL_CLUSTER="etcd1=http://etcd1:2380,etcd2=http://etcd2:2380,etcd3=http://etcd3:2380,etcd4=http://etcd4:2380,etcd5=http://etcd5:2380"
# etcd1 복구
docker run --rm -v $(pwd)/snapshot.db:/snapshot.db -v $(pwd)/etcd-data/etcd1:/bitnami/etcd bitnami/etcd:3.5.18 etcdutl snapshot restore /snapshot.db --data-dir /bitnami/etcd --name etcd1 --initial-cluster $INITIAL_CLUSTER --initial-cluster-token etcd-cluster-1 --initial-advertise-peer-urls http://etcd1:2380

# etcd2 복구
docker run --rm -v $(pwd)/snapshot.db:/snapshot.db -v $(pwd)/etcd-data/etcd2:/bitnami/etcd bitnami/etcd:3.5.18 etcdutl snapshot restore /snapshot.db --data-dir /bitnami/etcd --name etcd2 --initial-cluster $INITIAL_CLUSTER --initial-cluster-token etcd-cluster-1 --initial-advertise-peer-urls http://etcd2:2380

# etcd3 복구
docker run --rm -v $(pwd)/snapshot.db:/snapshot.db -v $(pwd)/etcd-data/etcd3:/bitnami/etcd bitnami/etcd:3.5.18 etcdutl snapshot restore /snapshot.db --data-dir /bitnami/etcd --name etcd3 --initial-cluster $INITIAL_CLUSTER --initial-cluster-token etcd-cluster-1 --initial-advertise-peer-urls http://etcd3:2380

# etcd4 복구
docker run --rm -v $(pwd)/snapshot.db:/snapshot.db -v $(pwd)/etcd-data/etcd4:/bitnami/etcd bitnami/etcd:3.5.18 etcdutl snapshot restore /snapshot.db --data-dir /bitnami/etcd --name etcd4 --initial-cluster $INITIAL_CLUSTER --initial-cluster-token etcd-cluster-1 --initial-advertise-peer-urls http://etcd4:2380

# etcd5 복구
docker run --rm -v $(pwd)/snapshot.db:/snapshot.db -v $(pwd)/etcd-data/etcd5:/bitnami/etcd bitnami/etcd:3.5.18 etcdutl snapshot restore /snapshot.db --data-dir /bitnami/etcd --name etcd5 --initial-cluster $INITIAL_CLUSTER --initial-cluster-token etcd-cluster-1 --initial-advertise-peer-urls http://etcd5:2380
```

- **주의**:  
  - `-v` 옵션으로 스냅샷 파일과 데이터 디렉토리를 컨테이너에 마운트합니다.  
  - 복구된 데이터 디렉토리는 이후 Docker Compose에서 사용됩니다.

### 4. APISIX 및 Dashboard 설정 파일 생성

#### APISIX 설정 (`./apisix/config.yaml`)

```yaml
etcd:
  host:
    - "http://etcd1:2379"
    - "http://etcd2:2379"
    - "http://etcd3:2379"
    - "http://etcd4:2379"
    - "http://etcd5:2379"
  prefix: "/apisix"
  user: "admin"
  password: "1234qwer!!"

apisix:
  node_listen: 9080
  admin_key:
    - name: "admin"
      key: "1234qwer!!"
```

#### Dashboard 설정 (`./dashboard/conf.yaml`)

```yaml
etcd:
  endpoints:
    - "etcd1:2379"
    - "etcd2:2379"
    - "etcd3:2379"
    - "etcd4:2379"
    - "etcd5:2379"
  username: "admin"
  password: "1234qwer!!"
```

- **참고**: Dashboard 설정은 실제 APISIX Dashboard 문서를 참조하여 추가 조정이 필요할 수 있습니다.

### 5. Docker Compose 파일 작성

`docker-compose.yml` 파일을 생성하여 5노드 ETCD 클러스터, APISIX, Dashboard를 정의합니다.

```yaml
version: '3'
services:
  etcd1:
    image: bitnami/etcd:3.5.18
    environment:
      - ETCD_NAME=etcd1
      - ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
      - ETCD_ADVERTISE_CLIENT_URLS=http://etcd1:2379
      - ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380
      - ETCD_INITIAL_ADVERTISE_PEER_URLS=http://etcd1:2380
      - ETCD_INITIAL_CLUSTER=etcd1=http://etcd1:2380,etcd2=http://etcd2:2380,etcd3=http://etcd3:2380,etcd4=http://etcd4:2380,etcd5=http://etcd5:2380
      - ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster-1
      - ETCD_ROOT_PASSWORD=1234qwer!!
    volumes:
      - ./etcd-data/etcd1:/bitnami/etcd
    networks:
      - app-net
    ports:
      - "2379:2379"
      - "2380:2380"

  etcd2:
    image: bitnami/etcd:3.5.18
    environment:
      - ETCD_NAME=etcd2
      - ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
      - ETCD_ADVERTISE_CLIENT_URLS=http://etcd2:2379
      - ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380
      - ETCD_INITIAL_ADVERTISE_PEER_URLS=http://etcd2:2380
      - ETCD_INITIAL_CLUSTER=etcd1=http://etcd1:2380,etcd2=http://etcd2:2380,etcd3=http://etcd3:2380,etcd4=http://etcd4:2380,etcd5=http://etcd5:2380
      - ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster-1
      - ETCD_ROOT_PASSWORD=1234qwer!!
    volumes:
      - ./etcd-data/etcd2:/bitnami/etcd
    networks:
      - app-net
    ports:
      - "3379:2379"
      - "3380:2380"

  etcd3:
    image: bitnami/etcd:3.5.18
    environment:
      - ETCD_NAME=etcd3
      - ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
      - ETCD_ADVERTISE_CLIENT_URLS=http://etcd3:2379
      - ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380
      - ETCD_INITIAL_ADVERTISE_PEER_URLS=http://etcd3:2380
      - ETCD_INITIAL_CLUSTER=etcd1=http://etcd1:2380,etcd2=http://etcd2:2380,etcd3=http://etcd3:2380,etcd4=http://etcd4:2380,etcd5=http://etcd5:2380
      - ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster-1
      - ETCD_ROOT_PASSWORD=1234qwer!!
    volumes:
      - ./etcd-data/etcd3:/bitnami/etcd
    networks:
      - app-net
    ports:
      - "4379:2379"
      - "4380:2380"

  etcd4:
    image: bitnami/etcd:3.5.18
    environment:
      - ETCD_NAME=etcd4
      - ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
      - ETCD_ADVERTISE_CLIENT_URLS=http://etcd4:2379
      - ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380
      - ETCD_INITIAL_ADVERTISE_PEER_URLS=http://etcd4:2380
      - ETCD_INITIAL_CLUSTER=etcd1=http://etcd1:2380,etcd2=http://etcd2:2380,etcd3=http://etcd3:2380,etcd4=http://etcd4:2380,etcd5=http://etcd5:2380
      - ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster-1
      - ETCD_ROOT_PASSWORD=1234qwer!!
    volumes:
      - ./etcd-data/etcd4:/bitnami/etcd
    networks:
      - app-net
    ports:
      - "5379:2379"
      - "5380:2380"

  etcd5:
    image: bitnami/etcd:3.5.18
    environment:
      - ETCD_NAME=etcd5
      - ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
      - ETCD_ADVERTISE_CLIENT_URLS=http://etcd5:2379
      - ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380
      - ETCD_INITIAL_ADVERTISE_PEER_URLS=http://etcd5:2380
      - ETCD_INITIAL_CLUSTER=etcd1=http://etcd1:2380,etcd2=http://etcd2:2380,etcd3=http://etcd3:2380,etcd4=http://etcd4:2380,etcd5=http://etcd5:2380
      - ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster-1
      - ETCD_ROOT_PASSWORD=1234qwer!!
    volumes:
      - ./etcd-data/etcd5:/bitnami/etcd
    networks:
      - app-net
    ports:
      - "6379:2379"
      - "6380:2380"

  apisix:
    image: apache/apisix:latest
    volumes:
      - ./apisix/config.yaml:/usr/local/apisix/conf/config.yaml
    networks:
      - app-net
    ports:
      - "9080:9080"
    depends_on:
      - etcd1
      - etcd2
      - etcd3
      - etcd4
      - etcd5

  dashboard:
    image: apache/apisix-dashboard:latest
    volumes:
      - ./dashboard/conf.yaml:/usr/local/apisix-dashboard/conf/conf.yaml
    networks:
      - app-net
    ports:
      - "9000:9000"
    depends_on:
      - etcd1
      - etcd2
      - etcd3
      - etcd4
      - etcd5

networks:
  app-net:
```

- **설명**:  
  - 각 ETCD 노드는 고유한 클라이언트 포트(2379, 3379, 4379, 5379, 6379)와 피어 포트(2380, 3380, 4380, 5380, 6380)를 호스트에 매핑합니다.  
  - Docker 네트워크(`app-net`)를 통해 컨테이너 간 통신이 가능합니다.  
  - `ETCD_INITIAL_CLUSTER`와 `ETCD_INITIAL_CLUSTER_TOKEN`은 복구 시 사용된 값과 일치합니다.

### 6. 서비스 시작

Docker Compose를 사용하여 모든 서비스를 시작합니다.

```bash
docker-compose up -d
```

- `-d` 옵션으로 백그라운드에서 실행됩니다.

### 7. 복구 확인

#### ETCD 클러스터 상태 확인
컨테이너 접속후 실행
```bash
export ETCDCTL_API=3
etcdctl --endpoints=http://etcd1:2379,http://etcd2:2379,http://etcd3:2379,http://etcd4:2379,http://etcd5:2379  member list 
etcdctl --endpoints=http://etcd1:2379,http://etcd2:2379,http://etcd3:2379,http://etcd4:2379,http://etcd5:2379  endpoint status  --cluster -w table
```

- `<etcd1_container_id>`는 `docker ps`로 확인한 etcd1 컨테이너 ID로 대체하세요.  
- 출력에 5개 노드가 모두 표시되면 클러스터가 정상적으로 복구된 것입니다.

#### APISIX 및 Dashboard 동작 확인

- **APISIX**:  
  ```bash
  curl http://localhost:9080 --head
  ```
  - `HTTP/1.1 404 Not Found` 등의 응답이 반환되면 정상입니다.

- **Dashboard**:  
  브라우저에서 `http://localhost:9000`에 접속하여 Dashboard UI가 표시되는지 확인하세요.

---

## 추가 참고 사항

- **리소스 고려**:  
  로컬 환경에서 5노드 ETCD 클러스터를 실행하려면 충분한 메모리와 CPU가 필요합니다. 리소스가 부족할 경우 3노드로 축소하는 것도 고려하세요.

- **스냅샷 무결성**:  
  복구 전에 `etcdutl snapshot status ./snapshot.db -w table`로 스냅샷의 상태를 확인하여 손상 여부를 점검할 수 있습니다.

- **실제 환경 반영**:  
  APISIX와 Dashboard의 추가 설정(예: 플러그인, 로그 디렉토리 등)이 필요하면 `docker-compose.yml`과 설정 파일을 조정하세요.

---

이 가이드를 따르면 백업 데이터가 복구된 5노드 ETCD 클러스터, APISIX, Dashboard가 로컬 환경에서 Docker Compose를 통해 성공적으로 구동됩니다.