# 개요

시나리오 별 API Gateway 운영 가이드

## Route 관리

### 신규 Route 추가

```bash
curl -i "http://127.0.0.1:9180/apisix/admin/routes" -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "id": "getting-started-ip",
  "uri": "/ip",
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}'
```

### 신규 Route 추가 (https)

```bash
curl -i "http://10.101.99.100:9180/apisix/admin/routes" -H "X-API-KEY: $admin_key"  -X PUT -d '
{
  "id": "getting-started-headers",
  "uri": "/headers",
  "upstream" : {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:443": 1,
      "mock.api7.ai:443": 1
    },
    "pass_host": "node",
    "scheme": "https"
  }
}'


# "regex_uri": ["^/flower(.*)", "$1"]
# "hosts": [
#   "flower.dwoong.com"
# ],
```

```bash
curl -i "http://10.101.99.101:9180/apisix/admin/routes/553448796621636287" \
     -H "X-API-KEY: $admin_key" \
     -X PUT \
     -d '{
  "uri": "/flower/*",
  "name": "connect-flower",
  "desc": "monitoring airflow worker",
  "labels": {
    "app": "flower",
    "API_VERSION": "v1",
    "ns": "airflow",
    "project": "connect"
  },
  "status": 1,
  "plugins": {
    "proxy-rewrite": {
      "regex_uri": [
        "^/flower/(.*)",
        "/$1"
      ]
    }
  },
  "upstream": {
    "type": "chash",
    "hash_on": "vars",
    "key": "remote_addr",
    "scheme": "http",
    "pass_host": "pass",
    "nodes": {
      "10.101.99.96:5555": 1,
      "10.101.99.95:5555": 1
    },
    "timeout": {
      "send": 6,
      "connect": 6,
      "read": 6
    },
    "keepalive_pool": {
      "idle_timeout": 60,
      "requests": 1000,
      "size": 320
    }
  }
}'

```

#### 조회
```bash

curl -i "http://10.101.99.101:9180/apisix/admin/routes/553448796621636287" -H "X-API-KEY: $admin_key"  -X GET

```

#### 추가한 Route 확인

```bash
for i in {1..10}; do curl "http://10.101.99.101:9180/headers" ; done


hc=$(seq 100 | xargs -I {} curl "http://10.101.99.101:9180/headers" -sL | grep "httpbin" | wc -l); echo httpbin.org: $hc, mock.api7.ai: $((100 - $hc))
```

```bash
curl -i -H "Host: flower.dwoong.com" http://localhost:9080/flower
curl -i -H "Host: flower.dwoong.com" http://localhost:9080/flower/
```

---

### Route 추가 (Upstream, TCP) with Redis

#### stream proxy 설정
```bash
  stream_proxy:
    tcp:
      - 6380 # listen on 9100 ports of all network interfaces for TCP requests
      - "127.0.0.1:6380"
```

#### Upstream 추가

```
curl -X PUT http://10.101.99.101:9180/apisix/admin/upstreams/1 \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: $admin_key" \
  -d '{
    "name": "redis",
    "nodes": {
      "10.101.99.97:7000": 1,
      "10.101.99.98:7001": 1,
      "10.101.99.99:7002": 1,
      "10.101.99.97:7003": 1,
      "10.101.99.98:7004": 1,
      "10.101.99.99:7005": 1
    },
    "type": "chash",         
    "key": "remote_addr",   
    "retries": 3,
    "timeout": {
      "connect": 5,
      "read": 5,
      "send": 5
    },
    "checks": {
      "active": {
        "type": "tcp",
        "healthy": {
          "interval": 2,
          "successes": 2
        },
        "unhealthy": {
          "interval": 2,
          "tcp_failures": 3,
          "timeouts": 3
        }
      }
    }
  }'


```

#### TCP Route 추가
```
curl -X PUT http://10.101.99.100:9180/apisix/admin/stream_routes/1 \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: $admin_key" \
  -d '{
    "upstream_id": "1",
    "server_port": 6380
  }'

```

#### TCP Route 삭제

```bash
curl -X DELETE http://10.101.99.100:9180/apisix/admin/stream_routes/1 \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: $admin_key" 

#### 추가한 Route 확인

```bash
HOST=10.101.99.100
for i in {1..10}; do \
  nc -zv $HOST 6380 <<< "PING"; \
done
HOST=0.0.0.0
for i in {1..3}; do \
  redis-cli  -h $HOST -p 6380 PING; \
  redis-cli  -h $HOST -p 6380 SET key$i value$i; \
done


redis-cli  -h 10.101.99.98 -p 7001 PING
redis-cli  -h 10.101.99.100 -p 6380 PING
```



## Plugin 관리
#### 전역 Plugin 목록 조회

```bash
curl "http://10.101.99.100:9180/apisix/admin/plugins" -H "X-API-KEY: $admin_key" | jq
curl "http://10.101.99.100:9180/apisix/admin/global_rules" -H "X-API-KEY: $admin_key" | jq
```

#### 전역 Plugin 추가
https://apisix.apache.org/docs/apisix/terminology/global-rule/
```bash
curl -X PUT \
  http://10.101.99.100:9180/apisix/admin/global_rules/1 \
  -H 'Content-Type: application/json' \
  -H "X-API-KEY: $admin_key" \
  -d '{
        "plugins": {
            "limit-count": {
                "time_window": 60,
                "policy": "local",
                "count": 20,
                "key": "remote_addr",
                "rejected_code": 503
            }
        }
    }'
```
```bash
curl -X PUT \
  http://10.101.99.100:9180/apisix/admin/global_rules/2 \
  -H 'Content-Type: application/json' \
  -H "X-API-KEY: $admin_key" \
  -d '{
        "plugins": {
            "prometheus": {}
        }
    }'
```

#### 삭제
```bash

curl http://127.0.0.1:9180/apisix/admin/global_rules/global-monitoring-logger \
  -H "X-API-KEY: $admin_key" -X DELETE
```


#### 목록 조회

```bash
curl http://127.0.0.1:9180/apisix/admin/global_rules   -H "X-API-KEY: $admin_key" -X GET | jq
```

#### 검증
```bash
curl -i http://10.101.99.100:9091/apisix/prometheus/metrics
curl -i http://10.101.99.101:9091/apisix/prometheus/metrics

curl -i http://10.101.99.100:9080/apisix/status
curl -i http://10.101.99.101:9080/apisix/status
```


### Eureka 연동
The diagnostic interface is exposed on port 9090 of the loopback interface by default, and the access method is GET /v1/discovery/{discovery_type}/dump, for example:
```bash

curl http://localhost:9090/v1/discovery/eureka/dump

```

### OTEL Collector 경로 추가


```bash
curl http://127.0.0.1:9180/apisix/admin/routes/otel_http \
-H "X-API-KEY: $admin_key" \
-X PUT -d '
{
  "id": "otel_http",
  "name": "otel_http",
  "uri": "/otel/http*",
  "plugins": {
    "proxy-rewrite": {
      "regex_uri": ["^/otel/http(.*)", "$1"]
    },
    "limit-count": {
        "time_window": 10,
        "policy": "local",
        "count": 20,
        "key": "remote_addr",
        "rejected_code": 503
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "10.101.91.145:4318": 1
    }
  }
}'
```

#### TEST
올바른 헤더와 IP로 요청 테스트:

```bash
# HTTP 요청 테스트 (125.209.206.X IP에서 실행해야 함)
curl -i "https://dwoong.com/v1/traces" \
  -H "Host: trader.dwoong.com" \
  --data '{...OTLP JSON 데이터...}'
```

잘못된 호스트 또는 IP로 테스트:

```bash
# 잘못된 호스트로 요청 (거부되어야 함)
curl -i "https://trader.dwoong.com/v1/traces" \
  -H "Host: wrong.example.com" \
  -H "Authorization: Bearer $TOKEN" \
  --data '{...OTLP JSON 데이터...}'
```