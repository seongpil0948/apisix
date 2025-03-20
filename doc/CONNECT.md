# Eureka 연동 및 인증 설정 가이드 (APISIX & Eureka)

이 가이드는 Eureka를 통해 APISIX와 인증 서버(`AUTH-API`) 및 테스트 서버(`TEST-CLIENT-A`, `TEST-CLIENT-B`)를 연동하고, 사용자별 권한에 따른 접근 제어 설정을 완료하는 방법을 설명합니다.

## 1. Eureka 연동 설정

### 1.1 Eureka 서버 정보
- **Eureka 서버 주소**: `http://10.101.99.102:8761`
- **Prefix**: `/eureka/`
- **서비스 정보**:
  - 인증 서버 서비스명: `AUTH-API`
    - 호스트: `10.101.99.102`
    - 포트: `8080`
  - 테스트 서버 A 서비스명: `TEST-CLIENT-A`
  - 테스트 서버 B 서비스명: `TEST-CLIENT-B`

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

응답에 `AUTH-API`, `TEST-CLIENT-A`, `TEST-CLIENT-B`가 포함되어 있는지 확인하세요.

## 2. 인증 서버 정보

### 2.1 인증 서버 엔드포인트
- **서비스명**: `AUTH-API`
- **제공 URI**:
  - `/auth/validate` (GET)
  - `/auth/sign-up` (POST)
  - `/auth/sign-in` (POST)
  - `/auth/sign-out` (POST)
  - `/auth/refresh` (POST)

### 2.2 인증 검증 요청 정보
- **검증 엔드포인트**: `/auth/validate` (GET)
- **필수 헤더**:
  - `X-FORWARDED-URI`: 사용자가 호출한 URI (예: `/connect/test-a/clients`)
  - `X-FORWARDED-METHOD`: 사용자가 호출한 HTTP Method (예: `GET`)
  - `Authorization`: JWT 토큰 (Bearer 토큰 형식)

### 2.3 사용자 정보 및 권한
- **사용자 1**:
  - **ID**: `tester`
  - **Password**: `1234`
  - **권한**: 테스트서버 A, B 모두 호출 가능
  
- **사용자 2**:
  - **ID**: `aClient`
  - **Password**: `1234`
  - **권한**: 테스트서버 A만 호출 가능
  
- **사용자 3**:
  - **ID**: `bClient`
  - **Password**: `1234`
  - **권한**: 테스트서버 B만 호출 가능

## 3. APISIX 라우트 설정

### 3.1 인증 서버 라우트 설정 (인증 제외)
인증 서버 자체 호출은 인증을 요구하지 않도록 설정합니다:

```bash
# curl -i "http://127.0.0.1:9180/apisix/admin/routes/connect-auth" -X DELETE -H "X-API-KEY: $admin_key" 
# curl -i "http://127.0.0.1:9180/apisix/admin/routes/connect-auth-validate" -X DELETE -H "X-API-KEY: $admin_key" 

curl -i "http://127.0.0.1:9180/apisix/admin/routes/connect-auth" -X PUT \
  -H "X-API-KEY: $admin_key" \
  -d '{
    "uri": "/connect/auth/*",
    "name": "connect-auth-server-route",
    "desc": "Route for auth server - no auth required",
    "methods": ["GET", "POST", "PUT", "DELETE", "PATCH"], 
    "plugins": {},    
    "upstream": {
      "service_name": "AUTH-API",
      "type": "roundrobin",
      "discovery_type": "eureka"
    },
    "priority": 200,
    "status": 1
  }'

curl -i "http://127.0.0.1:9180/apisix/admin/routes/connect-auth-validate" -X PUT \
  -H "X-API-KEY: $admin_key" \
  -d '{
    "uri": "/connect/auth/validate",
    "name": "connect-auth-server-route-validate",
    "desc": "Route for auth server - no auth required",
    "methods": ["GET", "POST", "PUT", "DELETE", "PATCH"], 
    "plugins": {
      "proxy-rewrite": {
        "headers": {
          "X-FORWARDED-URI": "$uri",
          "X-FORWARDED-METHOD": "$request_method"
        }
      }
    },    
    "upstream": {
      "service_name": "AUTH-API",
      "type": "roundrobin",
      "discovery_type": "eureka"
    },
    "priority": 201,
    "status": 1
  }'  
```

### 3.2 테스트 서버 A, B 라우트 설정 (인증 필요)
`/connect/test-a/*` 경로에 대해 `forward-auth` 플러그인을 적용하여 인증을 요구합니다:

```bash
curl -i "http://127.0.0.1:9180/apisix/admin/routes/test-client-a" -X PUT \
  -H "X-API-KEY: $admin_key" \
  -d '{
    "uri": "/connect/test-a/*",
    "name": "test-client-a",
    "desc": "Protected route requiring authentication for TEST-CLIENT-A",
    "methods": ["GET", "POST", "PUT", "DELETE", "PATCH"],
    "plugins": {
      "forward-auth": {
        "uri": "https://dwoong.com/connect/auth/validate",
        "request_headers": ["Authorization", "X-FORWARDED-URI", "X-FORWARDED-METHOD"],
        "upstream_headers": ["X-User-ID", "X-User-Name", "X-User-Roles"],
        "client_headers": ["Location"],
        "timeout": 5000,
        "keepalive": true,
        "keepalive_timeout": 60000,
        "keepalive_pool": 5,
        "status_on_error": 403
      }
    },
    "upstream": {
      "type": "roundrobin",
      "discovery_type": "eureka",
      "service_name": "TEST-CLIENT-A"
    },
    "priority": 100,
    "status": 1
  }'

curl -i "http://127.0.0.1:9180/apisix/admin/routes/test-client-b" -X PUT \
  -H "X-API-KEY: $admin_key" \
  -d '{
    "uri": "/connect/test-b/*",
    "name": "test-client-b",
    "desc": "Protected route requiring authentication for TEST-CLIENT-B",
    "methods": ["GET", "POST", "PUT", "DELETE", "PATCH"],
    "plugins": {
      "forward-auth": {
        "uri": "https://dwoong.com/connect/auth/validate",
        "request_headers": ["Authorization", "X-FORWARDED-URI", "X-FORWARDED-METHOD"],
        "upstream_headers": ["X-User-ID", "X-User-Name", "X-User-Roles"],
        "client_headers": ["Location"],
        "timeout": 5000,
        "keepalive": true,
        "keepalive_timeout": 60000,
        "keepalive_pool": 5,
        "status_on_error": 403
      }
    },
    "upstream": {
      "type": "roundrobin",
      "discovery_type": "eureka",
      "service_name": "TEST-CLIENT-B"
    },
    "priority": 100,
    "status": 1
  }'
```


## 4. 테스트 시나리오

### 4.1 로그인 및 토큰 획득
각 사용자별로 로그인하여 토큰을 획득합니다:

#### 테스트 사용자 로그인

```bash
echo "Logging in as tester..."
TESTER_RESPONSE=$(curl --silent --location 'https://dwoong.com/connect/auth/sign-in' \
  --header 'Content-Type: application/json' \
  --data '{
    "id": "tester",
    "password": "1234"
  }')

# Login for aClient user
echo "Logging in as aClient..."
ACLIENT_RESPONSE=$(curl --silent --location 'https://dwoong.com/connect/auth/sign-in' \
  --header 'Content-Type: application/json' \
  --data '{
    "id": "aClient",
    "password": "1234"
  }')

# Login for bClient user
echo "Logging in as bClient..."
BCLIENT_RESPONSE=$(curl --silent --location 'https://dwoong.com/connect/auth/sign-in' \
  --header 'Content-Type: application/json' \
  --data '{
    "id": "bClient",
    "password": "1234"
  }')

# Extract tokens using jq
TESTER_TOKEN=$(echo "$TESTER_RESPONSE" | jq -r '.data.token.access_token')
ACLIENT_TOKEN=$(echo "$ACLIENT_RESPONSE" | jq -r '.data.token.access_token')
BCLIENT_TOKEN=$(echo "$BCLIENT_RESPONSE" | jq -r '.data.token.access_token')

# Export tokens as environment variables with Bearer prefix
export TESTER_TOKEN="Bearer $TESTER_TOKEN"
export ACLIENT_TOKEN="Bearer $ACLIENT_TOKEN"
export BCLIENT_TOKEN="Bearer $BCLIENT_TOKEN"

# Show the extracted tokens
echo "Tokens set as environment variables:"
echo "TESTER_TOKEN: $TESTER_TOKEN"
echo "ACLIENT_TOKEN: $ACLIENT_TOKEN"
echo "BCLIENT_TOKEN: $BCLIENT_TOKEN"

echo "You can now use these tokens for testing API access"

```

### tester 사용자 테스트

#### tester 사용자 TEST-CLIENT-A 접근 테스트
```bash
# 테스트 A - client/123456 엔드포인트
curl -i "http://10.101.99.102:8081/connect/test-a/client/123456" \
  -H "Authorization: $TESTER_TOKEN"
curl -i "https://dwoong.com/connect/test-a/client/123456" \
  -H "Authorization: $TESTER_TOKEN"

curl -i "https://dwoong.com/connect/test-a/clients" \
  -H "Authorization: $TESTER_TOKEN"

# 테스트 B - client/123456 엔드포인트
curl -i "https://dwoong.com/connect/test-b/client/123456" \
  -H "Authorization: $TESTER_TOKEN"

# 테스트 B - clients 엔드포인트
curl -i "https://dwoong.com/connect/test-b/clients" \
  -H "Authorization: $TESTER_TOKEN"  
```
- **기대 결과**: 모두 HTTP 200 OK

### 4.4 aClient 사용자 테스트

#### aClient 사용자 TEST-CLIENT-A 접근 테스트
```bash
# 테스트 A - client/123456 엔드포인트
curl -i "https://dwoong.com/connect/test-a/client/123456" \
  -H "Authorization: $ACLIENT_TOKEN"

# 테스트 A - clients 엔드포인트
curl -i "https://dwoong.com/connect/test-a/clients" \
  -H "Authorization: $ACLIENT_TOKEN"
```
- **기대 결과**: 모두 HTTP 200 OK

#### aClient 사용자 TEST-CLIENT-B 접근 테스트
```bash
# 테스트 B - client/123456 엔드포인트
curl -i "https://dwoong.com/connect/test-b/client/123456" \
  -H "Authorization: $ACLIENT_TOKEN"

# 테스트 B - clients 엔드포인트
curl -i "https://dwoong.com/connect/test-b/clients" \
  -H "Authorization: $ACLIENT_TOKEN"
```
- **기대 결과**: 모두 HTTP 403 Forbidden

### 4.5 bClient 사용자 테스트

#### bClient 사용자 TEST-CLIENT-A 접근 테스트
```bash
# 테스트 A - client/123456 엔드포인트
curl -i "https://dwoong.com/connect/test-a/client/123456" \
  -H "Authorization: $BCLIENT_TOKEN"

# 테스트 A - clients 엔드포인트
curl -i "https://dwoong.com/connect/test-a/clients" \
  -H "Authorization: $BCLIENT_TOKEN"
```
- **기대 결과**: 모두 HTTP 403 Forbidden

#### bClient 사용자 TEST-CLIENT-B 접근 테스트
```bash
# 테스트 B - client/123456 엔드포인트
curl -i "https://dwoong.com/connect/test-b/client/123456" \
  -H "Authorization: $BCLIENT_TOKEN"

# 테스트 B - clients 엔드포인트
curl -i "https://dwoong.com/connect/test-b/clients" \
  -H "Authorization: $BCLIENT_TOKEN"
```
- **기대 결과**: 모두 HTTP 200 OK

## 5. 문제 해결 방법

### 5.1 Eureka 디스커버리 상태 확인
Eureka 연동 상태를 점검합니다:

```bash
curl "http://127.0.0.1:9090/v1/discovery/eureka/dump" | jq
```

### 5.2 Eureka 서비스 상세 확인
서비스 등록 정보를 확인합니다:

```bash
# 인증 서버 확인
curl -i "http://10.101.99.102:8761/eureka/apps/AUTH-API"

# 테스트 서버 A 확인
curl -i "http://10.101.99.102:8761/eureka/apps/TEST-CLIENT-A"

# 테스트 서버 B 확인
curl -i "http://10.101.99.102:8761/eureka/apps/TEST-CLIENT-B"
```

### 5.3 인증 서버 직접 요청 테스트
인증 서버에 직접 요청을 보내 정상 동작을 확인합니다:

```bash
# tester 사용자 테스트 A 권한 확인
curl -i "http://10.101.99.102:8080/auth/validate" \
  -H "X-FORWARDED-URI: /connect/test-a/clients" \
  -H "X-FORWARDED-METHOD: GET" \
  -H "Authorization: $TESTER_TOKEN"

# aClient 사용자 테스트 B 권한 확인
curl -i "http://10.101.99.102:8080/auth/validate" \
  -H "X-FORWARDED-URI: /connect/test-b/clients" \
  -H "X-FORWARDED-METHOD: GET" \
  -H "Authorization: $ACLIENT_TOKEN"
```

### 5.4 APISIX 로그 확인
오류가 발생할 경우 APISIX 로그를 확인합니다:

```bash
tail -f /usr/local/apisix/logs/error.log
```

---

위 가이드를 따라 Eureka와 APISIX를 성공적으로 연동하고, 사용자별 권한에 따른 접근 제어 설정을 완료할 수 있습니다. 각 테스트 시나리오를 통해 설정이 정상적으로 작동하는지 확인하세요.