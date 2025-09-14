# GitOps Deployment Guide

このディレクトリには、Kubernetes (k3s) へのデプロイに必要なマニフェストファイルが含まれています。

## 📁 ディレクトリ構造

```
deploy/
├── base/                    # 基本となるKubernetesマニフェスト
│   ├── namespace.yaml       # Namespace定義
│   ├── postgres.yaml        # PostgreSQLのDeployment/Service/PVC
│   ├── app-deployment.yaml  # アプリケーションのDeployment
│   ├── app-service.yaml     # アプリケーションのService
│   ├── app-ingress.yaml     # Ingress設定
│   └── kustomization.yaml   # Kustomize設定
│
├── overlays/               # 環境別の設定
│   ├── dev/               # 開発環境
│   │   ├── .env.secret.example     # Secret設定のテンプレート
│   │   ├── .env.secret            # 実際のSecret値（Gitには含まれない）
│   │   ├── ingress-patch.yaml     # 開発環境用のIngress設定
│   │   ├── imagepullsecret-patch.yaml  # DockerHub認証設定
│   │   └── kustomization.yaml     # 開発環境のKustomize設定
│   │
│   └── prod/              # 本番環境
│       ├── .env.secret.example    # Secret設定のテンプレート
│       └── kustomization.yaml     # 本番環境のKustomize設定
│
└── deploy.sh              # デプロイ自動化スクリプト
```

## 🚀 初回セットアップ

### 1. リポジトリのクローン

```bash
git clone <repository-url>
cd todo-k3s
```

### 2. 環境変数の設定

```bash
# イメージ設定用の環境変数ファイルを作成
cp deploy/.env.example deploy/.env
# 必要に応じて編集（デフォルト値で動作します）
nano deploy/.env
```

`deploy/.env`の内容:
```env
DOCKER_REGISTRY=docker.io
DOCKER_USER=subaru88
APP_NAME=home-kube
IMAGE_TAG=latest
```

### 3. Secret設定ファイルの作成

```bash
# 開発環境用
cp deploy/overlays/dev/.env.secret.example deploy/overlays/dev/.env.secret
# 実際の値に編集
nano deploy/overlays/dev/.env.secret
```

`.env.secret`の内容:
```env
POSTGRES_USER=myuser
POSTGRES_PASSWORD=mypassword
```

### 3. DockerHub認証の設定（プライベートイメージの場合）

```bash
# DockerHub Personal Access Token (PAT) を使用
kubectl create secret docker-registry regcred \
  --docker-server=docker.io \
  --docker-username=subaru88 \
  --docker-password='YOUR_DOCKER_PAT_TOKEN' \
  --docker-email='your-email@example.com' \
  -n todo-app --dry-run=client -o yaml > regcred.yaml

kubectl apply -f regcred.yaml
rm regcred.yaml  # セキュリティのため削除
```

### 5. 初回デプロイ

```bash
# 自動デプロイスクリプトを使用（環境変数から自動的にkustomization.yamlを生成）
./deploy/deploy.sh dev

# または手動で
./deploy/generate-kustomization.sh  # 環境変数からkustomization.yamlを生成
kubectl apply -k deploy/overlays/dev
```

## 📝 日常のデプロイフロー

### アプリケーション更新時

1. **コード変更とイメージビルド（ローカルPC）**
```bash
cd app
make deploy  # Docker imageのビルドとプッシュ
```

2. **デプロイ（リモートPC/k3sノード）**
```bash
cd todo-k3s
git pull
./deploy/deploy.sh dev
```

### 設定変更時

1. **マニフェスト更新（ローカルPC）**
```bash
# deploy/配下のYAMLファイルを編集
git add .
git commit -m "Update k8s manifests"
git push
```

2. **適用（リモートPC/k3sノード）**
```bash
git pull
kubectl apply -k deploy/overlays/dev
```

## 🔧 よく使うコマンド

### ステータス確認
```bash
# Pod一覧
kubectl -n todo-app get pods

# ログ確認
kubectl -n todo-app logs -f deployment/todo-api

# サービス確認
kubectl -n todo-app get svc,ingress
```

### トラブルシューティング
```bash
# Podの詳細確認
kubectl -n todo-app describe pod <pod-name>

# 再起動
kubectl -n todo-app rollout restart deployment/todo-api

# Secret確認
kubectl -n todo-app get secrets
```

### ポートフォワード（ローカルテスト用）
```bash
# アプリケーションに直接アクセス
kubectl -n todo-app port-forward service/todo-api-service 8080:80

# PostgreSQLに直接アクセス
kubectl -n todo-app port-forward service/postgres 5432:5432
```

## 🔐 セキュリティ注意事項

- `.env.secret`ファイルは絶対にGitにコミットしない
- DockerHubのPATトークンは安全に管理する
- 本番環境では強力なパスワードを使用する
- Secretの管理には将来的にExternal Secrets OperatorやSealed Secretsの導入を検討

## 🏷️ タグ管理

現在はすべての環境で`latest`タグを使用していますが、本番環境では特定のバージョンタグを使用することを推奨します。

`deploy/.env`ファイルで管理：
```env
# 開発環境
IMAGE_TAG=latest

# 本番環境（推奨）
IMAGE_TAG=v1.0.0
```

環境変数を変更後、`./deploy/generate-kustomization.sh`を実行すると、すべてのkustomization.yamlが更新されます。

## 🔧 カスタマイズ

異なるDockerレジストリやユーザー名を使用する場合は、`deploy/.env`を編集：

```env
DOCKER_REGISTRY=ghcr.io        # GitHub Container Registry
DOCKER_USER=your-username      # あなたのユーザー名
APP_NAME=your-app-name         # アプリケーション名
IMAGE_TAG=v2.0.0              # バージョンタグ
```

## 📚 参考リンク

- [Kustomize Documentation](https://kustomize.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [k3s Documentation](https://docs.k3s.io/)