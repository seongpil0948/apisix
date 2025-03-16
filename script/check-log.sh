#!/bin/bash

# 색상 정의
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}OpenTelemetry Collector 로그 검증 스크립트${NC}"
echo "=============================================="

# 컨테이너 실행 상태 확인
echo -e "\n${YELLOW}1. Collector 컨테이너 상태 확인:${NC}"
if docker ps | grep -q monitoring-agent; then
  echo -e "${GREEN}✓ monitoring-agent 컨테이너가 실행 중입니다.${NC}"
else
  echo -e "${RED}✗ monitoring-agent 컨테이너가 실행되지 않았습니다.${NC}"
fi

# 로그 파일 생성 확인
echo -e "\n${YELLOW}2. 로그 파일 생성 확인:${NC}"
if [ -f "$HOME/signal-data/access.json" ]; then
  echo -e "${GREEN}✓ access.json 파일이 생성되었습니다.${NC}"
  JSON_SIZE=$(ls -lh "$HOME/signal-data/access.json" | awk '{print $5}')
  echo "   크기: $JSON_SIZE"
else
  echo -e "${RED}✗ access.json 파일이 존재하지 않습니다.${NC}"
fi

if [ -f "$HOME/signal-data/error.json" ]; then
  echo -e "${GREEN}✓ error.json 파일이 생성되었습니다.${NC}"
  JSON_SIZE=$(ls -lh "$HOME/signal-data/error.json" | awk '{print $5}')
  echo "   크기: $JSON_SIZE"
else
  echo -e "${RED}✗ error.json 파일이 존재하지 않습니다.${NC}"
fi

# 로그 샘플 분석
echo -e "\n${YELLOW}3. 로그 샘플 분석:${NC}"

if [ -f "$HOME/signal-data/access.json" ]; then
  # access.json에서 최근 로그 3개를 추출하여 severitytext와 severitynumber 분석
  echo -e "\n${YELLOW}Access 로그 샘플:${NC}"
  tail -n 10 "$HOME/signal-data/access.json" | grep -i "severitytext\|severitynumber" | head -n 6
  
  # 누락된 severity 값 확인
  MISSING_SEVERITY=$(grep -c 'severitytext": null' "$HOME/signal-data/access.json")
  if [ "$MISSING_SEVERITY" -eq 0 ]; then
    echo -e "${GREEN}✓ 누락된 severitytext 없음${NC}"
  else
    echo -e "${RED}✗ $MISSING_SEVERITY 개의 로그에 severitytext가 누락됨${NC}"
  fi
fi

if [ -f "$HOME/signal-data/error.json" ]; then
  # error.json에서 최근 로그 3개를 추출하여 severitytext와 severitynumber 분석
  echo -e "\n${YELLOW}Error 로그 샘플:${NC}"
  tail -n 10 "$HOME/signal-data/error.json" | grep -i "severitytext\|severitynumber" | head -n 6
  
  # 누락된 severity 값 확인
  MISSING_SEVERITY=$(grep -c 'severitytext": null' "$HOME/signal-data/error.json")
  if [ "$MISSING_SEVERITY" -eq 0 ]; then
    echo -e "${GREEN}✓ 누락된 severitytext 없음${NC}"
  else
    echo -e "${RED}✗ $MISSING_SEVERITY 개의 로그에 severitytext가 누락됨${NC}"
  fi
fi

# Collector 로그 확인
echo -e "\n${YELLOW}4. Collector 로그 확인:${NC}"
docker logs monitoring-agent --tail 20 | grep -i "error\|warn" | head -n 5

echo -e "\n${YELLOW}검증이 완료되었습니다. 문제가 발견되면 설정을 검토하세요.${NC}"