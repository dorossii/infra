#!/bin/sh
set -eu

cd /infra

git pull --ff-only
docker compose pull

# webhook 自身が再作成されると up -d プロセスが道連れで中断されるため、
# 他のサービスを先に上げてから webhook は切り離して最後に更新する
docker compose up -d --remove-orphans --no-deps app auth migrate mysql nginx
nohup docker compose up -d --no-deps webhook >/tmp/webhook-selfupdate.log 2>&1 &
