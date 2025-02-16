아래 내용은 이전에 구성한 **서버 A(181.10.0.1), 서버 B(181.10.0.2)** 환경에서 **총 5개의 etcd 컨테이너**(A 서버 2개, B 서버 3개)를 어떻게 모니터링할 수 있는지에 대한 가이드입니다. 대부분의 모니터링은 etcd가 제공하는 HTTP 엔드포인트( `/metrics`, `/health`, `/debug/pprof` 등)를 활용하여, **Prometheus + Grafana** 구성을 통해 대시보드 형태로 시각화하는 방법을 가장 많이 사용합니다.

---

## 1. etcd 모니터링 개념 정리

1. **/metrics**  
   - etcd가 기본 Client 포트(예: 2379)에 `/metrics` 라는 엔드포인트를 제공  
   - Prometheus 형식의 메트릭 데이터를 노출  
   - CPU 사용, Raft 지연, gRPC 요청 수, 디스크 동기화 지연 등 핵심 지표 확인 가능

2. **/health, /livez, /readyz**  
   - etcd v3.3 이상에서는 `/health` 엔드포인트를, v3.5.12 이상에서는 `/livez`, `/readyz` 엔드포인트도 제공  
   - etcd 프로세스가 살아있는지(liveness)와 요청을 정상 처리할 수 있는지(readiness)를 체크 가능  
   - 로드밸런서나 모니터링 시스템에서 Health check 목적으로 활용

3. **/debug/pprof**  
   - Go 언어의 pprof(프로파일링) 정보 제공  
   - CPU, 메모리, 잠금(mutex) 사용량 등을 추적, 성능 문제 발생 시 유용  
   - 실 운영에서는 빈번히 사용하기보다는, 문제 발생 시 Debug 레벨로 전환 후 pprof 분석

4. **Prometheus**  
   - etcd의 `/metrics` 엔드포인트를 주기적으로 스크래핑(scrape)하여 시계열(time-series) DB로 저장  
   - Alertmanager와 연동해 특정 메트릭 임계값을 초과하면 알림(이메일, 슬랙 등)을 받을 수 있음

5. **Grafana**  
   - Prometheus를 데이터 소스로 설정하여, 메트릭들을 대시보드 형태로 시각화  
   - 공식 등에서 제공하는 **기본 etcd 대시보드 템플릿**을 가져와 사용하면 편리

---

## 2. 현재 환경(서버/컨테이너)에서의 모니터링 설정

### 2.1 etcd 컨테이너 포트 확인

이전 예시에 따르면, etcd가 다음과 같은 포트 매핑으로 동작한다고 가정합시다.

- **서버 A (IP: 181.10.0.1)**
  - etcd1: `-p 2379:2379 / 2380:2380`
  - etcd2: `-p 3379:2379 / 3380:2380`
- **서버 B (IP: 181.10.0.2)**
  - etcd3: `-p 2379:2379 / 2380:2380`
  - etcd4: `-p 3379:2379 / 3380:2380`
  - etcd5: `-p 4379:2379 / 4380:2380`

즉, 모니터링하려면 Prometheus에서 다음 주소로 `/metrics` 엔드포인트를 수집해야 합니다.

| etcd 노드 | 호스트IP       | 호스트 Client 포트 | etcd 내부 Client 포트 | 모니터링 엔드포인트 예시                     |
|-----------|----------------|--------------------|-----------------------|----------------------------------------------|
| etcd1     | 181.10.0.1    | 2379               | 2379                  | http://181.10.0.1:2379/metrics              |
| etcd2     | 181.10.0.1    | 3379               | 2379                  | http://181.10.0.1:3379/metrics              |
| etcd3     | 181.10.0.2    | 2379               | 2379                  | http://181.10.0.2:2379/metrics              |
| etcd4     | 181.10.0.2    | 3379               | 2379                  | http://181.10.0.2:3379/metrics              |
| etcd5     | 181.10.0.2    | 4379               | 2379                  | http://181.10.0.2:4379/metrics              |

  
> **주의**: 실제로는 방화벽(방화벽 정책, Security Group 등) 설정이 필요할 수 있습니다. Prometheus가 위 포트들에 접근할 수 있도록 열어둡니다.

---

### 2.2 Prometheus 설치 및 설정 예시

1. **Prometheus 설치**  
   - 호스트(혹은 별도 서버)에 Prometheus 바이너리를 다운로드받아 실행하거나, Docker 컨테이너로 배포할 수 있습니다.  
   - 공식 배포본: [https://prometheus.io/download/](https://prometheus.io/download/)  
   - Docker 이미지: `docker run prom/prometheus:v2.0.0 ...`

2. **Prometheus 설정파일(prometheus.yml) 작성**  
   - etcd 엔드포인트를 `scrape_configs`에 지정
   - 예시 ( `/etc/prometheus/prometheus.yml` 로 가정 ):

     ```yaml
     global:
       scrape_interval: 10s   # etcd 메트릭을 10초마다 수집

     scrape_configs:
       - job_name: etcd_cluster
         static_configs:
           - targets:
               - '181.10.0.1:2379'
               - '181.10.0.1:3379'
               - '181.10.0.2:2379'
               - '181.10.0.2:3379'
               - '181.10.0.2:4379'
     ```
     
   - `targets` 항목에 etcd 노드들의 `<IP>:<ClientPort>`을 모두 기재합니다.

3. **Prometheus 실행**  
   - 바이너리 실행 예:  
     ```bash
     ./prometheus \
       --config.file=/etc/prometheus/prometheus.yml \
       --web.listen-address=":9090" \
       --storage.tsdb.path="/var/lib/prometheus/data"
     ```
   - Docker 실행 예:  
     ```bash
     docker run -d --name prometheus \
       -p 9090:9090 \
       -v /path/to/prometheus.yml:/etc/prometheus/prometheus.yml \
       prom/prometheus
     ```

4. **접속 확인**  
   - 브라우저에서 `http://<Prometheus서버 IP>:9090` 열면 Prometheus UI가 보임  
   - “Status > Targets” 메뉴에서 etcd 클러스터의 각 노드가 “UP” 상태인지 확인

---

### 2.3 Grafana 설치 및 기본 대시보드 적용

1. **Grafana 설치**  
   - [공식 사이트](https://grafana.com/get)나 Docker 이미지를 통해 설치 가능합니다.  
   - Docker 예시:
     ```bash
     docker run -d --name grafana \
       -p 3000:3000 \
       grafana/grafana:latest
     ```

2. **Grafana 데이터 소스 설정**  
   - Grafana 웹 UI(기본 포트 3000) 접속 → 로그인(admin/admin) → “Configuration > Data Sources” → “Add data source” → Prometheus 선택  
   - URL: `http://<Prometheus IP>:9090`  
   - “Save & test” 클릭 → “Data source is working” 메시지 확인

3. **기본 etcd 대시보드 가져오기**  
   - Grafana에서 “+” → “Import” 메뉴를 통해 **Etcd 전용 Dashboard**를 불러올 수 있습니다.  
   - 예: [Grafana.com Dashboard #2371 (etcd Metrics)](https://grafana.com/grafana/dashboards/2371) 같은 템플릿 이용  
   - “Import via grafana.com”에 2371 입력 → Data source를 위에서 만든 Prometheus로 설정 → Import
   - 이후 “Dashboard”에 접속하면 etcd 관련 지표(클라이언트 요청, Raft 지연, 디스크 I/O 등)를 시각적으로 확인 가능

---

## 3. Health Check와 Alerting

1. **/health, /livez, /readyz**  
   - etcd v3.5.12 이상에서는 `/livez`와 `/readyz` 엔드포인트로 세분화된 Health check를 제공합니다.  
   - 예:  
     ```bash
     curl http://181.10.0.1:2379/health
     curl http://181.10.0.1:2379/livez
     curl http://181.10.0.1:2379/readyz
     ```
   - 실패 시 JSON 형태로 응답하거나 503 코드 등을 반환하므로, 로드밸런서(또는 쿠버네티스 등) 헬스프로브로 사용 가능

2. **Prometheus Alertmanager 연동**  
   - `prometheus.yml`에 `rule_files` 항목을 추가하여 알람 룰(예: etcd leader 변경 빈번, 디스크 동기화 지연 등)을 설정  
   - Alertmanager에 이메일, 슬랙, 웹훅 등으로 알림을 보낼 수 있음  
   - [공식 etcd 알람 룰 예시](https://github.com/etcd-io/etcd/blob/main/Documentation/op-guide/monitoring.md#alerting) 참조

---

## 4. /debug/pprof 활용(고급 디버깅)

- **문제 발생 시** CPU, 메모리 사용량, goroutine 등을 정밀하게 분석하기 위해 `/debug/pprof`를 이용합니다.  
- 예:  
  ```bash
  go tool pprof http://181.10.0.1:2379/debug/pprof/profile
  ```
  - 30초 프로파일링 후, 상호작용 모드로 전환되며, 가장 CPU를 많이 소모하는 함수 등을 파악 가능  
- **주의**: `--log-level=debug` 로 실행하면 성능 오버헤드가 있으므로, 상시 활성화보다는 디버깅 시점에만 사용

---

## 5. (선택) Distributed tracing (OpenTelemetry)

- etcd 3.5부터 실험적으로 도입된 기능으로, `--experimental-enable-distributed-tracing=true` 옵션을 통해 OpenTelemetry 기반 분산 트레이싱을 활성화할 수 있습니다.  
- 아직 안정적으로 권장되는 기능은 아니며(Experimental), 높은 성능 오버헤드(2~4%)가 있을 수 있으므로 주로 디버깅 용도로만 사용합니다.

---

## 6. 정리

1. **메트릭 수집**: 각 etcd 노드(컨테이너)에서 `/metrics` 엔드포인트로 Prometheus가 스크래핑  
2. **헬스 체크**: `/health`, `/livez`, `/readyz` 엔드포인트 확인. 운영 환경에서 LB나 모니터링 툴이 정기적으로 호출 가능  
3. **시각화**: Grafana에서 Prometheus를 데이터 소스로 추가 후, etcd 대시보드 템플릿을 가져오기  
4. **알람 설정**: Alertmanager를 통해 임계 지표(Leader 불안정, 디스크 지연 등)에 대한 경고 발송  
5. **고급 디버깅**: `/debug/pprof`와 `--log-level=debug`로 CPU/메모리 프로파일링 가능

이 과정을 통해 **분산 환경에서 동작 중인 etcd 노드(컨테이너)들을 Prometheus + Grafana로 효율적으로 모니터링**하고, 필요 시 Health check와 Alerting까지 종합 관리를 할 수 있습니다.