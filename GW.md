
## 실행 예시

### APISIX Gateway 실행 (Docker)


```bash
docker run -d \
  --restart unless-stopped \
  -p 9080:9080 \
  -p 9180:9180 \
  -v /shared/etcd/data/etcd1:/bitnami/etcd \
  -v config/apisix.yaml:/usr/local/apisix/conf/config.yaml \
  apache/apisix:latest
```

### APISIX Dashboard 실행 (Docker)

```bash
docker run -d \
  --restart unless-stopped \
  -p 9000:9000 \
  -p 9091:9091 \
  -v config/dashboard.yaml:/usr/local/apisix-dashboard/conf/config.yaml \
  apache/apisix-dashboard:latest
```

