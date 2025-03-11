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

curl http://10.101.99.100:9180/apisix/admin/ssls/1 \
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
curl http://10.101.99.100:9180/apisix/admin/ssls -H "X-API-KEY: $admin_key" 
```

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
            "httpbin.org:443": 1
        }
    }
  }'

curl -i "http://127.0.0.1:9180/apisix/admin/routes" -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "id": "quickstart-client-ip",
  "uri": "/ip",
  "upstream": {
    "nodes": {
      "httpbin.org:443":1
    },
    "type": "roundrobin"
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

PEM 파일은 Base64로 인코딩된 DER 형식의 데이터를 포함하며, 텍스트 파일 내에 `-----BEGIN CERTIFICATE-----` 또는 `-----BEGIN PRIVATE KEY-----` 등의 헤더와 푸터가 포함되어 있습니다. OpenSSL을 사용하면 PEM 파일을 디코딩하고 상세 정보를 확인할 수 있습니다.

---

## 인증서(Public Certificate) 디코딩

인증서 파일(fullchain.pem 등)의 내용을 확인하려면 다음 명령어를 사용합니다:

```bash
openssl x509 -in /etc/letsencrypt/live/dwoong.com/fullchain.pem -text -noout
```

이 명령어는 인증서의 유효기간, 발급자, 주체, 공개키, 확장 필드 등 여러 정보를 사람이 읽기 쉬운 형태로 출력합니다.

---

## 개인키(Private Key) 디코딩

RSA 개인키의 경우 다음 명령어를 사용합니다:

```bash
openssl rsa -in /etc/letsencrypt/live/dwoong.com/privkey.pem -text -noout
```

만약 EC (Elliptic Curve) 개인키인 경우에는 아래 명령어를 사용합니다:

```bash
openssl ec -in /etc/letsencrypt/live/dwoong.com/privkey.pem -text -noout
```

이 명령어들은 개인키의 구조, 크기, 공개키 정보 등을 출력합니다.

---

## 인증서 서명 요청(CSR) 파일 디코딩

CSR 파일의 내용을 확인하려면 다음 명령어를 사용합니다:

```bash
openssl req -in request.pem -text -noout
```

이 명령어는 요청서에 포함된 주체 정보, 공개키, 확장 필드 등 상세 정보를 출력합니다.

---

## 참고 사항

- **여러 개의 인증서가 포함된 경우**  
  PEM 파일에 여러 인증서가 포함되어 있다면, 해당 명령어는 첫 번째 인증서만 디코딩합니다. 여러 인증서를 확인하려면 텍스트 편집기로 파일을 열어 각 인증서를 분리하여 별도로 디코딩하면 됩니다.

- **파일 권한**  
  특히 개인키 파일은 민감하므로, 읽기 권한이 제한되어 있는지 확인하고, 작업 후 적절한 보안 조치를 취해야 합니다.

이와 같이 OpenSSL 명령어를 활용하면 PEM 파일의 내용을 쉽게 디코딩하여 해석할 수 있습니다.

