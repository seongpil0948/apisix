아래 예시는 **APISIX**에서 **Prometheus(메트릭)**와 **Loki(로그)**를 **전역(글로벌) 플러그인**으로 활성화하고, 관측 관련 엔드포인트(/apisix/prometheus/metrics 등)를 **public-api** 플러그인을 통해 “데이터 플레인 포트(예: 9080)”로 노출하는 방법을 단계별로 설명합니다.

---

# 구성 개요

1. **Prometheus 플러그인(전역)**  
   - APISIX가 내부적으로 `/apisix/prometheus/metrics` 경로에 메트릭을 노출  
   - 별도(9091) 서버를 쓰지 않고, 메인 포트(9080)에서 엔드포인트를 접근할 수 있도록 설정  
   - Prometheus 서버가 `http://<APISIX_IP>:9080/apisix/prometheus/metrics`를 스크래핑

2. **Loki 로깅(전역)**  
   - `loki-logger` 플러그인을 전역으로 활성화해, 모든 요청/응답 로그를 Loki에 전송  
   - Loki에서 APISIX 로그 조회 & Grafana에서 시각화

3. **public-api 플러그인**  
   - 기본적으로 `/apisix/prometheus/metrics` 같은 내부 경로를 “데이터 플레인 포트(9080)”에서 외부 접근 가능하도록 열어줌  
   - 즉, Prometheus나 관리자가 9080 포트로 메트릭 엔드포인트에 접근 가능

---

# 1. config.yaml 설정

다음은 `conf/config.yaml`의 **중요 발췌** 예시입니다. (버전에 따라 다를 수 있으니 참고)

```yaml
plugin_attr:
  # 1) Prometheus 플러그인 전역 설정
  prometheus:
    # 별도 서버(9091)로 띄우는 대신, 메인 포트(9080)에서 노출
    enable_export_server: false

    # (선택) 메트릭 노출 URI 커스터마이징
    # export_uri: /apisix/metrics

    # 기본 히스토그램 버킷
    default_buckets:
      - 0.005
      - 0.01
      - 0.025
      - 0.05
      - 0.1
      - 0.25
      - 0.5
      - 1

  # 2) loki-logger 기본 설정(메타데이터, 또는 여기서 지정 가능)
  #    endpoint_addrs 등은 전역 플러그인에서 설정할 것이므로 여기서는 생략 가능
  #    (필요 시 plugin_metadata 활용 가능)
  # loki-logger:
  #   ...

# 전역 플러그인 사용 시, plugins 섹션은 비워도 무방. (Route 단위가 아니라 Global Rule로 적용)
plugins:
  - prometheus
  - loki-logger
  - public-api  # 관측용 엔드포인트를 노출할 때 필요
```

- `prometheus.enable_export_server: false`로 설정하면, APISIX가 9091 포트를 개별적으로 열지 않고 **주 포트(9080)**에서 `/apisix/prometheus/metrics`를 노출합니다.  
- 이후 **public-api** 플러그인을 통해 `/apisix/prometheus/metrics` 경로를 외부에서 접근 가능하게 만들 예정입니다.

---

# 2. 관측용 라우트 설정 (public-api 플러그인)

APISIX 3.x부터는 **public-api** 플러그인을 이용해 “APISIX 내부 루트(/apisix/...)”를 외부(9080)로 공개할 수 있습니다.

```bash
# 1) 관리자 key (admin_key) 가져오기
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')

# 2) /apisix/prometheus/metrics 노출용 라우트 생성
curl -X PUT "http://127.0.0.1:9180/apisix/admin/routes/900" \
  -H "X-API-KEY: $admin_key" \
  -d '{
    "uri": "/apisix/prometheus/metrics",
    "plugins": {
      "public-api": {}
    }
  }'
```

- 위와 같이 라우트를 생성하면, `http://<APISIX_IP>:9080/apisix/prometheus/metrics` 경로로 접근 가능해집니다.  
- 이후 Prometheus 서버가 해당 URL을 스크래핑하도록 설정하면 됩니다.

---

# 3. Prometheus 전역 플러그인 활성화

APISIX에서는 **글로벌 룰(Global Rule)**을 통해 특정 플러그인을 전역적으로 적용할 수 있습니다. 그러나 **Prometheus 플러그인은 “전역 등록 자체가 필요 없다”**는 점에 유의하세요.  
- Prometheus 플러그인은 `enable_export_server`(or public-api) 방식으로 지표를 노출하며, **별도의 “글로벌 룰 등록” 없이도 작동**합니다.  
- 즉, `plugins` 섹션에 `"prometheus"`가 포함되어 있으면 이미 활성화된 상태입니다.

**정리**: `conf/config.yaml`에 `prometheus`가 포함되어 있고, `/apisix/prometheus/metrics` 라우트를 public-api로 열어주면 **전역(글로벌)**으로 모든 라우트의 요청/응답에 대한 메트릭이 노출됩니다.

---

# 4. Loki 전역 로거 설정

이제 **loki-logger**를 전역으로 활성화하여, 모든 라우트의 요청/응답 로그를 Loki로 전송합니다.

## 4.1 전역룰(Global Rule) 구성

```bash
curl -X PUT "http://127.0.0.1:9180/apisix/admin/global_rules/1" \
  -H "X-API-KEY: $admin_key" \
  -d '{
    "plugins": {
      "loki-logger": {
        "endpoint_addrs": ["http://<LOKI_HOST>:3100"],
        "log_labels": {
          "job": "apisix",
          "route_id": "$route_id"
        },
        "timeout": 3000,
        "keepalive": true,
        "keepalive_timeout": 60000,
        "keepalive_pool": 5
      }
    }
  }'
```

- **endpoint_addrs**: Loki 서버(또는 Gateway)의 주소. (예: `http://loki:3100`)  
- **log_labels**: Loki 라벨로 등록할 정보. `$route_id`, `$remote_addr`, `$host`, `$uri` 등 APISIX 변수를 자유롭게 활용 가능  
- 위 설정은 **“모든 트래픽”**에 대해 로그를 수집·전송합니다.

## 4.2 로그 포맷 커스터마이징(선택)

만약 로그 항목을 커스터마이징하고 싶다면, **plugin_metadata** API로 전역 포맷을 정의할 수 있습니다:

```bash
curl -X PUT "http://127.0.0.1:9180/apisix/admin/plugin_metadata/loki-logger" \
  -H "X-API-KEY: $admin_key" \
  -d '{
    "log_format": {
      "time": "$time_iso8601",
      "client_ip": "$remote_addr",
      "method": "$request_method",
      "request_uri": "$request_uri",
      "upstream": "$upstream_addr"
    }
  }'
```

- 이렇게 설정하면, `loki-logger`에서 전송되는 JSON 로그 구조가 위 필드들로 구성됩니다.  
- **주의**: plugin_metadata는 전역 스코프로 동작하므로, 모든 Loki 로깅에 공통 적용됩니다.

---

# 5. Prometheus & Loki 수집 예시

## 5.1 Prometheus 설정

Prometheus 서버(`prometheus.yml`)에서 다음과 같이 APISIX를 스크래핑하도록 추가합니다.

```yaml
scrape_configs:
  - job_name: "apisix"
    scrape_interval: 15s
    metrics_path: "/apisix/prometheus/metrics"
    static_configs:
      - targets:
        - "<APISIX_IP>:9080"  # public-api 로 노출된 metrics
```

Prometheus를 재시작/재로드 후, `Status → Targets`에서 “UP” 상태를 확인할 수 있습니다.

## 5.2 Loki 설정

- Loki는 별도의 설정 파일에서 ingestion/buffer 세팅 등을 구성합니다.  
- Grafana에서 “Data Sources” → Loki 추가 → `http://<LOKI_HOST>:3100` 입력  
- `Log browser`를 통해 `{job="apisix"}` 등 라벨로 필터링하면, APISIX의 로깅 메시지들이 수집된 것을 확인할 수 있습니다.

---

# 6. 최종 요약

1. **Prometheus 전역 플러그인**  
   - `plugins` 목록에 `prometheus` 추가 + `enable_export_server: false`  
   - `/apisix/prometheus/metrics`를 **public-api** 라우트로 열어주어 외부에서 접근 가능  
   - Prometheus에서 `http://APISIX:9080/apisix/prometheus/metrics` 스크래핑

2. **Loki 전역 로거**  
   - `loki-logger`를 전역 룰(global_rules/1)에 설정해 **모든 트래픽** 로그를 Loki에 전송  
   - 필요 시 `plugin_metadata/loki-logger`로 로그 포맷 조정

3. **public-api**  
   - 관측용 엔드포인트(메트릭, 기타 APISIX 내부 API)를 데이터 플레인 포트에서 외부 접근하도록 열어주는 플러그인  
   - 위 예시에서 `/apisix/prometheus/metrics`에 적용

이렇게 구성하면, APISIX는 **모든 라우트**에 대한 통계를 Prometheus로 내보내고, 요청/응답 로그를 Loki로 전송하며, 메트릭 엔드포인트 등은 public-api 라우트를 통해 공개되어 **한 포트(9080)로 통합 접근**할 수 있게 됩니다. Grafana를 통해 Prometheus와 Loki를 연동해 **APISIX의 주요 지표와 로그**를 손쉽게 시각화하고 분석할 수 있습니다.