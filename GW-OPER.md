# 개요

시나리오 별 API Gateway 운영 가이드

## Route 관리

#### 신규 Route 추가

```bash
curl -i "http://10.101.99.101:9180/apisix/admin/routes" -H "X-API-KEY: $admin_key"  -X PUT -d '
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

```

#### 추가한 Route 확인

```bash
for i in {1..10}; do curl "http://10.101.99.101:9180/headers" ; done

hc=$(seq 100 | xargs -I {} curl "http://10.101.99.101:9080/headers" -sL | grep "httpbin" | wc -l); echo httpbin.org: $hc, mock.api7.ai: $((100 - $hc))
```



## Plugin 관리
#### 전역 Plugin 목록 조회

```bash
curl "http://10.101.99.100:9180/apisix/admin/plugins" -H "X-API-KEY: $admin_key"
curl "http://10.101.99.100:9180/apisix/admin/global_rules" -H "X-API-KEY: $admin_key"
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
            "prometheus": {},
            "public-api": {}
        }
    }'
```

#### 검증
```bash
curl -i http://10.101.99.100:9091/apisix/prometheus/metrics
curl -i http://10.101.99.101:9091/apisix/prometheus/metrics

curl -i http://10.101.99.100:9080/apisix/status
curl -i http://10.101.99.101:9080/apisix/status
```
