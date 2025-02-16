#!/bin/bash
# 환경변수 확인: ADMIN_API와 ADMIN_KEY는 반드시 설정되어 있어야 합니다.
if [ -z "${ADMIN_API}" ]; then
  echo "ADMIN_API 환경변수가 설정되지 않았습니다."
  exit 1
fi

if [ -z "${ADMIN_KEY}" ]; then
  echo "ADMIN_KEY 환경변수가 설정되지 않았습니다."
  exit 1
fi

# Upstream 및 Route 관련 변수 설정
UPSTREAM_ID="airflow_upstream"
ROUTE_ID="553448796621636288"
SERVICE_URI="/airflow/*"
SERVICE_NAME="connect-airflow"
SERVICE_DESC="Airflow UI with primary/fallback upstream and response rewrite fallback"
LABELS='{"app": "airflow", "API_VERSION": "v1", "ns": "airflow", "project": "connect"}'

PRIMARY_HOST="10.101.99.95"
PRIMARY_PORT=8080
FALLBACK_HOST="10.101.99.96"
FALLBACK_PORT=8080

HEALTH_CHECK_PATH="/airflow/health"

# DOLLAR 변수: 리터럴 '$' 문자를 출력하기 위함
DOLLAR='$'

# 1. Active Health Check 설정
CHECKS=$(cat <<EOF
{
  "active": {
    "type": "http",
    "http_path": "${HEALTH_CHECK_PATH}",
    "concurrency": 10,
    "healthy": {
      "interval": 2,
      "successes": 2
    },
    "unhealthy": {
      "interval": 1,
      "http_failures": 3,
      "tcp_failures": 3,
      "timeouts": 3
    }
  }
}
EOF
)

# 2. Fallback 응답 메시지 (내부 따옴표 이스케이프 처리)
FALLBACK_MESSAGE="{\\\"message\\\": \\\"서비스가 현재 이용 불가합니다\\\"}"

# 3. Upstream JSON 구성 (roundrobin, priority 적용)
UPSTREAM_JSON=$(cat <<EOF
{
  "type": "roundrobin",
  "nodes": [
    {
      "host": "${PRIMARY_HOST}",
      "port": ${PRIMARY_PORT},
      "weight": 1,
      "priority": 0
    },
    {
      "host": "${FALLBACK_HOST}",
      "port": ${FALLBACK_PORT},
      "weight": 1,
      "priority": -1
    }
  ],
  "checks": ${CHECKS},
  "timeout": {
    "connect": 6,
    "send": 6,
    "read": 6
  },
  "keepalive_pool": {
    "idle_timeout": 60,
    "requests": 1000,
    "size": 320
  }
}
EOF
)

echo "Upstream JSON 구성:"
echo "$UPSTREAM_JSON"

# Upstream 생성/업데이트 (PUT 요청)
curl -i "${ADMIN_API}/apisix/admin/upstreams/${UPSTREAM_ID}" \
     -H "X-API-KEY: ${ADMIN_KEY}" \
     -X PUT \
     -d "$UPSTREAM_JSON"

# 4. Route JSON 구성 (upstream_id를 참조)
#    regex_uri에서 "/airflow/${DOLLAR}1"로 작성하여 최종 JSON에 "/airflow/$1"이 나오도록 함.
ROUTE_JSON=$(cat <<EOF
{
  "uri": "${SERVICE_URI}",
  "name": "${SERVICE_NAME}",
  "desc": "${SERVICE_DESC}",
  "labels": ${LABELS},
  "status": 1,
  "plugins": {
    "proxy-rewrite": {
      "regex_uri": [
        "^/airflow/(.*)",
        "/airflow/${DOLLAR}1"
      ]
    },
    "response-rewrite": {
      "status_code": 200,
      "body": "${FALLBACK_MESSAGE}",
      "vars": [
        [
          "status",
          "==",
          503
        ]
      ]
    }
  },
  "upstream_id": "${UPSTREAM_ID}"
}
EOF
)

echo "Route JSON 구성:"
echo "$ROUTE_JSON"

# 5. Route 생성/업데이트 (PUT 요청)
curl -i "${ADMIN_API}/apisix/admin/routes/${ROUTE_ID}" \
     -H "X-API-KEY: ${ADMIN_KEY}" \
     -X PUT \
     -d "$ROUTE_JSON"
