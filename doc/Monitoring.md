## 아키텍처 개요
- **API Gateway (Apache APISIX)**  
  각 GW-PROD 서버에 APISIX가 배포되어 있으며, APISIX 내부 플러그인을 통해 아래의 관측 데이터를 수집합니다.
  - **로그:** http-logger 플러그인을 활용해 API 접근 로그를 OTLP 형식으로 전송
  - **메트릭:** Prometheus 플러그인을 통해 API 호출, 응답 상태 등 메트릭 노출 (수집 대상은 OTEL Collector 외 추가 exporter를 통해 다른 시스템에도 전달 가능)
  - **트레이스:** OpenTelemetry 플러그인을 이용해 분산 추적 데이터를 OTLP 프로토콜로 전송

- **OTEL Collector (IP: 10.101.91.145)**  
  최신 Collector 구성은 로그(OTLP), 메트릭(Prometheus 스크래핑) 및 트레이스(OTLP)를 각각의 receiver로 수신하고, 내부 processors 및 connectors를 통해 dev/prod 환경별로 라우팅한 후, 파일(exporter)와 OTLP HTTP(exporter) 등 다양한 exporter로 데이터를 전송합니다.

- **관측 백엔드**  
  - Prometheus: 메트릭 수집 및 시각화 (Grafana 대시보드 활용)  
  - Loki (또는 기타 로그 수집/분석 도구): OTLP HTTP 로그 전송  
  - (옵션) AWS X-Ray: prod 트레이스 데이터 전송  
  - 추가적으로 파일(exporter)을 통해 로컬 백업 및 검증

## 전역 설정

### config.yaml 파일에서 전역 플러그인 등록

APISIX의 설정 파일(conf/config.yaml) 내에서 전역 플러그인 목록에 모니터링 관련 플러그인(예, opentelemetry, prometheus)을 추가할 수 있습니다.  
예시:

```yaml

plugin_attr:
  opentelemetry:
    resource:
      service.name: "apisix"
      env: "prod"
    collector:
      address: "10.101.91.145:4318"   # OTLP HTTP receiver 포트
      request_timeout: 3
  prometheus:
    export_uri: "/apisix/prometheus/metrics"
```
ㅋ

### 로그 전송 (OTLP)

- http-logger 또는 OpenTelemetry 로그 플러그인을 사용하여 APISIX가 생성한 로그를 OTLP 프로토콜로 Collector(10.101.91.145:4317 또는 :4318)로 전송  

```bash

curl http://127.0.0.1:9180/apisix/admin/global_rules \
  -H "X-API-KEY: $admin_key" -X PUT -d '{
    "id": "global-monitoring-logger",
    "plugins": {
      "http-logger": {
        "uri": "http://10.101.91.145:4318/otlp"
      }
    }
}'
```



### 3.2 메트릭 수집 (Prometheus)

- Prometheus 플러그인을 활성화하여 APISIX가 메트릭 데이터를 노출하도록 구성  
- Collector는 Prometheus receiver를 통해 이를 스크랩합니다.
  ```bash
  curl http://<APISIX_HOST>:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PUT -d '{
      "uri": "/get",
      "plugins": {
        "prometheus": {}
      },
      "upstream_id": "1"
  }'
  ```
- APISIX는 기본적으로 9091 포트에서 `/apisix/prometheus/metrics`로 메트릭을 제공하므로, Collector에 이 주소를 scrape_targets로 추가할 수 있습니다.

### 3.3 트레이스 전송 (OTLP)

- OpenTelemetry 트레이싱 플러그인을 사용해 트레이스 데이터를 OTLP 포맷으로 Collector(10.101.91.145:4317)로 전송합니다.
  ```bash
  curl http://<APISIX_HOST>:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PUT -d '{
      "methods": ["GET"],
      "uris": ["/uid/*"],
      "plugins": {
        "opentelemetry": {
          "sampler": {
            "name": "always_on"
          },
          "additional_attributes": ["env=prod", "service.name=apisix"]
        }
      },
      "upstream": {
        "type": "roundrobin",
        "nodes": {"127.0.0.1:1980": 1}
      }
  }'
  ```

---

## Otel collector 

#### update

```yaml
        - job_name: "apisix"
          scrape_interval: 15s # This value will be related to the time range of the rate function in Prometheus QL. The time range in the rate function should be at least twice this value.
          metrics_path: "/apisix/prometheus/metrics"
          static_configs:
            - targets: 
              - http://10.101.99.100:9091
              - http://10.101.99.101:9091

```