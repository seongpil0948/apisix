# Eureka 연동 및 인증 설정 가이드 (APISIX & Eureka)

이 가이드는 Eureka를 통해 APISIX와 인증 서버(`CONNECT-AUTH-API`)를 연동하고, 
tester 사용자의 호출 가능 엔드포인트에 대한 인증 설정을 완료하는 방법을 설명합니다. 
tester 사용자가 호출 가능한 특정 엔드포인트는 허용하며, 그 외의 엔드포인트에 대해서는 403 Forbidden을 반환하도록 설정합니다.

## 1. Eureka 연동 설정

### 1.1 Eureka 서버 정보
- **Eureka 서버 주소**: `http://10.101.99.102:8761`
- **Prefix**: `/eureka/`
- **서비스명**: `CONNECT-AUTH-API`
  - 호스트: `10.101.99.102`
  - 포트: `8080`

### 1.2 APISIX Eureka 디스커버리 설정
APISIX의 `config.yaml` 파일에 Eureka 디스커버리 설정을 추가합니다:

```yaml
discovery:
  eureka:
    host:
      - "http://10.101.99.102:8761"
    prefix: "/eureka/"
    fetch_interval: 30
    weight: 100
    timeout:
      connect: 2000
      send: 2000
      read: 5000
```

설정 적용 후 APISIX를 재시작합니다:

```bash
apisix reload
```

### 1.3 Eureka 서비스 확인
Eureka에 등록된 서비스를 확인합니다:

```bash
curl "http://127.0.0.1:9090/v1/discovery/eureka/dump" | jq
```

응답에 `CONNECT-AUTH-API`가 포함되어 있는지 확인하세요.

## 2. 인증 서버 설정

### 2.1 인증 서버 엔드포인트
- **호출 엔드포인트**: `/connect/authorization/validate` (GET)
- **필수 헤더**:
  - `X-FORWARDED-URI`: 사용자가 호출한 URI (예: `/connect/test/clients`)
  - `X-FORWARDED-METHOD`: 사용자가 호출한 HTTP Method (예: `GET`)
  - `Authorization`: JWT 토큰 (Bearer 토큰 형식)

### 2.2 tester 사용자 정보
- **ID**: `tester`
- **Password**: `1234`
- **JWT Access Token**:
  ```
  Bearer eyJhbGciOiJIUzUxMiJ9.eyJzdWIiOiI1IiwibmFtZSI6Iu2FjOyKpO2KuCDsgqzsmqnsnpAiLCJpZCI6InRlc3RlciIsInR5cGUiOiJVU0VSIiwiZ3JvdXBzIjpbXSwicm9sZXMiOlsiUk9MRV9URVNUX1VTRVIiXSwiaWF0IjoxNzQyMTg4ODgwLCJleHAiOjE3NDIyNzUyODB9.ryJsfwvo-D23pWHOzh3zaymq9QEZcwKvejLC1ocHh6FeXPfjdCQuR22yhEc7lO3XJG8qWHxH2Q5Kj4sS76-U9g
  ```

### 2.3 tester 사용자의 호출 가능 엔드포인트
- **허용된 엔드포인트**:
  - `/connect/test/clients`
  - `/connect/test/client/123456`
  - `/connect/test2/clients`
  - `/connect/test2/client/123456`
  - `/connect/authorization/test1/clients`
  - `/connect/authorization/test1/client/123456`
  - `/connect/authorization/test2/clients`
  - `/connect/authorization/test2/client/123456`
- **호출 불가능한 엔드포인트 예시**:
  - `/connect/supplier/clients` (403 Forbidden 반환)

**참고**: 인증 서버는 `/connect` 경로 이후만 파싱하여 권한을 체크하므로, 앞단의 도메인(예: `XXX:8080`)은 임의의 값이어도 동작합니다.

## 3. APISIX 라우트 설정

### 3.1 인증 서버 라우트 설정 (인증 제외)
인증 서버 자체 호출은 인증을 요구하지 않도록 설정합니다:

```bash
curl -i "http://127.0.0.1:9180/apisix/admin/routes/connect-auth" -X PUT \
  -H "X-API-KEY: $admin_key" \
  -d '{
    "uri": "/connect/authorization/*",
    "name": "connect-auth-server-route",
    "desc": "Route for authorization server - no auth required",
    "methods": ["GET", "POST", "PUT", "DELETE", "PATCH"],
    "plugins": {
      "proxy-rewrite": {
        "uri": "/authorization/validate"
      }
    },    
    "upstream": {
      "service_name": "CONNECT-AUTH-API",
      "type": "roundrobin",
      "discovery_type": "eureka"
    },
    "priority": 200,
    "status": 1
  }'
```

### 3.2 보호된 엔드포인트 라우트 설정 (인증 필요)
`/connect/*` 경로에 대해 `forward-auth` 플러그인을 적용하여 인증을 요구합니다:

```bash
curl -i "http://127.0.0.1:9180/apisix/admin/routes/connect-protected" -X PUT \
  -H "X-API-KEY: $admin_key" \
  -d '{
    "uri": "/connect/*",
    "name": "connect-protected-route",
    "desc": "Protected route requiring authentication",
    "methods": ["GET", "POST", "PUT", "DELETE", "PATCH"],
    "plugins": {
      "forward-auth": {
        "uri": "/connect/authorization/validate",
        "request_headers": ["Authorization"],
        "upstream_headers": ["X-User-ID", "X-User-Name", "X-User-Roles"],
        "client_headers": ["Location"],
        "timeout": 5000,
        "keepalive": true,
        "keepalive_timeout": 60000,
        "keepalive_pool": 5,
        "status_on_error": 403
      },
      "proxy-rewrite": {
        "headers": {
          "X-FORWARDED-URI": "$uri",
          "X-FORWARDED-METHOD": "$request_method"
        }
      }
    },
    "upstream": {
      "type": "roundrobin",
      "discovery_type": "eureka",
      "service_name": "$1"
    },
    "vars": [
      ["uri", "~~", "^/connect/([^/]+)/.*$"]
    ],
    "priority": 100,
    "status": 1
  }'
```

### 3.3 forward-auth 서비스 설정
`forward-auth` 플러그인이 사용할 인증 서비스를 정의합니다:

```bash
curl -i "http://127.0.0.1:9180/apisix/admin/services/auth-service" -X PUT \
  -H "X-API-KEY: $admin_key" \
  -d '{
    "name": "auth-service",
    "desc": "Authentication service via Eureka",
    "upstream": {
      "service_name": "CONNECT-AUTH-API",
      "type": "roundrobin",
      "discovery_type": "eureka"
    }
  }'
```

## 4. 테스트 방법

### 4.1 테스트 토큰 설정
터미널에서 테스트에 사용할 토큰을 환경 변수로 설정합니다:

```bash
export TEST_TOKEN="Bearer eyJhbGciOiJIUzUxMiJ9.eyJzdWIiOiI1IiwibmFtZSI6Iu2FjOyKpO2KuCDsgqzsmqnsnpAiLCJpZCI6InRlc3RlciIsInR5cGUiOiJVU0VSIiwiZ3JvdXBzIjpbXSwicm9sZXMiOlsiUk9MRV9URVNUX1VTRVIiXSwiaWF0IjoxNzQyMTg4ODgwLCJleHAiOjE3NDIyNzUyODB9.ryJsfwvo-D23pWHOzh3zaymq9QEZcwKvejLC1ocHh6FeXPfjdCQuR22yhEc7lO3XJG8qWHxH2Q5Kj4sS76-U9g"
```

### 4.2 인증 서버 직접 접근 테스트
인증 서버에 직접 요청을 보내어 정상 동작을 확인합니다:

```bash
curl -i "http://10.101.99.102:8080/authorization/validate" \
  -H "X-FORWARDED-URI: /connect/test2/clients" \
  -H "X-FORWARDED-METHOD: GET" \
  -H "Authorization: $TEST_TOKEN"
```
- **기대 응답**: HTTP 200 OK
```bash
curl -i "http://127.0.0.1:9080/connect/authorization/validate" \
  -H "X-FORWARDED-URI: /connect/test2/clients" \
  -H "X-FORWARDED-METHOD: GET" \
  -H "Authorization: $TEST_TOKEN"
```


### 4.3 APISIX를 통한 허용된 엔드포인트 테스트
APISIX를 통해 허용된 엔드포인트에 접근합니다:

```bash
curl -i "http://127.0.0.1:9080/connect/test2/clients" \
  -H "Authorization: $TEST_TOKEN"
```

- **기대 응답**: HTTP 200 OK (또는 해당 서비스의 응답)

### 4.4 APISIX를 통한 허용되지 않은 엔드포인트 테스트
허용되지 않은 엔드포인트에 접근하여 403 응답을 확인합니다:

```bash
curl -i "http://127.0.0.1:9080/connect/supplier/clients" \
  -H "Authorization: $TEST_TOKEN"
```

- **기대 응답**: HTTP 403 Forbidden

### 4.5 추가 테스트: 새로운 허용 엔드포인트
`/connect/authorization/test1/clients`와 같은 새로운 허용 엔드포인트도 확인합니다:

```bash
curl -i "http://127.0.0.1:9080/connect/authorization/test1/clients" \
  -H "Authorization: $TEST_TOKEN"
```

- **기대 응답**: HTTP 200 OK

## 5. 문제 해결 방법

### 5.1 Eureka 디스커버리 상태 확인
Eureka 연동 상태를 점검합니다:

```bash
curl "http://127.0.0.1:9090/v1/discovery/eureka/dump" | jq
```

### 5.2 Eureka 서비스 상세 확인
`CONNECT-AUTH-API`의 등록 정보를 확인합니다:

```bash
curl -i "http://10.101.99.102:8761/eureka/apps/CONNECT-AUTH-API"
```

### 5.3 APISIX 로그 확인
오류가 발생할 경우 APISIX 로그를 확인합니다:

```bash
tail -f /usr/local/apisix/logs/error.log
```

---

위 가이드를 따라 Eureka와 APISIX를 성공적으로 연동하고, tester 사용자의 호출 가능 엔드포인트에 대한 인증 설정을 완료할 수 있습니다. 설정 후 테스트를 통해 정상 작동 여부를 확인하세요!