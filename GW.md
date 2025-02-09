
## 컨테이너 구동동

### APISIX Gateway 실행 (Docker)


```bash
docker run -d \
    --restart unless-stopped \
    --net="host" \
    -v /shared/etcd/data/etcd1:/bitnami/etcd \
    -v /shared/scm/apisix/config/apisix.yaml:/usr/local/apisix/conf/config.yaml \
    apache/apisix:latest
```

### APISIX Dashboard 실행 (Docker)

```bash
docker run -d \
  --restart unless-stopped \
  -p 9000:9000 \
  -v /shared/scm/apisix/config/dashboard.yaml:/usr/local/apisix-dashboard/conf/conf.yaml \
  apache/apisix-dashboard:latest
```

#### 검증

*100번 서버*
```bash
$ curl "http://10.101.99.100:9080" --head
HTTP/1.1 404 Not Found
Date: Sat, 08 Feb 2025 13:56:26 GMT
Content-Type: text/plain; charset=utf-8
Connection: keep-alive
Server: APISIX/3.11.0

$ curl "http://10.101.99.101:9080" --head
```


## 운영

#### Reload
설정 변경시 컨테이너 재시작없이 설정을 적용할 수 있습니다.

```bash
CONTAINER_ID=$(docker ps | grep apache/apisix: | awk '{print $1}')
docker exec -it $CONTAINER_ID apisix reload
```

#### 신규 Route 추가

```bash
curl -i "http://10.101.99.100:9180/apisix/admin/routes" -H "X-API-KEY: $admin_key" -X PUT -d '
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
'
```
#### 추가한 Route 확인

```bash
curl "http://10.101.99.101:9180/ip" 
```

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
                "count": 2,
                "key": "remote_addr",
                "rejected_code": 503
            }
        }
    }'
```
