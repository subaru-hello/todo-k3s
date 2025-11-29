#!/bin/bash
set -e

NAMESPACE="app"

echo "======================================"
echo "Runtime Comparison Verification"
echo "======================================"
echo ""

# runc版API検証
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. runc版API検証"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
API_RUNC=$(kubectl get pod -n $NAMESPACE -l app=api -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $API_RUNC"
echo ""

echo "→ /healthz テスト:"
kubectl exec -n $NAMESPACE $API_RUNC -- curl -s http://localhost:3000/healthz | jq .
echo ""

echo "→ /test/runtime-info テスト:"
kubectl exec -n $NAMESPACE $API_RUNC -- curl -s http://localhost:3000/test/runtime-info | jq .
echo ""

echo "→ /test/exec テスト (成功するはず):"
kubectl exec -n $NAMESPACE $API_RUNC -- curl -s http://localhost:3000/test/exec | jq .
echo ""

echo "→ /test/sysinfo テスト:"
kubectl exec -n $NAMESPACE $API_RUNC -- curl -s http://localhost:3000/test/sysinfo | jq '.status, .cpuCount, .cpuModel'
echo ""

# gVisor版API検証
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. gVisor版API検証"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
API_GVISOR=$(kubectl get pod -n $NAMESPACE -o jsonpath='{.items[?(@.spec.runtimeClassName=="gvisor")].metadata.name}')
echo "Pod: $API_GVISOR"
echo ""

echo "→ /healthz テスト:"
kubectl exec -n $NAMESPACE $API_GVISOR -- curl -s http://localhost:3000/healthz | jq .
echo ""

echo "→ /test/runtime-info テスト:"
kubectl exec -n $NAMESPACE $API_GVISOR -- curl -s http://localhost:3000/test/runtime-info | jq .
echo ""

echo "→ /test/exec テスト (失敗する可能性あり):"
kubectl exec -n $NAMESPACE $API_GVISOR -- curl -s http://localhost:3000/test/exec | jq .
echo ""

echo "→ /test/sysinfo テスト (仮想化された情報):"
kubectl exec -n $NAMESPACE $API_GVISOR -- curl -s http://localhost:3000/test/sysinfo | jq '.status, .cpuCount, .cpuModel'
echo ""

# ファイルシステムパフォーマンス比較
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. ファイルシステムパフォーマンス比較"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "runc:"
kubectl exec -n $NAMESPACE $API_RUNC -- curl -s http://localhost:3000/test/filesystem | jq '.status, .durationMs'
echo ""

echo "gVisor:"
kubectl exec -n $NAMESPACE $API_GVISOR -- curl -s http://localhost:3000/test/filesystem | jq '.status, .durationMs'
echo ""

echo "======================================"
echo "検証完了"
echo "======================================"
