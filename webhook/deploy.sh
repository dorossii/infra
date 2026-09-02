#!/bin/sh
set -eu

# HOST_INFRA_DIR: ホスト上の infra リポジトリの絶対パス。
# docker.sock 経由で docker compose を実行するため、bind mount の相対パスは
# 常にこのディレクトリを基準にホスト側のパスとして解決する必要がある
# (webhook コンテナ内のパス /infra をそのまま使うとホスト上に存在しない
#  パスとして bind mount が作られてしまう)。
: "${HOST_INFRA_DIR:?HOST_INFRA_DIR is required}"

cd /infra

git pull --ff-only

# -f には webhook コンテナ内のパス(/infra/docker-compose.yaml)を渡す
# (docker compose CLI プロセス自体がこのコンテナ内で動いているため)。
# --project-directory にはホスト上の絶対パスを渡す
# (bind mount の相対パス解決は Docker daemon がホスト側で行うため)。
COMPOSE="docker compose --project-directory ${HOST_INFRA_DIR} -f /infra/docker-compose.yaml"

$COMPOSE pull
$COMPOSE up -d --remove-orphans
