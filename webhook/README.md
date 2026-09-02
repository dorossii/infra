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

`webhook` コンテナは docker.sock をマウントしてホストの docker compose を
操作しているが、パスの扱いに 2 つの罠がある。

1. **bind mount の相対パス解決はホスト側 (Docker daemon) が行う。**
   `./nginx/keys` のような相対パスは、docker compose を実行した
   カレントディレクトリ (`--project-directory`) を基準に、
   **ホスト上のパスとして** 解決される。ここにコンテナ内パス
   (`/infra`) を渡すと、ホスト上に存在しない空ディレクトリが
   新規作成されて nginx の設定・証明書が読み込めなくなる。
2. **`-f` (compose ファイル自体の読み込み) は docker compose CLI
   プロセスの視点で行われる。** この CLI は webhook コンテナ内で
   動いているので、`-f` にはコンテナ内パス (`/infra/docker-compose.yaml`)
   を渡す必要がある。ここにホストパスを渡すと
   `stat: no such file or directory` で失敗する。

そのため `deploy.sh` では `HOST_INFRA_DIR` (ホスト上の infra
リポジトリの絶対パス) を明示し、

```
docker compose --project-directory ${HOST_INFRA_DIR} -f /infra/docker-compose.yaml
```

という組み合わせで実行している
(`--project-directory` はホストパス、`-f` はコンテナ内パス)。

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
HOST_INFRA_DIR=<ホスト上の infra リポジトリの絶対パス (例: /root/dorossii/infra)>
```

`DEPLOY_SECRET` は GitHub 側 (backend リポジトリ) の Secrets
`DEPLOY_WEBHOOK_SECRET` にも同じ値を登録する。

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
