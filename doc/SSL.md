아래는 Let's Encrypt를 사용해 SSL 인증서를 발급받고, APISIX에 적용하여 HTTPS 서비스를 제공하는 예시 절차입니다.

---

### 1. Certbot(ACME 클라이언트) 설치 및 인증서 발급

1. **Certbot 설치**  
Ubuntu 환경에서는 다음과 같이 설치할 수 있습니다.

```bash
sudo apt-get update && sudo apt-get install certbot
```

2. **인증서 발급**  
standalone 모드(혹은 기존 웹 서버와의 연동 방식)를 사용하여 dwoong.com 도메인에 대한 인증서를 발급받습니다.

```bash
sudo certbot certonly --standalone -d dwoong.com
```

발급이 완료되면 인증서와 개인키는 보통 다음 경로에 저장됩니다.  
- 인증서 체인: `/etc/letsencrypt/live/dwoong.com/fullchain.pem`  
- 개인키: `/etc/letsencrypt/live/dwoong.com/privkey.pem`

---

### 2. APISIX에 SSL 인증서 구성

APISIX는 TLS의 Server Name Indication(SNI) 기능을 활용해 여러 인증서를 로드할 수 있습니다. 아래 예시는 dwoong.com 도메인을 위한 SSL 객체를 생성하는 방법입니다.

1. **Admin API 인증키 확인**  
   APISIX 설정 파일(conf/config.yaml)에서 `admin_key` 값을 확인하고 환경변수에 저장합니다.

2. **SSL 객체 생성 (단일 SNI 예시)**

   ```bash
   curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
     -H "X-API-KEY: $admin_key" \
     -X PUT -d '{
       "cert": "'"$(cat /etc/letsencrypt/live/dwoong.com/fullchain.pem)"'",
       "key": "'"$(cat /etc/letsencrypt/live/dwoong.com/privkey.pem)"'",
       "snis": ["dwoong.com"]
     }'
   ```

   > **참고:** 위 명령은 APISIX Admin API에 SSL 객체를 등록하여, dwoong.com으로 들어오는 HTTPS 요청에 대해 발급받은 인증서를 사용하도록 설정합니다.

3. **Router 객체 생성 (도메인에 맞게 라우팅)**

   예를 들어, dwoong.com 도메인에서 `/get` URI 요청을 특정 백엔드(예: on-premise 앱)로 전달하려면 다음과 같이 구성합니다.

   ```bash
   curl http://127.0.0.1:9180/apisix/admin/routes \
     -H "X-API-KEY: $admin_key" \
     -X PUT -i -d '{
        "id": "test-ssl",
       "uri": "/get",
       "hosts": ["dwoong.com"],
       "methods": ["GET"],
       "upstream": {
           "type": "roundrobin",
           "nodes": {
               "httpbin.org:80": 1
           }
       }
     }'
   ```

---

### 3. DNS (Route53) 설정

- Route53에서 **A 레코드**를 등록하여 `dwoong.com` 도메인이 on-premise 서버의 공용 IP를 가리키도록 설정합니다.
- 예) `dwoong.com` → `your_public_ip`

---

### 4. 테스트

APISIX가 HTTPS(예: 포트 9443)로 리스닝 중이라면, 다음과 같이 테스트할 수 있습니다.

```bash
curl --resolve 'dwoong.com:9443:127.0.0.1' https://dwoong.com:9443/get -vvv
```

- `--resolve` 옵션은 테스트 시 DNS를 우회해 APISIX가 실행 중인 서버 IP(예제에서는 127.0.0.1)로 요청을 보내게 합니다.
- 정상적으로 SSL 핸드쉐이크가 이루어지고, 백엔드 응답이 반환되면 설정이 완료된 것입니다.

---

### 5. 추가 고려사항

- **자동 갱신**: Let's Encrypt 인증서는 90일마다 만료되므로, Certbot의 자동 갱신(cron job 등)을 설정하고, 인증서 갱신 후 APISIX에 새 인증서를 적용할 수 있도록 재로딩하는 작업이 필요합니다.
- **포트 및 방화벽**: APISIX가 HTTPS(일반적으로 443 또는 9443) 포트에서 요청을 수신하도록 설정되어 있는지, 온프레미스 서버 및 네트워크 방화벽에서 해당 포트가 개방되어 있는지 확인합니다.

