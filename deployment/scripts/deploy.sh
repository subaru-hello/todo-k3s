#!/bin/bash
set -e

# 使い方を表示
usage() {
  echo "使い方: $0 {local|prod} [image-tag]"
  echo ""
  echo "引数:"
  echo "  環境      : local または prod"
  echo "  image-tag : APIイメージのタグ（省略時: latest for local, v1.0.0 for prod）"
  echo ""
  echo "例:"
  echo "  $0 local"
  echo "  $0 local latest"
  echo "  $0 prod v1.0.1"
  exit 1
}

# 引数チェック
if [ $# -lt 1 ]; then
  usage
fi

ENV=$1
IMAGE_TAG=${2:-}

# 環境チェック
if [ "$ENV" != "local" ] && [ "$ENV" != "prod" ]; then
  echo "エラー: 環境は 'local' または 'prod' を指定してください"
  usage
fi

# デフォルトのイメージタグ
if [ -z "$IMAGE_TAG" ]; then
  if [ "$ENV" = "local" ]; then
    IMAGE_TAG="latest"
  else
    IMAGE_TAG="v1.0.0"
  fi
fi

# リポジトリルートに移動
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

echo "========================================="
echo "🚀 デプロイ開始: $ENV 環境"
echo "========================================="
echo "イメージタグ: $IMAGE_TAG"
echo ""

# 本番環境の場合のみイメージをpull
if [ "$ENV" = "prod" ]; then
  # Note: 環境変数で上書き可能
  IMAGE_REGISTRY="${IMAGE_REGISTRY:-docker.io}"
  IMAGE_NAME="${IMAGE_NAME:-subaru88/home-kube}"
  IMAGE="$IMAGE_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
  echo "📦 イメージをpull中: $IMAGE"

  if command -v nerdctl &> /dev/null; then
    sudo nerdctl -n k8s.io pull "$IMAGE"
  elif command -v docker &> /dev/null; then
    docker pull "$IMAGE"
  else
    echo "警告: nerdctl または docker が見つかりません。イメージのpullをスキップします。"
  fi
  echo ""
fi

# Namespaceの作成
echo "📦 Namespace作成: app"
kubectl create namespace app 2>/dev/null || echo "Namespace 'app' は既に存在します"
echo ""

# PostgreSQLのデプロイ
echo "🗄️  PostgreSQLをデプロイ中..."
helm upgrade --install postgres ./deployment/charts/postgres \
  -n app \
  -f ./deployment/environments/$ENV/postgres-values.yaml

echo ""

# APIのデプロイ
echo "🔧 APIをデプロイ中..."
helm upgrade --install api ./deployment/charts/api \
  -n app \
  -f ./deployment/environments/$ENV/api-values.yaml \
  --set image.tag=$IMAGE_TAG

echo ""

# 本番環境の場合のみCloudflare Tunnelをデプロイ
if [ "$ENV" = "prod" ]; then
  echo "🌐 Cloudflare Tunnelをデプロイ中..."

  # Secretの存在確認
  if kubectl -n app get secret cloudflared-secret &>/dev/null; then
    kubectl apply -f ./deployment/cloudflare-tunnel/deployment-prod.yaml
    echo "Cloudflare Tunnel Podをデプロイしました"
  else
    echo "警告: cloudflared-secret が見つかりません"
    echo "deployment/cloudflare-tunnel/README.md を参照してSecretを作成してください"
  fi
  echo ""
fi

echo "========================================="
echo "✅ デプロイ完了"
echo "========================================="
echo ""

# Pod状態の確認
echo "📊 Pod状態:"
kubectl -n app get pods
echo ""

# ローカル環境の場合、port-forward手順を表示
if [ "$ENV" = "local" ]; then
  echo "========================================="
  echo "📝 ローカルアクセス手順"
  echo "========================================="
  echo "以下のコマンドでAPIにアクセスできます:"
  echo ""
  echo "  kubectl -n app port-forward svc/api 3000:3000"
  echo ""
  echo "その後、以下でテスト:"
  echo "  curl http://localhost:3000/healthz"
  echo "  curl http://localhost:3000/dbcheck"
  echo "  curl http://localhost:3000/api/todos"
  echo ""
fi

# 本番環境の場合、外部アクセス手順を表示
if [ "$ENV" = "prod" ]; then
  echo "========================================="
  echo "🌍 本番環境アクセス"
  echo "========================================="
  echo "Cloudflare Tunnelが正しく設定されていれば、以下でアクセスできます:"
  echo ""
  echo "  curl https://api.octomblog.com/healthz"
  echo "  curl https://api.octomblog.com/dbcheck"
  echo ""
fi
