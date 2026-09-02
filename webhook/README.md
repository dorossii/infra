# webhook デプロイ

backend の main ブランチが更新され、GHCR にイメージが push されたら、
GitHub Actions からこの webhook を叩いて Debian サーバー上のコンテナを更新する。

## 仕組み

1. backend の `release.yml` がイメージを build & push
2. infra リポジトリの `docker-compose.yaml` のイメージタグを書き換えて push
3. Cloudflare Tunnel (サーバー上の既存 cloudflared) 経由で `webhook` コンテナに
   HTTPS で通知
4. `webhook` コンテナが `deploy.sh` を実行し、サーバー上で
   `git pull && docker compose pull && docker compose up -d` を行う

`webhook` コンテナは `127.0.0.1:9000` にのみ公開しており、外部から直接は
到達できない。サーバー上で既に動いている cloudflared (システムサービス) に
Public Hostname を追加することで到達可能にする。

## セットアップ

### 1. 既存 Cloudflare Tunnel に Public Hostname を追加

Cloudflare Zero Trust ダッシュボード (Networks > Tunnels) で、
サーバー上で動いている既存の Tunnel を開き、Public Hostname を追加する。

| Public Hostname | Service |
| --- | --- |
| `deploy-dorossii.mattuu.com` | `http://localhost:9000` |

### 2. config/webhook.env を作成

```
DEPLOY_SECRET=<十分に長いランダム文字列>
```

この値は GitHub 側 (backend リポジトリ) の Secrets `DEPLOY_WEBHOOK_SECRET` にも
同じ値を登録する。

### 3. 起動

```
docker compose up -d webhook
```

### 4. 動作確認

```
curl -X POST https://deploy-dorossii.mattuu.com/hooks/deploy \
  -H "X-Deploy-Secret: <DEPLOY_SECRET>"
```

`deploy triggered` が返り、サーバー上で pull & up -d が走ることを確認する。
