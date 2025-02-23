아래는 Let's Encrypt를 사용해 SSL 인증서를 발급받고, APISIX에 적용하여 HTTPS 서비스를 제공하는 예시 절차입니다.

## **인증서 발급**

**자동화 방식 (certbot-dns-route53 플러그인 사용)**

Route53 API와 AWS 자격증명을 사용해 TXT 레코드 추가를 자동으로 처리할 수 있습니다.

### **준비 단계**

1. **플러그인 설치**

Ubuntu/Debian 계열에서는 아래와 같이 설치할 수 있습니다:

```bash
sudo apt-get update
sudo apt-get install python3-certbot-dns-route53
```

2. **AWS 자격증명 설정**

Certbot이 AWS Route53 API에 접근할 수 있도록 IAM 자격증명이 필요합니다.  
방법은 두 가지가 있습니다:

- **IAM 역할 사용 (EC2 인스턴스 등):**  
인스턴스에 적절한 권한이 부여된 IAM 역할을 할당합니다.

- **AWS 자격증명 파일 사용:**  
홈 디렉토리의 `~/.aws/credentials` 파일에 아래와 같이 작성합니다:

```ini
[default]
aws_access_key_id = YOUR_ACCESS_KEY_ID
aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
```

※ IAM 사용자에 Route53 레코드 수정 권한이 포함되어 있어야 합니다.

### **인증서 발급**

#### 1. 터미널에서 아래와 같이 Certbot을 실행합니다:

```bash
sudo certbot certonly --dns-route53 -d dwoong.com
```

**참고** 다중 도메인이나 와일드카드 인증서가 필요하다면:

```bash
sudo certbot certonly --dns-route53 -d dwoong.com -d '*.dwoong.com'
```


#### 2. Certbot이 자동으로 AWS Route53 API를 통해 `_acme-challenge` TXT 레코드를 생성하고, DNS 전파 후에 인증서를 발급합니다.

```
Saving debug log to /var/log/letsencrypt/letsencrypt.log
Requesting a certificate for dwoong.com

Successfully received certificate.
Certificate is saved at: /etc/letsencrypt/live/dwoong.com/fullchain.pem
Key is saved at:         /etc/letsencrypt/live/dwoong.com/privkey.pem
This certificate expires on 2025-05-19.
These files will be updated when the certificate renews.
Certbot has set up a scheduled task to automatically renew this certificate in the background.

- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
If you like Certbot, please consider supporting our work by:
 * Donating to ISRG / Let's Encrypt:   https://letsencrypt.org/donate
 * Donating to EFF:                    https://eff.org/donate-le
- - - - - -
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

curl http://10.101.99.100:9080/apisix/admin/ssls/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
     "cert" : "'"$(sudo cat /etc/letsencrypt/live/dwoong.com/fullchain.pem)"'",
     "key": "'"$(sudo cat /etc/letsencrypt/live/dwoong.com/privkey.pem)"'",
     "snis": ["dwoong.com"]
}'  
```

   > **참고:** 위 명령은 APISIX Admin API에 SSL 객체를 등록하여, dwoong.com으로 들어오는 HTTPS 요청에 대해 발급받은 인증서를 사용하도록 설정합니다.

#### 조회

```bash
curl http://10.101.99.100:9080/apisix/admin/ssls -H "X-API-KEY: $admin_key" 
```

3. **Router 객체 생성 (도메인에 맞게 라우팅)**

예를 들어, dwoong.com 도메인에서 `/get` URI 요청을 특정 백엔드(예: on-premise 앱)로 전달하려면 다음과 같이 구성합니다.

```bash
curl http://127.0.0.1:80/apisix/admin/routes \
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
curl --tlsv1.3  --resolve 'dwoong.com:443:0.0.0.0' https://dwoong.com:443/apisix/status -vvv
curl -i -H "Host: dwoong.com" http://localhost:9080/flower
curl --tlsv1.3 --resolve dwoong.com:443:10.101.99.100 https://dwoong.com:443/apisix/status -vvv

openssl s_client -connect 10.101.99.100:443 -tls1_3

```

- `--resolve` 옵션은 테스트 시 DNS를 우회해 APISIX가 실행 중인 서버 IP(예제에서는 127.0.0.1)로 요청을 보내게 합니다.
- 정상적으로 SSL 핸드쉐이크가 이루어지고, 백엔드 응답이 반환되면 설정이 완료된 것입니다.

---

### 5. 추가 고려사항

- **자동 갱신**: Let's Encrypt 인증서는 90일마다 만료되므로, Certbot의 자동 갱신(cron job 등)을 설정하고, 인증서 갱신 후 APISIX에 새 인증서를 적용할 수 있도록 재로딩하는 작업이 필요합니다.
- **포트 및 방화벽**: APISIX가 HTTPS(일반적으로 443 또는 9443) 포트에서 요청을 수신하도록 설정되어 있는지, 온프레미스 서버 및 네트워크 방화벽에서 해당 포트가 개방되어 있는지 확인합니다.

