# APISIX IP 제한 구성 솔루션

APISIX에서 `/bo` 하위 모든 경로에 대해 지정된 IP만 접근할 수 있도록 설정하는 방법을 안내해드리겠습니다. IP 제한은 `ip-restriction` 플러그인을 사용하며, 여러 라우트에 일관된 설정을 적용하기 위해 Plugin Config를 활용하겠습니다.


## Plugin Config 생성

IP 제한을 위한 Plugin Config를 생성합니다:

```bash
curl http://127.0.0.1:9180/apisix/admin/plugin_configs/ip_whitelist_bo \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "desc": "IP 화이트리스트 - /bo 경로용",
    "plugins": {
        "ip-restriction": {
            "whitelist": [
                "10.101.0.0/16",
                "59.10.17.253/32",
                "127.0.0.1/32",
                "180.64.179.43/32",
                "175.197.211.231/32",
                "203.234.253.0/24",
                "125.209.206.0/24",
                "125.209.204.0/24",
                "172.224.252.0/24"
            ],
            "message": "이 리소스에 접근할 수 있는 IP가 아닙니다",
            "rejected_code": 403
        }
    }
}'
```
## 확인

생성된 Plugin Config를 확인합니다:

| jq '.node.nodes[] | select(.key == "ip_whitelist_bo")'
```bash
curl http://127.0.0.1:9180/apisix/admin/plugin_configs \
  -H "X-API-KEY: $admin_key" \
  | jq '.list[] | select(.value.id == "ip_whitelist_bo")'
  
```

## 3. 라우트 생성 (기존 라우트가 없는 경우)

`/bo` 경로와 그 하위 경로에 대한 라우트를 생성하고 위에서 만든 Plugin Config를 연결합니다:

```bash
curl http://127.0.0.1:9180/apisix/admin/routes/bo_routes \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/bo/*",
    "plugin_config_id": "ip_whitelist_bo",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "your-backend-server:port": 1
        }
    }
}'
```

## 4. 기존 라우트에 Plugin Config 적용하기

이미 `/bo` 관련 라우트가 있는 경우, 각 라우트에 Plugin Config ID를 추가해야 합니다. 다음 스크립트를 사용하여 모든 `/bo` 경로 라우트를 찾아 업데이트할 수 있습니다:

```bash
#!/bin/bash

# 관리자 API 키 설정
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')

# 모든 라우트 조회
routes=$(curl -s http://127.0.0.1:9180/apisix/admin/routes -H "X-API-KEY: $admin_key" | jq -r '.node.nodes[] | @base64')

for route_base64 in $routes; do
    route=$(echo $route_base64 | base64 --decode)
    route_id=$(echo $route | jq -r '.key' | awk -F'/' '{print $NF}')
    uri=$(echo $route | jq -r '.value.uri // ""')
    uris=$(echo $route | jq -r '.value.uris // []')
    
    # URI 또는 URIs에 '/bo'가 포함된 라우트 확인
    if [[ $uri == *"/bo"* ]] || [[ $(echo $uris | grep -c "/bo") -gt 0 ]]; then
        echo "라우트 ID $route_id에 Plugin Config 추가 중..."
        
        # 라우트 정보 가져오기
        route_config=$(curl -s http://127.0.0.1:9180/apisix/admin/routes/$route_id -H "X-API-KEY: $admin_key")
        
        # plugin_config_id 추가
        updated_config=$(echo $route_config | jq '.node.value += {"plugin_config_id": "ip_whitelist_bo"}')
        
        # 라우트 업데이트
        curl -s http://127.0.0.1:9180/apisix/admin/routes/$route_id \
            -H "X-API-KEY: $admin_key" -X PUT \
            -d "$(echo $updated_config | jq -r '.node.value')"
        
        echo "라우트 ID $route_id가 업데이트되었습니다."
    fi
done
```

## 5. 테스트

설정이 올바르게 적용되었는지 확인하기 위해 다음 명령어로 테스트할 수 있습니다:

```bash
# 허용된 IP에서 (성공 예상)
curl -i http://127.0.0.1:9080/bo/test

# 허용되지 않은 IP에서 (403 에러 예상)
curl -i http://외부IP:9080/bo/test
```



이 구성으로 `/bo` 하위의 모든 경로는 지정된 IP 주소/서브넷에서만 접근이 가능하며, 
이외의 모든 접근은 403 오류로 차단됩니다. 보안을 위해 차단된 접근은 로그에 기록되며, 응답 헤더에 보안 관련 헤더가 추가됩니다.