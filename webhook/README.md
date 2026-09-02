# webhook デプロイ

backend の main ブランチが更新され、GHCR にイメージが push されたら、
GitHub Actions からこの webhook を叩いて Debian サーバー上のコンテナを更新する。

## 仕組み

1. backend の `release.yml` がイメージを build & push
2. infra リポジトリの `docker-compose.yaml` のイメージタグを書き換えて push
3. Cloudflare Tunnel (別サーバーの既存 cloudflared) 経由で `webhook` コンテナに
   HTTPS で通知
4. `webhook` コンテナが `deploy.sh` を実行し、サーバー上で
   `git pull && docker compose pull && docker compose up -d` を行う

`webhook` コンテナは `0.0.0.0:9000` で公開している。cloudflared は
別サーバーで動いているため、Public Hostname の Service には
このサーバーの IP (`192.168.10.33`) を指定する。

シークレット (`X-Deploy-Secret` ヘッダー) による認証は必須なので、
ポート自体がネットワーク内に開いていても deploy.sh は正しいシークレットが
無い限り実行されない。

`webhook` はメインの `docker-compose.yaml` (プロジェクト名 `dorossii-backend`)
とは別に、`webhook/docker-compose.yaml` (プロジェクト名 `dorossii-webhook`) で
独立して動かしている。同じ compose プロジェクトに入れると、deploy.sh が
`docker compose up -d` を実行した際に webhook 自身も再作成対象になり、
実行中のプロセスが強制終了して他サービスの更新が中断されてしまうため。

## セットアップ

### 1. 既存 Cloudflare Tunnel に Public Hostname を追加

Cloudflare Zero Trust ダッシュボード (Networks > Tunnels) で、
別サーバーで動いている既存の Tunnel を開き、Public Hostname を追加する。

| Public Hostname | Service |
| --- | --- |
| `deploy-dorossii.mattuu.com` | `http://192.168.10.33:9000` |

### 2. config/webhook.env を作成

```
DEPLOY_SECRET=<十分に長いランダム文字列>
```

この値は GitHub 側 (backend リポジトリ) の Secrets `DEPLOY_WEBHOOK_SECRET` にも
同じ値を登録する。

### 3. 起動

```
cd webhook
docker compose up -d
```

### 4. 動作確認

```
curl -X POST https://deploy-dorossii.mattuu.com/hooks/deploy \
  -H "X-Deploy-Secret: <DEPLOY_SECRET>"
```

`deploy triggered` が返り、サーバー上で pull & up -d が走ることを確認する。
