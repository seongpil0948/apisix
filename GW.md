
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

#### Reload
설정 변경시 컨테이너 재시작없이 설정을 적용할 수 있습니다.

```bash
CONTAINER_ID=$(docker ps | grep apache/apisix: | awk '{print $1}')
docker exec -it $CONTAINER_ID apisix reload
```