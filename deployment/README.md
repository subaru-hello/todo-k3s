# Helm Chart デプロイメント

自宅k3sでの手動pull運用によるAPI + PostgreSQL のHelm Chartデプロイ構成です。

## ⚠️ 古いデプロイメントをお使いの方へ

もし以前のKustomizeベースのデプロイメントや、`node-app`、`go-echo`などの古いデプロイメントが残っている場合は、まず以下のクリーンアップスクリプトを実行してください:

```bash
./deployment/cleanup-old-deployments.sh
```

これにより、CrashLoopBackOff状態の古いPodが削除され、クリーンな状態でHelm Chartをデプロイできます。

## 📁 ディレクトリ構造

```
deployment/
├── charts/
│   ├── postgres/          # PostgreSQL Helm Chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── secret.yaml
│   │       ├── statefulset.yaml
│   │       ├── service.yaml
│   │       └── networkpolicy.yaml
│   └── api/               # API Helm Chart
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           └── service.yaml
├── environments/
│   ├── local/             # ローカル環境設定
│   │   ├── postgres-values.yaml
│   │   └── api-values.yaml
│   └── prod/              # 本番環境設定
│       ├── postgres-values.yaml
│       └── api-values.yaml
├── cloudflare-tunnel/     # Cloudflare Tunnel設定（本番のみ）
│   ├── config-prod.yaml
│   ├── deployment-prod.yaml
│   ├── secret-prod.yaml.example
│   └── README.md
├── scripts/
│   └── deploy.sh          # デプロイスクリプト
└── cleanup-old-deployments.sh  # 古いデプロイメント削除スクリプト
```

## 🚀 クイックスタート

### ローカル環境

```bash
# リポジトリルートで実行
./deployment/scripts/deploy.sh local

# APIにアクセス（別ターミナル）
kubectl -n app port-forward svc/api 3000:3000

# テスト
curl http://localhost:3000/healthz
curl http://localhost:3000/dbcheck
curl http://localhost:3000/api/todos
```

### 本番環境

```bash
# 1. Secret設定（初回のみ）
cd deployment/environments/prod
cp .env.secret.example .env.secret
nano .env.secret  # POSTGRES_USER, POSTGRES_PASSWORD, JWT_SECRET を設定

# 2. 最新のイメージタグを確認
# Docker Hub: https://hub.docker.com/r/subaru88/home-kube/tags
# GitHub Actions: リポジトリの Actions タブ → 最新ワークフロー
#
# 推奨: GitHub Actionsが自動生成するコミットハッシュタグ(sha-xxx)を使用
# 例: sha-329968d

# 3. サーバーでデプロイ（.env.secret から自動的に Secret 作成）
./deployment/scripts/deploy.sh prod sha-329968d  # ← 確認したタグを指定

# 4. Cloudflare Tunnel設定（初回のみ）
# deployment/cloudflare-tunnel/README.md を参照

# 5. 外部からアクセス
curl https://api.octomblog.com/healthz
```

**💡 イメージタグについて**:
- **推奨**: `sha-329968d` (GitHub Actionsが自動生成)
  - 再現性が高い
  - 特定のコミットに紐付く
  - ロールバックが容易
- **非推奨**: `latest`
  - どのバージョンか不明
  - 予期しない変更が入る可能性

## 🏗️ アーキテクチャ

### ローカル環境

```
開発PC
  ↓ kubectl port-forward
k3s Node
  ├── API Pod (replicas: 1)
  │   └── ClusterIP Service
  └── PostgreSQL StatefulSet
      └── PVC (local-path, 5Gi)
```

- **namespace**: `app`
- **CORS**: `http://localhost:5173`
- **NetworkPolicy**: 無効（デバッグしやすいよう）
- **アクセス**: `kubectl port-forward`

### 本番環境

```
インターネット
  ↓ https://api.octomblog.com
Cloudflare Edge
  ↓
Cloudflare Tunnel Pod
  ↓ http://api.app.svc.cluster.local:3000
k3s Node
  ├── API Pod (replicas: 2)
  │   └── ClusterIP Service
  └── PostgreSQL StatefulSet
      ├── PVC (local-path, 20Gi)
      └── NetworkPolicy (API Podからのみ許可)
```

- **namespace**: `app`
- **CORS**: `https://prod-app.octomblog.com`
- **NetworkPolicy**: 有効（DB保護）
- **アクセス**: Cloudflare Tunnel

## 📦 イメージビルド

### 開発環境用（デバッグ可能）

```bash
docker build --target development -t docker.io/subaru88/home-kube:dev ./packages/api
```

### 本番環境用（distroless、セキュア）

```bash
# GitHub Actionsで自動ビルド(推奨)
# git pushすると自動的にsha-xxxタグでビルドされます

# 手動ビルドする場合
cd packages/api
docker build --target production \
  -t docker.io/subaru88/home-kube:sha-$(git rev-parse --short HEAD) .
docker push docker.io/subaru88/home-kube:sha-$(git rev-parse --short HEAD)
```

## 🔧 カスタマイズ

### 環境変数の変更

**本番環境の Secret（推奨）**

`deployment/environments/prod/.env.secret` を編集：

```bash
POSTGRES_USER=youruser
POSTGRES_PASSWORD=強力なパスワード
POSTGRES_DB=yourdb
JWT_SECRET=ランダムな長い文字列
```

デプロイ時に自動的に Kubernetes Secret として作成されます。

**ローカル環境**

`deployment/environments/local/api-values.yaml` を編集：

```yaml
env:
  NODE_ENV: development
  ALLOWED_ORIGINS: "http://localhost:5173"
  JWT_SECRET: "local-dev-secret"
```

### PostgreSQL設定の変更

`deployment/environments/{local,prod}/postgres-values.yaml` を編集：

```yaml
# 注意: 本番環境では .env.secret の値が優先されます
auth:
  username: postgres  # フォールバック値
  password: postgres  # フォールバック値
  database: todos

persistence:
  size: 50Gi
```

### リソース制限の変更

```yaml
resources:
  requests:
    cpu: "200m"
    memory: "512Mi"
  limits:
    cpu: "1000m"
    memory: "1Gi"
```

## 🔍 トラブルシューティング

### Podが起動しない

```bash
kubectl -n app get pods
kubectl -n app describe pod <pod-name>
kubectl -n app logs <pod-name>
```

### DBに接続できない

```bash
# PostgreSQL Pod確認
kubectl -n app get pod -l app=postgres
kubectl -n app logs -l app=postgres

# API PodからDB接続テスト
kubectl -n app exec -it <api-pod-name> -- sh
```

### イメージがpullできない

```bash
# ローカルイメージ確認（k3s）
sudo nerdctl -n k8s.io images | grep home-kube

# 手動pull
sudo nerdctl -n k8s.io pull docker.io/subaru88/home-kube:v1.0.0
```

### Helm Chartの検証

```bash
# テンプレート生成確認
helm template postgres ./deployment/charts/postgres \
  -f ./deployment/environments/local/postgres-values.yaml

# Dry-run
helm upgrade --install postgres ./deployment/charts/postgres \
  -n app -f ./deployment/environments/local/postgres-values.yaml --dry-run
```

## 🔄 更新手順

### APIのアップデート

#### 方法1: GitHub Actions経由(推奨)

```bash
# 1. コードを修正してpush
git add packages/api
git commit -m "feat: 新機能を追加"
git push

# 2. GitHub Actionsの完了を待つ
# GitHub → Actions タブで自動ビルドを確認

# 3. 生成されたタグを確認
# GitHub Actions のログから sha-xxxxxxx を確認
# https://hub.docker.com/r/subaru88/home-kube/tags

# 4. サーバーでデプロイ
./deployment/scripts/deploy.sh prod sha-abc1234  # ← 確認したタグ

# 5. ローリングアップデート確認
kubectl -n app rollout status deployment/api
```

#### 方法2: 手動ビルド&プッシュ

```bash
# 1. ローカルでビルド
cd packages/api
docker build --target production -t docker.io/subaru88/home-kube:sha-$(git rev-parse --short HEAD) .
docker push docker.io/subaru88/home-kube:sha-$(git rev-parse --short HEAD)

# 2. サーバーでデプロイ
./deployment/scripts/deploy.sh prod sha-$(git rev-parse --short HEAD)
```

### PostgreSQLのアップデート

```bash
# values.yamlのimageタグを更新後
helm upgrade postgres ./deployment/charts/postgres \
  -n app -f ./deployment/environments/prod/postgres-values.yaml
```

## 🧹 クリーンアップ

```bash
# 特定の環境を削除
helm uninstall api -n app
helm uninstall postgres -n app

# Namespace全体を削除
kubectl delete namespace app
```

## 🔄 GitHub Actions連携（CI/CD）

### 概要

packages/api/ の変更を `main` ブランチにpushすると、自動的にDockerイメージがビルド・pushされます。

### ワークフロー

```
開発PC
  ├── packages/api/ 編集
  ├── git commit & push
  └── GitHub へpush
       ↓
GitHub Actions
  ├── Dockerイメージビルド（本番用・distroless）
  ├── マルチアーキテクチャ対応（amd64, arm64）
  └── Docker Hubへpush
       ↓
別サーバー（k3s）
  ├── git pull（deployment/ のみ）
  ├── nerdctl pull（イメージ）
  └── helm upgrade（デプロイ）
```

### GitHub Secretsの設定（初回のみ）

1. GitHubリポジトリ → Settings → Secrets and variables → Actions
2. 以下のSecretを追加：

| Name | Value | 取得方法 |
|------|-------|---------|
| `DOCKER_USERNAME` | `subaru88` | Docker Hubのユーザー名 |
| `DOCKER_PASSWORD` | `dckr_pat_xxx...` | [Docker Hub PAT](https://hub.docker.com/settings/security) |

### 別サーバーでのデプロイ手順

#### 初回セットアップ

```bash
# deployment/ のみクローン（sparse-checkout）
git clone --filter=blob:none --sparse https://github.com/YOUR_ORG/todo-k3s.git
cd todo-k3s
git sparse-checkout set deployment

# 本番環境のSecret設定
cd deployment/environments/prod
cp .env.secret.example .env.secret
nano .env.secret  # PostgreSQLパスワード、JWT_SECRET等を設定

# .env.secret の内容例:
# POSTGRES_USER=produser
# POSTGRES_PASSWORD=強力なパスワード
# POSTGRES_DB=todos
# JWT_SECRET=ランダムな長い文字列

# 注意: deploy.sh 実行時に自動的に Kubernetes Secret が作成されるため、
#       kubectl create secret を手動で実行する必要はありません
```

#### 通常のデプロイ

```bash
# 1. GitHub Actionsのビルド完了を確認
# GitHub → Actions タブでワークフローが成功していることを確認

# 2. 最新コードを取得
git pull

# 3. ビルドされたイメージのタグを確認
# GitHub Actions のログから sha-xxxxxxx を確認
# または GitHub → Actions → 該当ワークフロー → "Output image tags" を確認

# 4. イメージをpull
sudo nerdctl -n k8s.io pull docker.io/subaru88/home-kube:sha-abc1234

# 5. デプロイ
./deployment/scripts/deploy.sh prod sha-abc1234

# 6. 確認
kubectl -n app get pods
kubectl -n app logs -l app=api
```

### イメージタグの種類

GitHub Actionsが自動生成するタグ：

| タグ | 説明 | 例 |
|------|------|-----|
| `sha-{commit}` | コミットハッシュ（推奨） | `sha-abc1234` |
| `latest` | mainブランチの最新 | `latest` |
| `main` | mainブランチ | `main` |

**推奨**: 本番環境では `sha-{commit}` タグを使用（特定バージョン固定）

### 手動ビルド（GitHub Actions経由）

```bash
# GitHub → Actions → "Build and Push Docker Image" → "Run workflow"
# ブランチを選択して実行
```

### トラブルシューティング

#### GitHub Actionsが失敗する

```bash
# GitHub → Actions → 該当ワークフロー → ログ確認

# よくあるエラー:
# - Docker Hub認証エラー → Secretsを再設定
# - ビルドエラー → packages/api/Dockerfile を確認
```

#### イメージがpullできない

```bash
# Docker Hubで公開されているか確認
# https://hub.docker.com/r/subaru88/home-kube/tags

# 手動ログイン確認
sudo nerdctl login docker.io
```

## 📚 参考

- [Helm Documentation](https://helm.sh/docs/)
- [Kubernetes StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [k3s Documentation](https://docs.k3s.io/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)