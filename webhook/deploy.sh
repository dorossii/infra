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

$COMPOSE pull
$COMPOSE up -d --remove-orphans
