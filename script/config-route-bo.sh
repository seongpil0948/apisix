#!/bin/bash

# 환경 설정
export ADMIN_API="http://127.0.0.1:9180/apisix/admin"
export LOGFILE="plugin_config_update.log"
echo "=== 플러그인 설정 업데이트 $(date) ===" > $LOGFILE

echo "라우트 조회 중..." | tee -a $LOGFILE
routes=$(curl -s "${ADMIN_API}/routes" -H "X-API-KEY: ${admin_key}")

# 총 라우트 수 출력
total_routes=$(echo "$routes" | jq -r '.total')
echo "총 ${total_routes}개의 라우트가 있습니다." | tee -a $LOGFILE

# 3. /bo 경로 패턴을 가진 라우트 업데이트
count=0
updated=0

echo "$routes" | jq -c '.list[]' | while read -r route; do
    count=$((count+1))
    
    # 라우트 ID 추출
    route_id=$(echo "$route" | jq -r '.id // .value.id')
    route_name=$(echo "$route" | jq -r '.value.name // "이름없음"')
    
    # URI 추출 (단일 URI 또는 URIs 배열)
    uri=$(echo "$route" | jq -r '.value.uri // ""')
    uris=$(echo "$route" | jq -r '.value.uris // []')
    
    # URI 정보 출력
    echo "[$count/$total_routes] 라우트 검사 중: $route_id ($route_name)" | tee -a $LOGFILE
    echo "  - URI: $uri" | tee -a $LOGFILE
    echo "  - URIs: $uris" | tee -a $LOGFILE
    
    # URI나 URIs에 '/bo'가 포함되어 있는지 확인
    if [[ "$uri" == *"/bo"* ]] || [[ "$uris" == *"/bo"* ]]; then
        echo "  → /bo 경로 발견, Plugin Config 적용..." | tee -a $LOGFILE
        
        # 현재 라우트 정보 추출
        route_info=$(echo "$route" | jq '.value | del(.create_time, .update_time)' )
        
        # plugin_config_id가 이미 있는지 확인
        has_plugin_config=$(echo "$route_info" | jq 'has("plugin_config_id")')
        
        if [[ "$has_plugin_config" == "true" ]]; then
            echo "  → 이미 plugin_config_id가 설정되어 있습니다. 건너뜁니다." | tee -a $LOGFILE
            continue
        fi
        
        # plugin_config_id 추가 
        updated_route=$(echo "$route_info" | jq '. + {"plugin_config_id": "ip_whitelist_bo"}')
        echo "  → 업데이트된 라우트 정보: $updated_route" | tee -a $LOGFILE

        # 라우트 업데이트
        update_result=$(curl -s "${ADMIN_API}/routes/${route_id}" \
            -H "X-API-KEY: ${admin_key}" -X PUT \
            -d "$updated_route")
        
        # 업데이트 결과 확인
        if echo "$update_result" | jq -e '.value.plugin_config_id' > /dev/null; then
            echo "  → 라우트 업데이트 성공: $route_id" | tee -a $LOGFILE
            updated=$((updated+1))
        else
            echo "  → 라우트 업데이트 실패: $route_id" | tee -a $LOGFILE
            echo "  → 오류 메시지: $update_result" | tee -a $LOGFILE
        fi
    else
        echo "  → /bo 경로 없음, 건너뜁니다." | tee -a $LOGFILE
    fi
done

echo "작업 완료: $updated 개의 라우트가 업데이트되었습니다." | tee -a $LOGFILE