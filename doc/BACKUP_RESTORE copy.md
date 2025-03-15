# APISIX etcd 클러스터 백업 및 복구 가이드

## 목차

1. [개요](#1-개요)
2. [로컬 테스트 환경 구성](#2-로컬-테스트-환경-구성)
3. [백업 프로세스](#3-백업-프로세스)
4. [복구 절차](#4-복구-절차)
5. [복구 검증](#5-복구-검증)

## 1. 개요

이 문서는 운영 환경의 APISIX etcd 클러스터(5개 노드)를 로컬 환경에서 백업 및 복원하는 절차를 설명합니다. 운영 환경과 동일한 구성을 로컬에서 재현하고, S3에 저장된 백업으로부터 복구하는 전체 프로세스를 다룹니다.

### 1.1 운영 환경 구성

- **서버 A (GW-PROD-1, 10.101.99.100)**
  - etcd1: 클라이언트 포트 2379, 피어 포트 2380
  - etcd2: 클라이언트 포트 3379, 피어 포트 3380

- **서버 B (GW-PROD-2, 10.101.99.101)**
  - etcd3: 클라이언트 포트 2379, 피어 포트 2380
  - etcd4: 클라이언트 포트 3379, 피어 포트 3380
  - etcd5: 클라이언트 포트 4379, 피어 포트 4380

### 1.2 로컬 테스트 환경 구성

로컬 환경에서는 Docker Compose를 사용하여 운영 환경과 동일한 구성을 재현합니다:
- 5개의 etcd 노드 (etcd1~etcd5)
- APISIX 게이트웨이
- APISIX 대시보드
- 백업 및 복구 기능

## 2. 로컬 테스트 환경 구성

### 2.1 디렉토리 구조 생성

```bash
mkdir -p ~/apisix-test/etcd/{data,snapshot,log}/{etcd1,etcd2,etcd3,etcd4,etcd5}
mkdir -p ~/apisix-test/apisix/{config,log}
mkdir -p ~/apisix-test/restore-temp
mkdir -p ~/apisix-test/etcd/backup-before-restore


```

### 2.2 Docker Compose 파일 생성

다음 내용을 `~/apisix-test/docker-compose.yml` 파일로 저장하세요:

```yaml
networks:
  apisix-network:
    driver: bridge

services:
  etcd1:
    image: bitnami/etcd:3.5.9
    container_name: etcd1
    restart: unless-stopped
    networks:
      - apisix-network
    ports:
      - "2379:2379"
      - "2380:2380"
    volumes:
      - ./etcd/data/etcd1:/bitnami/etcd
      - ./etcd/snapshot/etcd1:/snapshots
    environment:
      - ETCD_NAME=etcd1
      - ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
      - ETCD_ADVERTISE_CLIENT_URLS=http://etcd1:2379
      - ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380
      - ETCD_INITIAL_ADVERTISE_PEER_URLS=http://etcd1:2380
      - ETCD_INITIAL_CLUSTER=etcd1=http://etcd1:2380,etcd2=http://etcd2:2380,etcd3=http://etcd3:2380,etcd4=http://etcd4:2380,etcd5=http://etcd5:2380
      - ETCD_INITIAL_CLUSTER_STATE=new
      - ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster-1
      - ETCD_ROOT_PASSWORD=1234qwer!!
      - ALLOW_NONE_AUTHENTICATION=yes

  etcd2:
    image: bitnami/etcd:3.5.9
    container_name: etcd2
    restart: unless-stopped
    networks:
      - apisix-network
    ports:
      - "3379:2379"
      - "3380:2380"
    volumes:
      - ./etcd/data/etcd2:/bitnami/etcd
      - ./etcd/snapshot/etcd2:/snapshots
    environment:
      - ETCD_NAME=etcd2
      - ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
      - ETCD_ADVERTISE_CLIENT_URLS=http://etcd2:2379
      - ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380
      - ETCD_INITIAL_ADVERTISE_PEER_URLS=http://etcd2:2380
      - ETCD_INITIAL_CLUSTER=etcd1=http://etcd1:2380,etcd2=http://etcd2:2380,etcd3=http://etcd3:2380,etcd4=http://etcd4:2380,etcd5=http://etcd5:2380
      - ETCD_INITIAL_CLUSTER_STATE=new
      - ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster-1
      - ETCD_ROOT_PASSWORD=1234qwer!!
      - ALLOW_NONE_AUTHENTICATION=yes

  etcd3:
    image: bitnami/etcd:3.5.9
    container_name: etcd3
    restart: unless-stopped
    networks:
      - apisix-network
    ports:
      - "4379:2379"
      - "4380:2380"
    volumes:
      - ./etcd/data/etcd3:/bitnami/etcd
      - ./etcd/snapshot/etcd3:/snapshots
    environment:
      - ETCD_NAME=etcd3
      - ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
      - ETCD_ADVERTISE_CLIENT_URLS=http://etcd3:2379
      - ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380
      - ETCD_INITIAL_ADVERTISE_PEER_URLS=http://etcd3:2380
      - ETCD_INITIAL_CLUSTER=etcd1=http://etcd1:2380,etcd2=http://etcd2:2380,etcd3=http://etcd3:2380,etcd4=http://etcd4:2380,etcd5=http://etcd5:2380
      - ETCD_INITIAL_CLUSTER_STATE=new
      - ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster-1
      - ETCD_ROOT_PASSWORD=1234qwer!!
      - ALLOW_NONE_AUTHENTICATION=yes

  etcd4:
    image: bitnami/etcd:3.5.9
    container_name: etcd4
    restart: unless-stopped
    networks:
      - apisix-network
    ports:
      - "5379:2379"
      - "5380:2380"
    volumes:
      - ./etcd/data/etcd4:/bitnami/etcd
      - ./etcd/snapshot/etcd4:/snapshots
    environment:
      - ETCD_NAME=etcd4
      - ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
      - ETCD_ADVERTISE_CLIENT_URLS=http://etcd4:2379
      - ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380
      - ETCD_INITIAL_ADVERTISE_PEER_URLS=http://etcd4:2380
      - ETCD_INITIAL_CLUSTER=etcd1=http://etcd1:2380,etcd2=http://etcd2:2380,etcd3=http://etcd3:2380,etcd4=http://etcd4:2380,etcd5=http://etcd5:2380
      - ETCD_INITIAL_CLUSTER_STATE=new
      - ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster-1
      - ETCD_ROOT_PASSWORD=1234qwer!!
      - ALLOW_NONE_AUTHENTICATION=yes

  etcd5:
    image: bitnami/etcd:3.5.9
    container_name: etcd5
    restart: unless-stopped
    networks:
      - apisix-network
    ports:
      - "6379:2379"
      - "6380:2380"
    volumes:
      - ./etcd/data/etcd5:/bitnami/etcd
      - ./etcd/snapshot/etcd5:/snapshots
    environment:
      - ETCD_NAME=etcd5
      - ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
      - ETCD_ADVERTISE_CLIENT_URLS=http://etcd5:2379
      - ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380
      - ETCD_INITIAL_ADVERTISE_PEER_URLS=http://etcd5:2380
      - ETCD_INITIAL_CLUSTER=etcd1=http://etcd1:2380,etcd2=http://etcd2:2380,etcd3=http://etcd3:2380,etcd4=http://etcd4:2380,etcd5=http://etcd5:2380
      - ETCD_INITIAL_CLUSTER_STATE=new
      - ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster-1
      - ETCD_ROOT_PASSWORD=1234qwer!!
      - ALLOW_NONE_AUTHENTICATION=yes

  apisix:
    image: apache/apisix:3.3.0-debian
    container_name: apisix
    restart: unless-stopped
    networks:
      - apisix-network
    ports:
      - "9080:9080"
      - "9180:9180"
      - "9091:9091"
    volumes:
      - ./apisix/config/config.yaml:/usr/local/apisix/conf/config.yaml
      - ./apisix/log:/usr/local/apisix/logs
    depends_on:
      - etcd1
      - etcd2
      - etcd3
      - etcd4
      - etcd5

  dashboard:
    image: apache/apisix-dashboard
    container_name: apisix-dashboard
    restart: always
    volumes:
      - ./apisix/config/dashboard.yaml:/usr/local/apisix-dashboard/conf/conf.yaml
    depends_on:
      - etcd1
    ports:
      - "9000:9000/tcp"
    networks:
      - apisix-network 
    
```

### 2.3 APISIX 설정 파일 생성

다음 내용을 `~/apisix-test/apisix/config/config.yaml` 파일로 저장하세요:

```yaml
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    host:
      - "http://etcd1:2379"
      - "http://etcd2:2379"
      - "http://etcd3:2379"
      - "http://etcd4:2379"
      - "http://etcd5:2379"
    prefix: "/apisix"
    timeout: 30
    user: "root" # 추가: etcd에서 생성된 root 사용자
    password: "1234qwer!!" # 추가: etcd 사용자 암호
  admin:
    admin_key_required: true
    admin_key:
      - name: admin
        key: "edd1c9f034335f136f87ad84b625c8f1"
        role: admin
    allow_admin:
      - 0.0.0.0/0
    admin_listen:
      ip: 0.0.0.0
      port: 9180

plugin_attr:
  prometheus:
    export_uri: "/apisix/prometheus/metrics"
    export_addr:
      ip: "0.0.0.0"
      port: 9091

plugins:
  - basic-auth
  - jwt-auth
  - key-auth
  - limit-count
  - prometheus
  - proxy-rewrite
  - response-rewrite
  - cors

```

다음 내용을 `~/apisix-test/apisix/config/dashboard.yaml` 파일로 저장하세요:

```yaml
conf:
  listen:
    host: 0.0.0.0
    port: 9000
  etcd:
    endpoints:
      - "http://etcd1:2379"
      - "http://etcd2:2379"
      - "http://etcd3:2379"
      - "http://etcd4:2379"
      - "http://etcd5:2379"
    prefix: "/apisix"
    timeout: 30
    username: "root"
    password: "1234qwer!!"
  log:
    error_log:
      level: warn
      file_path: logs/error.log
    access_log:
      file_path: logs/access.log

authentication:
  secret: "secret-for-dashboard"
  expire_time: 3600
  users:
    - username: admin
      password: admin
```

### 2.4 복구 스크립트 생성

다음 내용을 `~/apisix-test/restore.py` 파일로 저장하세요:

```python
#!/usr/bin/env python3
# S3에 저장된 etcd 백업 파일을 다운로드하여 로컬 Docker 환경에 복원하는 스크립트

import os
import json
import subprocess
import tempfile
import argparse
import logging
import sys
import boto3
from botocore.exceptions import ClientError
from datetime import datetime

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler(
            f"etcd_restore_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
        ),
        logging.StreamHandler(sys.stdout),
    ],
)
logger = logging.getLogger("etcd_restore")

# 기본 설정
S3_BUCKET = "theshop-lake"
S3_PREFIX = "connect/backup"
LOCAL_RESTORE_DIR = os.path.expanduser("~/apisix-test/restore-temp")


def list_available_backups(
    s3_client, bucket, prefix, backup_type=None, node_name=None, limit=10
):
    """S3에서 사용 가능한 백업 목록을 조회합니다."""

    try:
        # 접두사 구성
        list_prefix = prefix
        if backup_type:
            list_prefix = f"{list_prefix}/{backup_type}"
            if node_name:
                list_prefix = f"{list_prefix}/{node_name}"

        logger.info(f"S3 백업 목록 조회: s3://{bucket}/{list_prefix}")
        response = s3_client.list_objects_v2(
            Bucket=bucket, Prefix=list_prefix, MaxKeys=100
        )

        # 결과 처리
        backups = []
        if "Contents" in response:
            for obj in response["Contents"]:
                # 스냅샷 파일만 목록에 포함
                if obj["Key"].endswith(".snapshot"):
                    # 키에서 정보 추출
                    key_parts = obj["Key"].split("/")
                    if len(key_parts) >= 4:  # prefix/backup_type/node_name/filename
                        backup_info = {
                            "key": obj["Key"],
                            "size": obj["Size"],
                            "last_modified": obj["LastModified"].isoformat(),
                            "backup_type": key_parts[-3] if len(key_parts) >= 4 else "",
                            "node_name": key_parts[-2] if len(key_parts) >= 4 else "",
                            "filename": key_parts[-1],
                        }
                        backups.append(backup_info)

        # 최신 순으로 정렬
        backups.sort(key=lambda x: x["last_modified"], reverse=True)

        # 출력 제한
        if limit > 0 and len(backups) > limit:
            backups = backups[:limit]

        logger.info(f"{len(backups)}개 백업 파일 조회 완료")
        return backups

    except ClientError as e:
        logger.error(f"S3 백업 목록 조회 실패: {str(e)}")
        return []


def download_backup_from_s3(s3_client, bucket, object_key, local_path):
    """S3에서 백업 파일을 다운로드합니다."""

    try:
        logger.info(f"S3 다운로드 시작: s3://{bucket}/{object_key} -> {local_path}")
        s3_client.download_file(bucket, object_key, local_path)
        logger.info(f"S3 다운로드 완료: {local_path}")
        return True

    except ClientError as e:
        logger.error(f"S3 다운로드 실패: {str(e)}")
        return False


def verify_snapshot(snapshot_path):
    """스냅샷 파일의 무결성을 검증합니다."""

    try:
        logger.info(f"스냅샷 무결성 검증 중: {snapshot_path}")

        # Docker 환경에서 검증 명령어 실행
        cmd = [
            "docker",
            "run",
            "--rm",
            "-v",
            f"{os.path.dirname(snapshot_path)}:/snapshots",
            "bitnami/etcd:3.5.9",
            "etcdctl",
            "snapshot",
            "status",
            f"/snapshots/{os.path.basename(snapshot_path)}",
            "-w",
            "table",
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            logger.error(f"스냅샷 무결성 검증 실패: {result.stderr}")
            return False, result.stderr

        logger.info(f"스냅샷 무결성 검증 성공: \n{result.stdout}")
        return True, result.stdout

    except Exception as e:
        logger.error(f"스냅샷 검증 중 오류 발생: {str(e)}")
        return False, str(e)

def restore_snapshot_to_etcd(snapshot_path):
    """스냅샷을 로컬 Docker etcd 클러스터로 복원합니다."""

    try:
        logger.info("etcd 클러스터 중지 중...")
        subprocess.run(
            ["docker-compose", "stop", "etcd1", "etcd2", "etcd3", "etcd4", "etcd5", "apisix", "dashboard"],
            cwd=os.path.expanduser("~/apisix-test"),
            check=True
        )

        # 데이터 디렉토리 백업 및 초기화
        backup_time = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_dir = os.path.expanduser(
            f"~/apisix-test/etcd/backup-before-restore/{backup_time}"
        )
        os.makedirs(backup_dir, exist_ok=True)

        # 모든 etcd 노드 백업 및 초기화
        for i in range(1, 6):
            # 데이터 디렉토리 백업
            node_data_dir = os.path.expanduser(f"~/apisix-test/etcd/data/etcd{i}")
            node_backup_dir = f"{backup_dir}/etcd{i}"

            if os.path.exists(node_data_dir) and os.listdir(node_data_dir):
                logger.info(f"etcd{i} 데이터 백업 중...")
                os.makedirs(node_backup_dir, exist_ok=True)
                subprocess.run(["cp", "-r", f"{node_data_dir}/.", node_backup_dir])

            # 데이터 디렉토리 초기화 - 디렉토리 자체를 삭제하고 새로 생성
            logger.info(f"etcd{i} 데이터 디렉토리 초기화 중...")
            if os.path.exists(node_data_dir):
                subprocess.run(["rm", "-rf", node_data_dir], check=True)
            os.makedirs(node_data_dir, exist_ok=True)
            
            # 도커 사용자(bitnami:root) 권한 설정
            subprocess.run(["chmod", "-R", "777", node_data_dir], check=True)

            # 스냅샷 복원 - etcdutl 사용
            logger.info(f"etcd{i} 노드에 스냅샷 복원 중...")
            cmd = [
                "docker",
                "run",
                "--rm",
                "-v",
                f"{os.path.dirname(snapshot_path)}:/snapshots",
                "-v",
                f"{node_data_dir}:/data",
                "bitnami/etcd:3.5.9",
                "etcdutl",  # etcdctl 대신 etcdutl 사용
                "snapshot",
                "restore",
                f"/snapshots/{os.path.basename(snapshot_path)}",
                "--data-dir=/data",
                "--name",
                f"etcd{i}",
                "--initial-cluster",
                "etcd1=http://etcd1:2380,etcd2=http://etcd2:2380,etcd3=http://etcd3:2380,etcd4=http://etcd4:2380,etcd5=http://etcd5:2380",
                "--initial-cluster-token",
                "etcd-cluster-1",
                "--initial-advertise-peer-urls",
                f"http://etcd{i}:2380"
            ]

            result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode != 0:
                logger.error(f"etcd{i} 복원 실패: {result.stderr}")
                return False, f"etcd{i} 복원 실패: {result.stderr}"

            logger.info(f"etcd{i} 복원 완료")

        # 결과 출력
        logger.info("모든 노드 복원 완료, etcd 데이터 디렉토리 권한 설정 중...")
        
        # 각 노드의 데이터 디렉토리 권한 확인
        for i in range(1, 6):
            node_data_dir = os.path.expanduser(f"~/apisix-test/etcd/data/etcd{i}")
            subprocess.run(["chmod", "-R", "777", node_data_dir], check=True)
            logger.info(f"etcd{i} 데이터 디렉토리 권한 설정 완료")

        # etcd 클러스터 재시작 (etcd1부터 순차적으로)
        logger.info("etcd 클러스터 재시작 중...")
        
        # etcd1 먼저 시작 (리더 역할)
        subprocess.run(
            ["docker-compose", "start", "etcd1"],
            cwd=os.path.expanduser("~/apisix-test"),
            check=True
        )
        
        # 잠시 대기 후 나머지 순차 시작
        logger.info("etcd1 시작 완료, 5초 대기 후 나머지 노드 시작...")
        subprocess.run(["sleep", "5"])
        
        for i in range(2, 6):
            logger.info(f"etcd{i} 시작 중...")
            subprocess.run(
                ["docker-compose", "start", f"etcd{i}"],
                cwd=os.path.expanduser("~/apisix-test"),
                check=True
            )
            subprocess.run(["sleep", "3"])
            
        # 클러스터 모두 시작 후 APISIX 서비스 시작
        logger.info("etcd 클러스터 시작 완료, APISIX 서비스 시작 중...")
        subprocess.run(
            ["docker-compose", "start", "apisix", "dashboard"],
            cwd=os.path.expanduser("~/apisix-test"),
            check=True
        )
        
        logger.info("모든 서비스 시작 완료")
        return True, "스냅샷 복원 및 서비스 재시작 완료"
        
    except Exception as e:
        logger.error(f"복원 중 오류 발생: {str(e)}")
        return False, str(e)
        


def validate_restored_cluster():
    """복원된 클러스터의 상태를 검증합니다."""

    try:
        logger.info("복원된 클러스터 검증 중...")

        # 1. etcd 클러스터 상태 확인
        cmd = [
            "docker",
            "exec",
            "etcd1",
            "etcdctl",
            "endpoint",
            "status",
            "--cluster",
            "-w",
            "table",
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            logger.error(f"클러스터 상태 확인 실패: {result.stderr}")
            return False, "클러스터 상태 확인 실패"

        logger.info(f"클러스터 상태: \n{result.stdout}")

        # 2. APISIX 라우트 확인
        admin_key = "edd1c9f034335f136f87ad84b625c8f1"  # 기본값, 실제 환경에 맞게 조정

        cmd = [
            "curl",
            "-s",
            f"http://localhost:9180/apisix/admin/routes",
            "-H",
            f"X-API-KEY: {admin_key}",
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)

        try:
            routes_data = json.loads(result.stdout)
            route_count = routes_data.get("total", 0)
            logger.info(f"APISIX 라우트 수: {route_count}")

            if route_count > 0:
                logger.info("APISIX 라우트 확인 성공")
            else:
                logger.warning("APISIX 라우트가 없습니다.")
        except json.JSONDecodeError:
            logger.error("APISIX 라우트 정보 파싱 실패")

        # 3. 테스트 요청 수행
        cmd = [
            "curl",
            "-s",
            "-o",
            "/dev/null",
            "-w",
            "%{http_code}",
            "http://localhost:9080/get",
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.stdout.strip() in ["200", "302", "301", "307", "308"]:
            logger.info(f"테스트 요청 성공: HTTP {result.stdout.strip()}")
        else:
            logger.warning(f"테스트 요청 응답: HTTP {result.stdout.strip()}")

        return True, "클러스터 검증 완료"

    except Exception as e:
        logger.error(f"검증 중 오류 발생: {str(e)}")
        return False, str(e)


def main():
    parser = argparse.ArgumentParser(
        description="S3에 저장된 etcd 백업 파일을 다운로드하여 로컬 Docker 환경에 복원"
    )
    parser.add_argument("--bucket", default=S3_BUCKET, help="S3 버킷 이름")
    parser.add_argument("--prefix", default=S3_PREFIX, help="S3 객체 접두사")
    parser.add_argument(
        "--backup-type",
        choices=["daily", "weekly", "monthly"],
        default="daily",
        help="백업 유형",
    )
    parser.add_argument("--node-name", help="특정 노드 이름 (예: etcd1)")
    parser.add_argument("--key", help="복원할 특정 S3 객체 키")
    parser.add_argument(
        "--list-only", action="store_true", help="백업 목록만 표시하고 종료"
    )
    parser.add_argument(
        "--restore-dir", default=LOCAL_RESTORE_DIR, help="로컬 복원 디렉토리"
    )
    args = parser.parse_args()

    # S3 클라이언트 초기화
    s3_client = boto3.client("s3")

    # 임시 디렉토리 생성
    os.makedirs(args.restore_dir, exist_ok=True)

    # 백업 목록 조회
    backups = list_available_backups(
        s3_client=s3_client,
        bucket=args.bucket,
        prefix=args.prefix,
        backup_type=args.backup_type,
        node_name=args.node_name,
        limit=10,
    )

    if not backups:
        logger.error("백업 파일을 찾을 수 없습니다.")
        return

    # 백업 목록 출력
    logger.info("사용 가능한 백업 파일:")
    for i, backup in enumerate(backups):
        logger.info(
            f"{i+1}. {backup['filename']} ({backup['backup_type']}, {backup['node_name']}, {backup['last_modified']})"
        )

    # 목록만 표시하는 경우 종료
    if args.list_only:
        return

    # 특정 키가 지정된 경우
    if args.key:
        selected_key = args.key
        selected_backup = next((b for b in backups if b["key"] == selected_key), None)

        if not selected_backup:
            logger.error(
                f"지정된 키를 가진 백업 파일을 찾을 수 없습니다: {selected_key}"
            )
            return
    else:
        # 사용자 선택
        while True:
            choice = input("복원할 백업 번호를 선택하세요 (또는 'q'를 입력하여 종료): ")

            if choice.lower() == "q":
                return

            try:
                choice_idx = int(choice) - 1
                if 0 <= choice_idx < len(backups):
                    selected_backup = backups[choice_idx]
                    break
                else:
                    print(f"유효한 번호를 입력하세요 (1-{len(backups)})")
            except ValueError:
                print("숫자를 입력하세요")

    # 선택된 백업 정보 출력
    logger.info(f"선택된 백업: {selected_backup['filename']}")
    logger.info(f"백업 유형: {selected_backup['backup_type']}")
    logger.info(f"노드: {selected_backup['node_name']}")
    logger.info(f"마지막 수정일: {selected_backup['last_modified']}")

    # 백업 파일 다운로드
    local_snapshot_path = os.path.join(args.restore_dir, selected_backup["filename"])

    if not download_backup_from_s3(
        s3_client=s3_client,
        bucket=args.bucket,
        object_key=selected_backup["key"],
        local_path=local_snapshot_path,
    ):
        logger.error("백업 파일 다운로드 실패. 종료합니다.")
        return

    # 스냅샷 무결성 검증
    success, verify_message = verify_snapshot(local_snapshot_path)
    if not success:
        logger.error("스냅샷 무결성 검증 실패. 종료합니다.")
        return

    # 복원 확인
    confirm = input(
        "선택한 백업을 복원하시겠습니까? 이 작업은 현재 클러스터를 덮어쓰게 됩니다. (y/n): "
    )
    if confirm.lower() != "y":
        logger.info("복원 작업이 취소되었습니다.")
        return

    # 스냅샷 복원
    success, restore_message = restore_snapshot_to_etcd(local_snapshot_path)
    if not success:
        logger.error(f"스냅샷 복원 실패: {restore_message}")
        return

    logger.info("스냅샷 복원 완료!")

    # 복원된 클러스터 검증
    success, validate_message = validate_restored_cluster()
    if not success:
        logger.warning(f"클러스터 검증 주의: {validate_message}")
    else:
        logger.info(f"클러스터 검증 성공: {validate_message}")

    # 마무리
    logger.info("복원 프로세스가 완료되었습니다.")
    logger.info(
        f"테스트를 위해 다음 명령어를 사용하세요: curl http://localhost:9080/ip"
    )


if __name__ == "__main__":
    main()


```

## 3. 백업 프로세스

### 3.1 AWS 자격 증명 설정

S3에서 백업 파일을 다운로드하기 위해 AWS 자격 증명을 설정해야 합니다:

```bash
mkdir -p ~/.aws
cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = YOUR_ACCESS_KEY_ID
aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
EOF

cat > ~/.aws/config << EOF
[default]
region = ap-northeast-2
EOF
```

### 3.2 필요한 패키지 설치

```bash
pip install boto3 argparse
```

## 4. 복구 절차

### 4.1 Docker Compose 환경 시작

```bash
cd ~/apisix-test
docker-compose up -d
```

이 명령은 5개의 etcd 노드와 APISIX, Dashboard를 포함한 전체 환경을 시작합니다.

### 4.2 환경 확인

```bash
# etcd 클러스터 상태 확인
docker exec etcd1 etcdctl endpoint health --cluster

# APISIX 상태 확인
curl http://localhost:9080/apisix/status
```

### 4.3 백업 목록 조회

```bash
cd ~/apisix-test
python3 restore.py --list-only
```
결과
```bash
2025-03-14 17:27:39,405 - botocore.credentials - INFO - Found credentials in environment variables.
2025-03-14 17:27:39,493 - etcd_restore - INFO - S3 백업 목록 조회: s3://theshop-lake/connect/backup/daily
2025-03-14 17:27:39,940 - etcd_restore - INFO - 1개 백업 파일 조회 완료
2025-03-14 17:27:39,940 - etcd_restore - INFO - 사용 가능한 백업 파일:
2025-03-14 17:27:39,941 - etcd_restore - INFO - 1. etcd1_daily_20250314_163504.snapshot (daily, etcd1, 2025-03-14T07:35:06+00:00)
```

이 명령은 S3에 저장된 백업 파일의 목록을 표시합니다.

### 4.4 백업 복원 실행

```bash
# 대화형 모드로 복구 스크립트 실행
python3 restore.py

# 특정 백업 파일로 직접 복원
python3 restore.py --key connect/backup/daily/etcd1/etcd1_daily_20250314_152743.snapshot
```

복원 스크립트는 다음 단계를 자동으로 수행합니다:

1. S3에서 선택한 백업 파일을 다운로드
2. 백업 파일의 무결성 검증
3. etcd 클러스터와 APISIX 서비스 중지
4. 기존 데이터 백업
5. 5개 노드의 etcd 데이터 디렉토리 초기화
6. 백업 파일에서 각 노드로 데이터 복원
7. 클러스터 재시작 (etcd1부터 순차적으로)
8. APISIX 및 Dashboard 재시작
9. 복원된 클러스터 검증

## 5. 복구 검증

### 5.1 etcd 클러스터 상태 확인

```bash
# 클러스터 상태 확인
docker exec etcd1 etcdctl --user root:1234qwer!! endpoint status --cluster -w table

# 클러스터 헬스 체크
docker exec etcd1 etcdctl --user root:1234qwer!! endpoint health --cluster
```

### 5.2 APISIX 상태 확인

```bash
# APISIX Admin API 접근
curl http://localhost:9180/apisix/admin/routes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1'

# APISIX 상태 확인
curl http://localhost:9080/apisix/status
```

### 5.3 테스트 라우트 생성

```bash
# 테스트 라우트 생성
curl http://localhost:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' \
-X PUT -d '
{
    "uri": "/get",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org:80": 1
        }
    }
}'

# 테스트 요청
curl -i http://localhost:9080/get
```

### 5.4 Dashboard 접근

브라우저에서 `http://localhost:9000` 접속하여 Dashboard가 정상적으로 동작하는지 확인합니다. 
(기본 계정: admin/admin)

## 문제 해결

### 노드 상태 불일치

클러스터 노드 간 상태가 일치하지 않는 경우:

```bash
# 모든 노드 상태 확인
docker exec etcd1 etcdctl endpoint status --cluster -w table

# 클러스터 다시 시작
cd ~/apisix-test
docker-compose down
docker-compose up -d
```

### 데이터 일관성 문제

데이터 일관성 문제가 발생한 경우:

```bash
# 데이터 해시 값 확인
docker exec etcd1 etcdctl endpoint hashkv --cluster -w table

# 문제가 지속되면 다시 복원 시도
python3 restore.py
```

### APISIX 연결 문제

APISIX가 etcd에 연결하지 못하는 경우:

```bash
# APISIX 로그 확인
cat ~/apisix-test/apisix/log/error.log

# etcd 연결 확인
docker exec apisix curl -s http://etcd1:2379/health

# APISIX 재시작
docker-compose restart apisix
```

## 결론

이 문서는 운영 환경의 APISIX etcd 클러스터를 로컬 환경에서 복제하고, S3에 저장된 백업으로부터 복구하는 방법을 설명했습니다. 복구 프로세스는 5개의 etcd 노드와 APISIX, Dashboard를 포함한 전체 환경을 일관성 있게 복원합니다.

이러한 복구 테스트는 실제 장애 상황에서 신속하게 대응할 수 있는 능력을 확보하는 데 중요합니다. 정기적인 테스트를 통해 복구 절차를 검증하고 개선하는 것을 권장합니다.