#!/bin/sh
set -eu

cd /infra

git pull --ff-only
docker compose pull
docker compose up -d --remove-orphans
