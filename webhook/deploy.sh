#!/bin/sh
set -eu

# HOST_INFRA_DIR: ホスト上の infra リポジトリの絶対パス。
# webhook コンテナには「ホストと同じ絶対パス」で infra ディレクトリを
# マウントしているため、docker compose 側から見ても env_file や
# bind mount の相対パスがホスト上のパスとしてそのまま解決できる。
: "${HOST_INFRA_DIR:?HOST_INFRA_DIR is required}"

cd "${HOST_INFRA_DIR}"

git pull --ff-only

COMPOSE="docker compose --project-directory ${HOST_INFRA_DIR} -f ${HOST_INFRA_DIR}/docker-compose.yaml"

# app コンテナの再作成前の StartedAt を記録しておく。
# pull 失敗などで実際には再作成されなかった場合に検知するため。
BEFORE_STARTED_AT=$(docker inspect dorossii-backend-app-1 --format '{{.State.StartedAt}}' 2>/dev/null || echo "none")

$COMPOSE pull
$COMPOSE up -d --remove-orphans

AFTER_STARTED_AT=$(docker inspect dorossii-backend-app-1 --format '{{.State.StartedAt}}' 2>/dev/null || echo "none")

if [ "${BEFORE_STARTED_AT}" = "${AFTER_STARTED_AT}" ]; then
    echo "app container was not recreated (StartedAt unchanged: ${AFTER_STARTED_AT})"
    exit 1
fi

echo "app container recreated: ${BEFORE_STARTED_AT} -> ${AFTER_STARTED_AT}"
