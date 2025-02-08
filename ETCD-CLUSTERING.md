아래는 TLS/CERT 관련 내용 없이 사용자 인증(ETCD_ROOT_PASSWORD) 설정을 유지하면서, 클러스터 부트스트랩 방식(정적 부트스트랩, etcd Discovery, DNS Discovery) 내용을 반영한 Bitnami Etcd 클러스터와 APISIX 연동 가이드입니다.

---

# Bitnami Etcd (etcd v3) 클러스터 부트스트랩 및 APISIX 연동 가이드

이 문서는 두 서버(10.101.99.100, 10.101.99.101)에 걸쳐 총 5개의 Etcd 노드를 도커 컨테이너로 배포하고,  
APISIX가 Etcd 클러스터와 통신하도록 구성하는 방법과 함께, 클러스터 부트스트랩 방식(정적 부트스트랩, etcd Discovery, DNS Discovery)에 대해 설명합니다.

> **중요 사전 준비 및 주의사항:**
>
> - **비루트 실행:**  
>   각 컨테이너는 일반적으로 UID 1001(비루트 사용자)로 실행되므로,  
>   데이터가 위치한 호스트 디렉토리의 소유권을 반드시 UID 1001로 변경하세요.
>
> - **정적 부트스트랩 시 동시 기동 필수:**  
>   정적 부트스트랩 방식은 모든 노드가 동시에 기동되어야 올바른 피어 연결이 형성됩니다.  
>   (만약 일부 노드만 먼저 기동하면 해당 노드들은 클러스터의 일부로 인식되지 않고 독립적으로 동작할 수 있습니다.)
>   **노드 추가 시에는 클러스터 부팅 후 `etcdctl member add` 명령어를 이용한 동적 가입 방법을 사용하세요.**
>
> - **사용자 인증 관련 환경변수:**  
>   현재 Bitnami Etcd 컨테이너는 ETCD_ROOT_PASSWORD(및 필요 시 ETCD_ROOT_USER) 환경변수가  
>   설정되지 않으면 “ETCD_ROOT_PASSWORD environment variable is empty or not set” 오류를 발생시킵니다.  
>   - 인증을 사용하려면 유효한 값을 설정해야 하며 (예: `-e ETCD_ROOT_PASSWORD="1234qwer!!"`),  
>   - 인증 없이 사용하려면 대신 `-e ALLOW_NONE_AUTHENTICATION=yes`를 추가하세요.  
>   (단, 인증 없이 사용하는 것은 개발 환경에서만 권장됩니다.)

---

## 1. 클러스터 부트스트랩 방식 개요

etcd 클러스터 부트스트랩은 각 멤버가 서로의 주소를 사전에 알고 있느냐에 따라 아래 세 가지 방식 중 선택할 수 있습니다.

- **정적 부트스트랩 (Static Bootstrapping):**  
  클러스터 멤버들의 IP 및 포트가 사전에 확정되어 있는 경우,  
  각 노드에 `ETCD_INITIAL_CLUSTER`, `ETCD_INITIAL_CLUSTER_STATE`, `ETCD_INITIAL_CLUSTER_TOKEN` 등의 환경변수(또는 명령줄 인자)를 지정하여 부트스트랩합니다.
  
- **etcd Discovery:**  
  클러스터 멤버들의 IP가 미리 결정되지 않은 환경에서는,  
  기존의 디스커버리 서비스를 통해 클러스터를 부트스트랩할 수 있습니다.  
  각 노드는 고유한 이름을 가지며, 생성된 디스커버리 URL(예: https://discovery.etcd.io/...)을 `--discovery` 옵션(또는 환경변수 ETCD_DISCOVERY)으로 지정합니다.
  
- **DNS Discovery:**  
  DNS SRV 레코드를 이용하여 클러스터 멤버들을 자동으로 검색할 수 있습니다.  
  이 경우 각 노드는 `--discovery-srv` 옵션(또는 환경변수 ETCD_DISCOVERY_SRV)으로 DNS 도메인을 지정하여 부트스트랩합니다.

> **참고:**  
> 부트스트랩 방식은 클러스터 초기 구성에만 적용되며, 클러스터가 부팅된 이후에는 환경변수나 인자로 전달한 초기 구성 값은 무시됩니다.  
> 변경 사항(예: 멤버 추가/삭제)은 런타임 재구성을 통해 적용해야 합니다.

---

## 2. 클러스터 구성 개요

### 2.1 Etcd 노드 배포

- **서버 A (10.101.99.100):** 2개 컨테이너  
  - **etcd1:**  
    - **호스트 포트:** 2379 (클라이언트), 2380 (피어)
  - **etcd2:**  
    - **호스트 포트:** 3379 (클라이언트), 3380 (피어)

- **서버 B (10.101.99.101):** 3개 컨테이너  
  - **etcd3:**  
    - **호스트 포트:** 2379 (클라이언트), 2380 (피어)
  - **etcd4:**  
    - **호스트 포트:** 3379 (클라이언트), 3380 (피어)
  - **etcd5:**  
    - **호스트 포트:** 4379 (클라이언트), 4380 (피어)

### 2.2 정적 부트스트랩 초기 설정

모든 노드는 아래와 같이 **동일한 초기 클러스터 구성** 정보를 사용합니다.

```bash
ETCD_INITIAL_CLUSTER="etcd1=http://10.101.99.100:2380,etcd2=http://10.101.99.100:3380,etcd3=http://10.101.99.101:2380,etcd4=http://10.101.99.101:3380,etcd5=http://10.101.99.101:4380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-1"
```

**반드시 모든 노드를 동시에 기동**해야 합니다.  
> 이미 부트스트랩된 클러스터에 새 노드를 추가할 경우, 해당 노드의 `ETCD_INITIAL_CLUSTER_STATE`를 `"existing"`으로 변경하고,  
> `etcdctl member add` 명령어를 이용해 동적 가입시키세요.

---

## 3. Etcd 컨테이너 배포 (정적 부트스트랩 방식)

Bitnami Etcd 이미지(버전 3.5.18)를 사용하며, 모든 설정은 환경변수로 전달합니다.  
**주의:** 컨테이너 내부에서는 리스닝 주소를 `0.0.0.0`으로 지정하고,  
광고(Advertise) 주소에는 실제 호스트 IP와 포트를 사용합니다.

### 3.1 공통 환경변수

모든 컨테이너는 아래의 환경변수를 공유합니다:



> **인증 관련 환경변수:**  
> 모든 컨테이너 실행 시 유효한 ETCD_ROOT_PASSWORD 값을 반드시 설정해야 합니다.  
> (예제에서는 `-e ETCD_ROOT_PASSWORD="1234qwer!!"` 사용)  
> 인증 없이 사용하고자 할 경우 대신 `ALLOW_NONE_AUTHENTICATION=yes`를 추가하세요.

---

### 3.2 서버 A (IP: 10.101.99.100)

#### **etcd1 컨테이너**

```bash
docker run -d \
  --restart unless-stopped \
  --user 1003:1003 \
  -p 2379:2379 \
  -p 2380:2380 \
  -v /shared/etcd/data/etcd1:/bitnami/etcd \
  -e ETCD_NAME="etcd1" \
  -e ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379" \
  -e ETCD_ADVERTISE_CLIENT_URLS="http://10.101.99.100:2379" \
  -e ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380" \
  -e ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.101.99.100:2380" \
  -e ETCD_INITIAL_CLUSTER="$ETCD_INITIAL_CLUSTER" \
  -e ETCD_INITIAL_CLUSTER_STATE="new" \
  -e ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-1" \
  -e ETCD_ROOT_PASSWORD="1234qwer!!" \
  bitnami/etcd:3.5.18
```

#### **etcd2 컨테이너**

```bash
docker run -d \
  --restart unless-stopped \
  --user 1003:1003 \
  -p 3379:2379 \
  -p 3380:2380 \
  -v /shared/etcd/data/etcd2:/bitnami/etcd \
  -e ETCD_NAME="etcd2" \
  -e ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379" \
  -e ETCD_ADVERTISE_CLIENT_URLS="http://10.101.99.100:3379" \
  -e ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380" \
  -e ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.101.99.100:3380" \
  -e ETCD_INITIAL_CLUSTER="$ETCD_INITIAL_CLUSTER" \
  -e ETCD_INITIAL_CLUSTER_STATE="new" \
  -e ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-1" \
  -e ETCD_ROOT_PASSWORD="1234qwer!!" \
  bitnami/etcd:3.5.18
```

---

### 3.3 서버 B (IP: 10.101.99.101)

#### **etcd3 컨테이너**

```bash
export ETCD_INITIAL_CLUSTER="etcd1=http://10.101.99.100:2380,etcd2=http://10.101.99.100:3380,etcd3=http://10.101.99.101:2380,etcd4=http://10.101.99.101:3380,etcd5=http://10.101.99.101:4380"

docker run -d \
  --restart unless-stopped \
  --user 1003:1003 \
  -p 2379:2379 \
  -p 2380:2380 \
  -v /shared/etcd/data/etcd3:/bitnami/etcd \
  -e ETCD_NAME="etcd3" \
  -e ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379" \
  -e ETCD_ADVERTISE_CLIENT_URLS="http://10.101.99.101:2379" \
  -e ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380" \
  -e ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.101.99.101:2380" \
  -e ETCD_INITIAL_CLUSTER="$ETCD_INITIAL_CLUSTER" \
  -e ETCD_INITIAL_CLUSTER_STATE="new" \
  -e ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-1" \
  -e ETCD_ROOT_PASSWORD="1234qwer!!" \
  bitnami/etcd:3.5.18
```

#### **etcd4 컨테이너**

```bash
docker run -d \
  --restart unless-stopped \
  --user 1003:1003 \
  -p 3379:2379 \
  -p 3380:2380 \
  -v /shared/etcd/data/etcd4:/bitnami/etcd \
  -e ETCD_NAME="etcd4" \
  -e ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379" \
  -e ETCD_ADVERTISE_CLIENT_URLS="http://10.101.99.101:3379" \
  -e ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380" \
  -e ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.101.99.101:3380" \
  -e ETCD_INITIAL_CLUSTER="$ETCD_INITIAL_CLUSTER" \
  -e ETCD_INITIAL_CLUSTER_STATE="new" \
  -e ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-1" \
  -e ETCD_ROOT_PASSWORD="1234qwer!!" \
  bitnami/etcd:3.5.18
```

#### **etcd5 컨테이너**

```bash
docker run -d \
  --restart unless-stopped \
  --user 1003:1003 \
  -p 4379:2379 \
  -p 4380:2380 \
  -v /shared/etcd/data/etcd5:/bitnami/etcd \
  -e ETCD_NAME="etcd5" \
  -e ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379" \
  -e ETCD_ADVERTISE_CLIENT_URLS="http://10.101.99.101:4379" \
  -e ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380" \
  -e ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.101.99.101:4380" \
  -e ETCD_INITIAL_CLUSTER="$ETCD_INITIAL_CLUSTER" \
  -e ETCD_INITIAL_CLUSTER_STATE="new" \
  -e ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-1" \
  -e ETCD_ROOT_PASSWORD="1234qwer!!" \
  bitnami/etcd:3.5.18
```

---

## 4. 네트워크 및 피어 통신 확인

- **피어 포트 개방:**  
  각 서버 간 피어 통신에 사용되는 포트(2380, 3380, 4380 등)가 방화벽이나 네트워크 정책에 의해 차단되지 않았는지 확인하세요.
  
- **동일 초기 클러스터 변수 확인:**  
  모든 컨테이너가 동일한 `ETCD_INITIAL_CLUSTER` 값을 전달받고 있는지, 그리고 환경변수 설정이 올바른지 점검합니다.
  
- **정적 부트스트랩 기동 순서:**  
  모든 노드를 **동시에 기동**하여 정적 부트스트랩 방식으로 클러스터를 구성합니다.  
  (순차 기동 시, 최초 부트스트랩 후 새 노드를 추가하려면 `ETCD_INITIAL_CLUSTER_STATE`를 `"existing"`으로 설정하고 `etcdctl member add`를 사용하세요.)

---

## 5. 클러스터 부트스트랩 방식 선택 (추가 옵션)

클러스터 부트스트랩 방식은 환경에 따라 아래와 같이 선택할 수 있습니다.

### 5.1 정적 부트스트랩 (Static Bootstrapping)

- **개요:**  
  위 섹션 2 및 3에 설명된 방식처럼, 각 노드가 서로의 IP와 포트를 알고 있을 때 환경변수(또는 명령줄 인자)를 이용하여 클러스터를 부트스트랩합니다.
  
- **주의:**  
  각 노드의 `--initial-advertise-peer-urls` 값이 초기 클러스터 구성에 명시된 URL과 정확히 일치해야 합니다.

### 5.2 etcd Discovery

- **개요:**  
  클러스터 멤버의 IP가 사전에 확정되지 않은 경우,  
  내부 또는 공용 디스커버리 서비스를 이용해 부트스트랩할 수 있습니다.
  
- **예시 (Bitnami 컨테이너 내 환경변수 사용):**

  ```bash
  -e ETCD_NAME="etcd1" \
  -e ETCD_DISCOVERY="https://discovery.etcd.io/<generated-token>"
  ```
  
  위와 같이 각 노드에 고유한 이름과 생성된 디스커버리 URL을 지정하면, 디스커버리 서비스가 클러스터 크기를 관리하고 멤버 등록을 수행합니다.
  
- **주의:**  
  각 노드는 고유한 이름이어야 하며, 클러스터 생성 전 디스커버리 서비스에 예상 클러스터 크기를 등록해야 합니다.

### 5.3 DNS Discovery

- **개요:**  
  DNS SRV 레코드를 사용하여 클러스터 멤버를 자동으로 찾을 수 있습니다.  
  이 경우 각 노드는 `ETCD_DISCOVERY_SRV` 환경변수(또는 `--discovery-srv` 인자)를 사용하여 DNS 도메인을 지정합니다.
  
- **예시:**

  ```bash
  -e ETCD_NAME="etcd1" \
  -e ETCD_DISCOVERY_SRV="example.com"
  ```
  
- **주의:**  
  DNS SRV 레코드에 등록된 A 레코드의 IP와, 각 노드의 `--initial-advertise-peer-urls` 값이 일치해야 하며, 노드별 고유한 이름이 필요합니다.

> **오류 처리 및 주의 사항:**  
> - 초기 클러스터 구성에 누락된 멤버가 있다면 "not listed in the initial cluster config" 오류가 발생할 수 있습니다.  
> - 동일한 클러스터 토큰을 사용하여 고유한 클러스터 ID가 생성되도록 해야 하며, 부트스트랩 중 멤버 이름이 중복되지 않아야 합니다.

---

## 6. APISIX와 Etcd 연동

APISIX는 Etcd v3 클러스터의 클라이언트 엔드포인트를 이용해 설정 정보를 관리합니다.  
클러스터 부팅 후, etcdctl을 이용해 사용자 생성한 후 아래와 같이 APISIX 설정 파일에 인증 정보를 포함하여 연동합니다.

### 6.1 APISIX 설정 파일 (config.yaml) 예시

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
  # 클러스터 부팅 후, etcdctl로 사용자 생성 후 적용
  user: "admin"
  password: "1234qwer!!"

apisix:
  node_listen: 9080
  admin_key:
    - name: "admin"
      key: "1234qwer!!"
```

### 6.2 APISIX 컨테이너 실행 예시

```bash
docker run -d \
  -p 9080:9080 \
  -v /path/to/config.yaml:/usr/local/apisix/conf/config.yaml \
  -e ETCDCTL_API=3 \
  apache/apisix:latest
```

---

## 7. 클러스터 확인 및 테스트

1. **Etcd 클러스터 상태 확인 (etcdctl v3):**

   ```bash
   export ETCDCTL_API=3
   etcdctl --user admin:1234qwer!! member list -w=table
   ```

   > 정상적인 클러스터라면 5개 노드 모두가 목록에 나타나야 합니다.

2. **키-값 데이터 기록 및 읽기 테스트:**

   - 데이터 기록:
     ```bash
     etcdctl --user admin:1234qwer!! --endpoints=http://10.101.99.101:4379 put /test/message "Hello, etcd cluster!"
     ```
   - 데이터 읽기 (다른 엔드포인트에서 확인):
     ```bash
     etcdctl --user admin:1234qwer!! --endpoints=http://10.101.99.100:2379 get /test/message
     ```

3. **로그 점검:**  
   각 Etcd 및 APISIX 컨테이너의 로그를 확인하여 인증, 네트워크 통신 관련 오류가 없는지 점검합니다.

---

## 8. 결론

이 가이드를 통해 다음과 같이 구성할 수 있습니다:

- **서버 A (10.101.99.100):**  
  - Etcd 컨테이너 2개 (etcd1, etcd2)
- **서버 B (10.101.99.101):**  
  - Etcd 컨테이너 3개 (etcd3, etcd4, etcd5)
- **부트스트랩 방식 선택:**  
  - **정적 부트스트랩:**  
    모든 노드가 동일한 `ETCD_INITIAL_CLUSTER`, `ETCD_INITIAL_CLUSTER_STATE`, `ETCD_INITIAL_CLUSTER_TOKEN` 등의 환경변수를 공유하며,  
    동시에 기동되어야 정상적인 클러스터 피어 연결이 형성됩니다.
  - **추가 옵션 (etcd Discovery, DNS Discovery):**  
    환경에 따라 클러스터 멤버의 IP가 사전에 결정되지 않은 경우, 디스커버리 서비스를 이용하여 부트스트랩할 수 있습니다.
- **인증 설정:**  
  - 모든 컨테이너에 유효한 ETCD_ROOT_PASSWORD(예: `"1234qwer!!"`)를 설정하며,  
  인증 없이 사용하려면 `ALLOW_NONE_AUTHENTICATION=yes`를 추가할 수 있습니다.
- **네트워크 및 피어 통신 확인:**  
  - 서버 간 피어 통신에 사용되는 포트(2380, 3380, 4380 등)가 개방되어 있어야 하며,  
  동일 초기 클러스터 정보가 각 컨테이너에 올바르게 전달되어야 합니다.
- **APISIX 연동:**  
  - APISIX는 config.yaml에 Etcd HTTP 엔드포인트 및 인증 정보를 포함하여 연동하며,  
  ETCDCTL_API=3 환경변수를 사용해 etcdctl v3 명령어로 클러스터 상태를 확인할 수 있습니다.

**해결 요약:**  
- **문제:**  
  - ETCD_ROOT_PASSWORD 환경변수가 빈 값이거나 설정되지 않아 오류 발생.
- **해결:**  
  1. 모든 etcd 컨테이너 실행 시 유효한 ETCD_ROOT_PASSWORD 값을 포함하도록 설정  
     (예: `-e ETCD_ROOT_PASSWORD="1234qwer!!"`).  
  2. 인증 없이 사용하고자 한다면 `ALLOW_NONE_AUTHENTICATION=yes`를 추가.  
  3. 모든 노드를 동시에 기동하고, 피어 통신에 필요한 포트가 개방되어 있는지 확인.

이와 같이 구성하면, 두 서버에 걸쳐 5개 노드로 안정적인 Bitnami Etcd 클러스터를 도커 컨테이너로 구동하고,  
APISIX를 통해 Etcd와 연동하여 설정 정보를 관리할 수 있습니다.

---

> 실제 환경에 맞게 IP, 포트, 디렉토리 및 필요한 사용자 정보를 조정한 후 적용해 주세요.