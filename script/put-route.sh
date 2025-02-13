curl -i "${ADMIN_API}/apisix/admin/routes/553448796621636288" \
     -H "X-API-KEY: ${ADMIN_KEY}" \
     -X PUT \
     -d '{
  "uri": "/airflow/*",
  "name": "connect-airflow",
  "desc": "monitoring airflow UI",
  "labels": {
    "app": "airflow",
    "API_VERSION": "v1",
    "ns": "airflow",
    "project": "connect"
  },
  "status": 1,
  "plugins": {
    "proxy-rewrite": {
      "regex_uri": [
        "^/airflow/(.*)",
        "/airflow/$1"
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
      "10.101.99.95:8080": 1,
      "10.101.99.96:8080": 1
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