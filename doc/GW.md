## 구성

#### 특징
- `/shared` 경로를 NFS로 모든 인스턴스는 코드와 파일을 공유 중
- 각 서버는 apisix gateway와 dashboard를 실행하며 ETCD Cluster를 사용하여 설정을 공유

- GW-PROD-1: ETCD(2), APISIX(1), Dashboard(1)
- GW-PROD-2: ETCD(3), APISIX(1), Dashboard(1)

#### 서버 정보
```
Host GW-PROD-1
    HostName 10.101.99.100
    User develop

Host GW-PROD-2
    HostName 10.101.99.101
    User develop

```

## 컨테이너 구동동

### APISIX Gateway 실행 (Docker)

```bash
mkdir -p $HOME/logs/apisix 
sudo chmod -R 777 $HOME/logs/apisix
rm $HOME/logs/apisix/*.sock

docker run -d   \
    --restart unless-stopped \
    --network host \
    --user root \
    -v /shared/etcd/data/etcd1:/bitnami/etcd \
    -v $HOME/logs/apisix:/usr/local/apisix/logs \
    -v /shared/scm/apisix/config/apisix.yaml:/usr/local/apisix/conf/config.yaml \
    -v /shared/scm/apisix/config/debug.yaml:/usr/local/apisix/conf/debug.yaml \
    -v /shared/scm/apissix-plugin-lua:/usr/local/apissix-plugin-lua \
    apache/apisix:latest

# docker run -d   \
#     --restart unless-stopped \
#     -p 80:9080 \
#     -p 9180:9180 \
#     -p 9080:9080 \
#     -p 9081:9081 \
#     -p 9082:9082 \
#     -p 6380:6380 \
#     -p 9200:9200 \
#     -p 443:443 \
#     -p 9091:9091 \
#     -v /shared/etcd/data/etcd1:/bitnami/etcd \
#     -v $HOME/logs/apisix:/usr/local/apisix/logs \
#     -v /shared/scm/apisix/config/apisix.yaml:/usr/local/apisix/conf/config.yaml \
#     -v /shared/scm/apisix/config/debug.yaml:/usr/local/apisix/conf/debug.yaml \
#     -v /shared/scm/apissix-plugin-lua:/usr/local/apissix-plugin-lua \
#     apache/apisix:latest
```

### APISIX Dashboard 실행 (Docker)

```bash
docker run -d \
  --restart unless-stopped \
  -p 9000:9000 \
  -v /shared/scm/apisix/config/dashboard.yaml:/usr/local/apisix-dashboard/conf/conf.yaml \
  -v ($HOME)/logs/apisix-dashboard:/usr/local/apisix-dashboard/logs \
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