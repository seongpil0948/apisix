## Ignite
it runs on port 9081 and 9082 and 9083 for testing purpose.
command pwd should be run on the test directory.

https://docs.api7.ai/apisix/how-to-guide/service-discovery/eureka-integration

```bash
docker run -d \
  --name web1 \
  -v $(pwd)/web1.conf:/etc/nginx/nginx.conf \
  -p 9081:80 \
  nginx:1.19.0-alpine

docker run -d \
  --name web2 \
  -v $(pwd)/web2.conf:/etc/nginx/nginx.conf \
  -p 9082:80 \
  nginx:1.19.0-alpine

docker run -d \
  --name web3 \
  -v $(pwd)/web3.conf:/etc/nginx/nginx.conf \
  -p 9083:80 \
  nginx:1.19.0-alpine

```

### Register services to Eureka
```bash
HOST_IP=$(hostname -I | awk '{print $1}')
EUREKA_HOST=http://10.101.99.102:8761

curl "$EUREKA_HOST/eureka/apps/web" -X POST \
  -H "Content-Type: application/json" \
  -d '{
"instance":{
  "instanceId": "'"$HOST_IP"':9081",
  "hostName": "'"$HOST_IP"'",
  "ipAddr": "'"$HOST_IP"'",
  "port":{
    "$":9081,
    "@enabled":true
    },
  "status": "UP",
  "app": "web",
  "dataCenterInfo": {
    "name": "MyOwn",
    "@class":"com.netflix.appinfo.InstanceInfo$DefaultDataCenterInfo"
    }
  }
}'


curl "$EUREKA_HOST/eureka/apps/web" -X POST \
  -H "Content-Type: application/json" \
  -d '{
"instance":{
  "instanceId": "'"$HOST_IP"':9082",
  "hostName": "'"$HOST_IP"'",
  "ipAddr": "'"$HOST_IP"'",
  "port":{
    "$":9082,
    "@enabled":true
    },
  "status": "UP",
  "app": "web",
  "dataCenterInfo": {
    "name": "MyOwn",
    "@class":"com.netflix.appinfo.InstanceInfo$DefaultDataCenterInfo"
    }
  }
}'

curl "$EUREKA_HOST/eureka/apps/web" -X POST \
  -H "Content-Type: application/json" \
  -d '{
"instance":{
  "instanceId": "'"$HOST_IP"':9083",
  "hostName": "'"$HOST_IP"'",
  "ipAddr": "'"$HOST_IP"'",
  "port":{
    "$":9083,
    "@enabled":true
    },
  "status": "UP",
  "app": "web",
  "dataCenterInfo": {
    "name": "MyOwn",
    "@class":"com.netflix.appinfo.InstanceInfo$DefaultDataCenterInfo"
    }
  }
}'

```

### Register routes to APISIX
```bash
curl "http://127.0.0.1:9180/apisix/admin/routes" -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "id": "eureka-web-route",
  "uri": "/eureka/web/*",
  "upstream": {
    "service_name": "WEB",
    "discovery_type": "eureka",
    "type": "roundrobin"
  }
}'

```



## Reference
- https://docs.api7.ai/apisix/how-to-guide/service-discovery/eureka-integration
