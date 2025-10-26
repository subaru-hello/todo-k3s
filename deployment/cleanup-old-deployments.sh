#!/bin/bash

# 古いデプロイメントを削除するスクリプト
# 自宅サーバーで実行してください

set -e

echo "🧹 古いデプロイメントをクリーンアップします..."
echo ""

# node-appの削除
echo "1️⃣ node-app を削除中..."
if kubectl get deployment node-app 2>/dev/null; then
  kubectl delete deployment node-app
  echo "✅ node-app デプロイメントを削除しました"
else
  echo "⏭️  node-app デプロイメントは存在しません"
fi

# go-echoの削除
echo ""
echo "2️⃣ go-echo を削除中..."
if kubectl get deployment go-echo 2>/dev/null; then
  kubectl delete deployment go-echo
  echo "✅ go-echo デプロイメントを削除しました"
else
  echo "⏭️  go-echo デプロイメントは存在しません"
fi

# 重複しているcloudflared-cloudflare-tunnelの削除
echo ""
echo "3️⃣ 重複している cloudflared-cloudflare-tunnel を削除中..."
if kubectl get deployment cloudflared-cloudflare-tunnel 2>/dev/null; then
  kubectl delete deployment cloudflared-cloudflare-tunnel
  echo "✅ cloudflared-cloudflare-tunnel デプロイメントを削除しました"
else
  echo "⏭️  cloudflared-cloudflare-tunnel デプロイメントは存在しません"
fi

echo ""
echo "✨ クリーンアップが完了しました!"
echo ""
echo "📊 現在のデプロイメント一覧:"
kubectl get deployments

echo ""
echo "🎯 次のステップ:"
echo "   1. Helm Chartを使って新しいデプロイメントを作成してください"
echo "   2. deployment/README.md を参照してください"
