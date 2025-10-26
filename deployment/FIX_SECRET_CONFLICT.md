# Secret競合エラーの修正手順

## 🔍 問題

以下のエラーが発生した場合:

```
Error: UPGRADE FAILED: Unable to continue with update: Secret "postgres-secret" in namespace "app" exists and cannot be imported into the current release: invalid ownership metadata; label validation error: missing key "app.kubernetes.io/managed-by": must be set to "Helm"
```

**原因**: `postgres-secret`が手動で作成されており、Helmが管理できない状態です。

---

## ✅ 解決方法1: deploy.shスクリプトを使う(推奨)

更新された`deploy.sh`スクリプトは自動的にこの問題を修正します。

```bash
cd ~/projects/todo-k3s/deployment
./scripts/deploy.sh local  # またはprod
```

**スクリプトの動作**:
1. 既存Secretが非Helm管理かチェック
2. 非Helm管理の場合、削除
3. `.env.secret`がある場合はそこから再作成、ない場合はHelmに任せる
4. Helmでデプロイ

---

## ✅ 解決方法2: 手動で修正

### ステップ1: 既存Secretを削除

```bash
kubectl -n app delete secret postgres-secret
```

**注意**:
- PostgreSQLのデータは削除されません(PVCは残ります)
- API Podが一時的に再起動しますが、すぐに復旧します

### ステップ2: Helmでデプロイ

#### 方法A: .env.secretを使う場合

```bash
# .env.secretファイルの作成
cd ~/projects/todo-k3s/deployment/environments/local  # または prod
cat > .env.secret <<EOF
POSTGRES_USER=appuser
POSTGRES_PASSWORD=your-strong-password
POSTGRES_DB=todos
JWT_SECRET=your-jwt-secret
EOF

# Secretを作成
kubectl create secret generic postgres-secret \
  --from-env-file=.env.secret \
  --namespace=app

# Helmでデプロイ(createSecret=falseで競合を防ぐ)
cd ~/projects/todo-k3s
helm upgrade --install postgres ./deployment/charts/postgres \
  -n app \
  -f ./deployment/environments/local/postgres-values.yaml \
  --set createSecret=false
```

#### 方法B: Helmに全て任せる場合

```bash
# values.yamlのデフォルト値でSecretを作成
helm upgrade --install postgres ./deployment/charts/postgres \
  -n app \
  -f ./deployment/environments/local/postgres-values.yaml \
  --set createSecret=true
```

**この場合のSecret内容**:
- POSTGRES_USER: `appuser`
- POSTGRES_PASSWORD: `change-me-strong`
- POSTGRES_DB: `todos`

---

## 🔍 現在の状態を確認

### Secretが存在するか確認

```bash
kubectl -n app get secret postgres-secret
```

### SecretがHelm管理かどうか確認

```bash
kubectl -n app get secret postgres-secret -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}'
```

**出力**:
- `Helm` → Helm管理されている(OK)
- 空または他の値 → Helm管理されていない(要修正)

### Secret内容を確認

```bash
kubectl -n app get secret postgres-secret -o jsonpath='{.data.POSTGRES_USER}' | base64 -d
echo
kubectl -n app get secret postgres-secret -o jsonpath='{.data.POSTGRES_DB}' | base64 -d
echo
```

---

## 📝 完全なクリーンインストール手順

もし全てをリセットしたい場合:

```bash
# 1. 既存リソースを全削除
helm uninstall api -n app 2>/dev/null || true
helm uninstall postgres -n app 2>/dev/null || true
kubectl -n app delete secret postgres-secret 2>/dev/null || true

# 2. データも削除する場合(注意!)
kubectl -n app delete pvc --all

# 3. deploy.shでクリーンインストール
cd ~/projects/todo-k3s/deployment
./scripts/deploy.sh local
```

---

## 🚨 トラブルシューティング

### API Podが起動しない

Secretを削除した直後は、API Podが一時的にCrashLoopBackOffになる可能性があります。

```bash
# Secretが正しく作成されたか確認
kubectl -n app get secret postgres-secret

# API Podを強制的に再起動
kubectl -n app rollout restart deployment/api

# Pod状態を監視
kubectl -n app get pods -w
```

### PostgreSQLが接続できない

```bash
# PostgreSQL Podの状態確認
kubectl -n app get pod -l app=postgres

# PostgreSQLのログ確認
kubectl -n app logs -l app=postgres --tail=50

# PostgreSQLに直接接続してテスト
kubectl -n app exec -it deployment/postgres -- psql -U appuser -d todos -c "SELECT NOW();"
```

---

## 📚 参考資料

- Helm管理リソースのラベル: https://helm.sh/docs/chart_best_practices/labels/
- Kubernetes Secrets: https://kubernetes.io/docs/concepts/configuration/secret/
