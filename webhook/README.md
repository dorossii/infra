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
操作しているが、パスの扱いに罠がある。

- **bind mount の相対パス解決はホスト側 (Docker daemon) が行う。**
  `./nginx/keys` のような相対パスは `--project-directory` を基準に
  **ホスト上のパスとして** 解決される。
- **`-f` (compose ファイル読み込み) や `env_file` の読み込みは
  docker compose CLI プロセス自身 (webhook コンテナ内) が行う。**
  そのためこれらのパスは **webhook コンテナから見えるパス** で
  なければならない。

この 2 つが同じパス文字列を要求するにも関わらず基準(ホスト/コンテナ)が
異なるため、`/infra` のような別名でマウントすると必ずどちらかが壊れる。

解決策として、webhook コンテナに **ホストと全く同じ絶対パス**
(`HOST_INFRA_DIR`) で infra ディレクトリをマウントしている。
これにより `--project-directory` にも `-f` にも `env_file` にも
同じ `${HOST_INFRA_DIR}` を渡せば、ホスト側・コンテナ側どちらの
解決でも正しいファイルを指す。

## セットアップ

### 1. 既存 Cloudflare Tunnel に Public Hostname を追加

Cloudflare Zero Trust ダッシュボード (Networks > Tunnels) で、
別サーバーで動いている既存の Tunnel を開き、Public Hostname を追加する。

| Public Hostname | Service |
| --- | --- |
| `deploy-dorossii.mattuu.com` | `http://192.168.10.33:9000` |

### 2. config/webhook.env を作成 (コンテナ実行時の環境変数)

```
DEPLOY_SECRET=<十分に長いランダム文字列>
HOST_INFRA_DIR=<ホスト上の infra リポジトリの絶対パス (例: /root/dorossii/infra)>
```

`DEPLOY_SECRET` は GitHub 側 (backend リポジトリ) の Secrets
`DEPLOY_WEBHOOK_SECRET` にも同じ値を登録する。

### 3. webhook/.env を作成 (docker compose 自体の変数展開用)

`webhook/.env.example` を参考に、`webhook/.env` を作成する。
`HOST_INFRA_DIR` と `HOST_WEBHOOK_DIR` はホスト上の絶対パスと
完全に一致させる必要がある (ホストと同じパスでコンテナに
マウントするため)。

```
HOST_INFRA_DIR=/root/dorossii/infra
HOST_WEBHOOK_DIR=/root/dorossii/infra/webhook
```

### 4. 起動

```
cd webhook
docker compose up -d
```

### 5. 動作確認

```
curl -X POST https://deploy-dorossii.mattuu.com/hooks/deploy \
  -H "X-Deploy-Secret: <DEPLOY_SECRET>"
```

`deploy triggered` が返り、サーバー上で pull & up -d が走ることを確認する。
