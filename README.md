# Todo API for k3s

TypeScriptで実装したTodo APIをk3sクラスタにデプロイするためのプロジェクトです。

## プロジェクト構成

```
todo-k3s/
├── app/                     # Node.js TypeScript API
│   ├── src/                # ソースコード
│   ├── Dockerfile          # Dockerイメージビルド設定
│   └── package.json        # Node.js依存関係
└── deploy/                 # Kubernetes マニフェスト (Kustomize)
    ├── base/              # 共通設定
    └── overlays/          # 環境別設定
        ├── dev/           # 開発環境
        └── prod/          # 本番環境
```

## API仕様

### エンドポイント

- `GET /healthz` - ヘルスチェック
- `GET /api/todos` - Todo一覧取得
- `GET /api/todos/:id` - Todo詳細取得
- `POST /api/todos` - Todo作成
- `PUT /api/todos/:id` - Todo更新
- `DELETE /api/todos/:id` - Todo削除

### データモデル

```json
{
  "id": 1,
  "title": "タスクのタイトル",
  "description": "タスクの説明",
  "completed": false,
  "createdAt": "2024-01-01T00:00:00.000Z",
  "updatedAt": "2024-01-01T00:00:00.000Z"
}
```

## セットアップ手順

### 1. 開発環境での動作確認

```bash
cd app
npm install
npm run dev
```

### 2. Dockerイメージのビルド

```bash
cd app
docker build -t todo-api:latest .
```

### 3. プライベートレジストリへのプッシュ

```bash
# タグ付け
docker tag todo-api:latest <your-registry>/todo-api:v1.0.0

# ログイン
docker login <your-registry>

# プッシュ
docker push <your-registry>/todo-api:v1.0.0
```

## k3sへのデプロイ

### 前提条件

- k3sクラスタがセットアップ済み
- kubectlがインストール済み
- k3sクラスタへのアクセス設定済み

### プライベートレジストリの認証設定

プライベートレジストリを使用する場合、pull secretを作成します：

```bash
kubectl create namespace todo-app

kubectl -n todo-app create secret docker-registry regcred \
  --docker-server=<your-registry> \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email>
```

### イメージPullSecret設定の追加

`deploy/base/app-deployment.yaml`に以下を追加：

```yaml
spec:
  template:
    spec:
      imagePullSecrets:
      - name: regcred
      containers:
      ...
```

### デプロイ実行

#### 開発環境へのデプロイ

1. overlaysの設定を調整

```bash
# deploy/overlays/dev/kustomization.yaml を編集
# newName: <your-registry>/home-kube
# newTag: <your-tag>
```

2. デプロイ実行

```bash
# リポジトリをクローン
git clone <repository-url>
cd todo-k3s

# 開発環境にデプロイ
kubectl apply -k deploy/overlays/dev

# 状態確認
kubectl -n todo-app get all
kubectl -n todo-app get ingress
```

#### 本番環境へのデプロイ

```bash
# overlays/prod/kustomization.yaml を編集して本番用の設定に変更

# デプロイ
kubectl apply -k deploy/overlays/prod

# 状態確認
kubectl -n todo-app rollout status deployment/todo-api
kubectl -n todo-app rollout status deployment/postgres
```

### 動作確認

```bash
# ポートフォワード（ローカルテスト用）
kubectl -n todo-app port-forward service/todo-api-service 8080:80

# APIテスト
curl http://localhost:8080/healthz
curl http://localhost:8080/api/todos

# Todo作成
curl -X POST http://localhost:8080/api/todos \
  -H "Content-Type: application/json" \
  -d '{"title":"テストタスク","description":"これはテストです"}'
```

### Ingressでアクセスする場合

```bash
# hostsファイルに追加
echo "<k3s-node-ip> todo-dev.local" | sudo tee -a /etc/hosts

# アクセス
curl http://todo-dev.local/api/todos
```

## トラブルシューティング

### Podが起動しない場合

```bash
# Pod詳細確認
kubectl -n todo-app describe pod <pod-name>

# ログ確認
kubectl -n todo-app logs <pod-name>
```

### データベース接続エラー

```bash
# PostgreSQLの状態確認
kubectl -n todo-app get pod -l app=postgres
kubectl -n todo-app logs -l app=postgres

# Secret確認
kubectl -n todo-app get secret postgres-secret -o yaml
```

### イメージPullエラー

```bash
# Pull Secret確認
kubectl -n todo-app get secret regcred

# イベント確認
kubectl -n todo-app get events --sort-by='.lastTimestamp'
```

## アップデート手順

1. 新しいイメージをビルド・プッシュ
2. overlaysのkustomization.yamlでnewTagを更新
3. `kubectl apply -k deploy/overlays/<env>`で適用
4. `kubectl -n todo-app rollout status deployment/todo-api`で確認

## クリーンアップ

```bash
# 開発環境の削除
kubectl delete -k deploy/overlays/dev

# Namespace全体を削除
kubectl delete namespace todo-app
```