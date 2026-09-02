# webhook デプロイ

backend の main ブランチが更新され、GHCR にイメージが push されたら、
GitHub Actions からこの webhook を叩いて Debian サーバー上のコンテナを更新する。

## 仕組み

1. backend の `release.yml` がイメージを build & push
2. infra リポジトリの `docker-compose.yaml` のイメージタグを書き換えて push
3. Cloudflare Tunnel 経由で `webhook` コンテナに HTTPS で通知
4. `webhook` コンテナが `deploy.sh` を実行し、サーバー上で
   `git pull && docker compose pull && docker compose up -d` を行う

## セットアップ

### 1. Cloudflare Tunnel を作成

Cloudflare Zero Trust ダッシュボード (Networks > Tunnels) で
Tunnel を作成し、以下の Public Hostname を設定する。

| Public Hostname | Service |
| --- | --- |
| `deploy-dorossii.mattuu.com` | `http://webhook:9000` |

作成後に発行される Tunnel Token を控えておく。

### 2. config/cloudflared.env を作成

```
TUNNEL_TOKEN=<Cloudflare で発行したトークン>
```

### 3. config/webhook.env を作成

```
DEPLOY_SECRET=<十分に長いランダム文字列>
```

この値は GitHub 側 (backend リポジトリ) の Secrets `DEPLOY_WEBHOOK_SECRET` にも
同じ値を登録する。

### 4. 起動

```
docker compose up -d webhook cloudflared
```

### 5. 動作確認

```
curl -X POST https://deploy-dorossii.mattuu.com/hooks/deploy \
  -H "X-Deploy-Secret: <DEPLOY_SECRET>"
```

`deploy triggered` が返り、サーバー上で pull & up -d が走ることを確認する。
