# ローカル環境（minikube）デプロイガイド

このドキュメントでは、minikube環境でTodo APIをデプロイする手順を解説します。

## 目次
- [前提条件](#前提条件)
- [環境確認](#環境確認)
- [イメージの準備](#イメージの準備)
- [デプロイ手順](#デプロイ手順)
- [動作確認](#動作確認)
- [トラブルシューティング](#トラブルシューティング)
- [クリーンアップ](#クリーンアップ)

## 前提条件

### 必要なツール

- **minikube**: ローカルKubernetesクラスタ
- **kubectl**: Kubernetesコマンドラインツール
- **Docker**: コンテナイメージのビルド（オプション）
- **Helm**: Kubernetesパッケージマネージャー（デプロイスクリプト内で使用）

### インストール（macOS）

```bash
# minikubeのインストール
brew install minikube

# kubectlのインストール（minikubeに含まれる）
brew install kubectl

# Helmのインストール
brew install helm
```

### minikubeの起動

```bash
# minikubeを起動
minikube start

# 起動確認
minikube status
# 出力例:
# minikube
# type: Control Plane
# host: Running
# kubelet: Running
# apiserver: Running
# kubeconfig: Configured

# kubectl contextの確認
kubectl config current-context
# 出力: minikube
```

## 環境確認

### 1. minikubeの状態確認

```bash
# minikubeの起動状態
minikube status

# Kubernetesバージョン
kubectl version --short

# Node情報
kubectl get nodes
```

### 2. kubectl contextの確認

```bash
# 現在のcontext（minikubeを指しているか）
kubectl config current-context

# 利用可能なcontext一覧
kubectl config get-contexts
```

### 3. StorageClassの確認

```bash
# 利用可能なStorageClass
kubectl get storageclass

# 出力例:
# NAME                 PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE
# standard (default)   k8s.io/minikube-hostpath   Delete          Immediate
```

**注意**: minikubeでは`standard`がデフォルトですが、本プロジェクトの設定では`local-path`を指定している場合があります。必要に応じて設定を調整します。

## イメージの準備

Todo APIを稼働させるには、コンテナイメージが必要です。以下の2つの方法があります。

### 方法A: Docker Hubから取得（推奨）

最も簡単な方法です。インターネット接続があれば、デプロイ時に自動的にイメージが取得されます。

```bash
# イメージの存在確認（オプション）
docker pull docker.io/subaru88/home-kube:latest

# minikubeで使用する場合
minikube image pull docker.io/subaru88/home-kube:latest
```

**メリット**:
- 事前の準備不要
- CI/CDでビルドされた本番品質イメージを使用

**デメリット**:
- インターネット接続が必要
- イメージの内容を確認できない

### 方法B: ローカルでビルド＆ロード

ローカルでコードを変更してテストする場合や、オフライン開発に適しています。

#### ステップ1: Dockerイメージのビルド

```bash
cd /Users/s30764/Personal/todo-k3s/packages/api

# 開発用イメージをビルド（シェルありでデバッグ可能）
docker build -t docker.io/subaru88/home-kube:latest --target development .
```

**ビルドオプション**:
- `--target development`: 開発用（Node.js Alpine、シェルあり）
- `--target production`: 本番用（Distroless、シェルなし）

#### ステップ2: minikubeへイメージロード

```bash
# minikubeの内部Dockerにイメージをロード
minikube image load docker.io/subaru88/home-kube:latest

# ロード確認
minikube image ls | grep home-kube
```

**別の方法: minikubeのDockerデーモンを使用**

```bash
# minikubeのDockerデーモンを使用する設定
eval $(minikube docker-env)

# この状態でビルドすると、minikube内に直接イメージが作成される
cd /Users/s30764/Personal/todo-k3s/packages/api
docker build -t docker.io/subaru88/home-kube:latest --target development .

# 元のDockerデーモンに戻す
eval $(minikube docker-env -u)
```

## デプロイ手順

### 1. プロジェクトディレクトリに移動

```bash
cd /Users/s30764/Personal/todo-k3s
```

### 2. 環境設定の確認（オプション）

デフォルトの設定をカスタマイズする場合：

```bash
# ローカル環境の設定ファイル
cat deployment/environments/local/api-values.yaml
cat deployment/environments/local/postgres-values.yaml
```

**主な設定項目**:
- `replicaCount`: Pod数（デフォルト: 1）
- `image.tag`: イメージタグ（デフォルト: latest）
- `postgres.auth`: データベース認証情報

### 3. デプロイスクリプト実行

```bash
# ローカル環境にデプロイ
./deployment/scripts/deploy.sh local

# 特定のイメージタグを指定する場合
./deployment/scripts/deploy.sh local sha-abc1234
```

### 4. デプロイプロセスの確認

スクリプトは以下の処理を自動実行します：

1. **Namespace作成**: `app` namespace
2. **Secret作成**: PostgreSQL認証情報（`.env.secret`がある場合）
3. **PostgreSQLデプロイ**: StatefulSet + Service + PVC
4. **APIデプロイ**: Deployment + Service
5. **アクセス方法表示**: port-forward手順

**出力例**:
```
Creating namespace...
namespace/app created

Deploying PostgreSQL...
Release "postgres" does not exist. Installing it now.
NAME: postgres
LAST DEPLOYED: ...
STATUS: deployed

Deploying API...
Release "api" does not exist. Installing it now.
NAME: api
LAST DEPLOYED: ...
STATUS: deployed

Deployment completed!

To access the API:
  kubectl -n app port-forward svc/api 3000:3000
  curl http://localhost:3000/healthz
```

### 5. デプロイ状態の確認

```bash
# Pod状態確認
kubectl -n app get pods

# 期待される出力:
# NAME           READY   STATUS    RESTARTS   AGE
# api-xxx        1/1     Running   0          30s
# postgres-0     1/1     Running   0          45s

# Service確認
kubectl -n app get svc

# PVC確認（PostgreSQLの永続化ボリューム）
kubectl -n app get pvc
```

### 6. Pod起動の詳細確認

Podが起動しない場合は、詳細を確認：

```bash
# Pod詳細情報
kubectl -n app describe pod api-xxx

# ログ確認
kubectl -n app logs api-xxx
kubectl -n app logs postgres-0

# リアルタイムでログ監視
kubectl -n app logs -f api-xxx
```

## 動作確認

### 1. Port Forwardでアクセス

```bash
# APIサービスへのポートフォワード
kubectl -n app port-forward svc/api 3000:3000
```

### 2. ヘルスチェック

別のターミナルで以下を実行：

```bash
# サービスヘルスチェック
curl http://localhost:3000/healthz
# 出力: {"status":"healthy"}

# データベース接続確認
curl http://localhost:3000/dbcheck
# 出力: {"status":"ok","message":"Database connection successful"}
```

### 3. Todo API動作確認

#### Todo一覧取得（空のリスト）

```bash
curl http://localhost:3000/api/todos
# 出力: []
```

#### Todo作成

```bash
curl -X POST http://localhost:3000/api/todos \
  -H "Content-Type: application/json" \
  -d '{
    "title": "minikubeテスト",
    "description": "ローカル環境でのテスト",
    "completed": false
  }'

# 出力:
# {
#   "id": 1,
#   "title": "minikubeテスト",
#   "description": "ローカル環境でのテスト",
#   "completed": false,
#   "createdAt": "2025-10-08T...",
#   "updatedAt": "2025-10-08T..."
# }
```

#### Todo一覧取得（作成後）

```bash
curl http://localhost:3000/api/todos
# 出力: [{"id":1,"title":"minikubeテスト",...}]
```

#### Todo更新

```bash
curl -X PUT http://localhost:3000/api/todos/1 \
  -H "Content-Type: application/json" \
  -d '{
    "title": "minikubeテスト",
    "description": "更新済み",
    "completed": true
  }'
```

#### Todo削除

```bash
curl -X DELETE http://localhost:3000/api/todos/1
```

## トラブルシューティング

### ImagePullBackOff エラー

**症状**: Podが`ImagePullBackOff`状態で起動しない

```bash
kubectl -n app describe pod api-xxx
# Events:
#   Failed to pull image "docker.io/subaru88/home-kube:latest": ...
```

**原因**: イメージが見つからない

**解決策**:

```bash
# 方法1: Docker Hubから取得できるか確認
docker pull docker.io/subaru88/home-kube:latest

# 方法2: ローカルでビルド＆ロード
cd /Users/s30764/Personal/todo-k3s/packages/api
docker build -t docker.io/subaru88/home-kube:latest --target development .
minikube image load docker.io/subaru88/home-kube:latest

# 再デプロイ
kubectl -n app rollout restart deployment api
```

### CrashLoopBackOff エラー

**症状**: Podが起動しても即座にクラッシュする

```bash
kubectl -n app get pods
# NAME       READY   STATUS             RESTARTS   AGE
# api-xxx    0/1     CrashLoopBackOff   5          3m
```

**原因**: アプリケーションエラー（PostgreSQL接続失敗など）

**解決策**:

```bash
# ログ確認
kubectl -n app logs api-xxx

# PostgreSQL起動確認
kubectl -n app get pods postgres-0

# PostgreSQLログ確認
kubectl -n app logs postgres-0

# Secret確認（認証情報が正しいか）
kubectl -n app get secret postgres-secret -o yaml

# 環境変数確認
kubectl -n app describe pod api-xxx | grep -A 20 "Environment:"
```

### PostgreSQL接続エラー

**症状**: `/dbcheck`が失敗する

```bash
curl http://localhost:3000/dbcheck
# エラーレスポンス
```

**解決策**:

```bash
# Pod内からPostgreSQLに接続確認
kubectl -n app exec -it api-xxx -- sh
nc -zv postgres.app.svc.cluster.local 5432

# PostgreSQL Service確認
kubectl -n app get svc postgres
kubectl -n app describe svc postgres

# PostgreSQL Pod状態確認
kubectl -n app logs postgres-0 | tail -20
```

### StorageClass not found エラー

**症状**: PVCが`Pending`状態

```bash
kubectl -n app get pvc
# NAME              STATUS    VOLUME   CAPACITY   STORAGECLASS
# postgres-data-0   Pending                       local-path
```

**原因**: 指定したStorageClassが存在しない

**解決策**:

```bash
# 利用可能なStorageClass確認
kubectl get storageclass

# minikubeのデフォルトを使用する場合
# postgres-values.yamlを編集（一時的）
kubectl -n app delete pvc postgres-data-postgres-0

# 再デプロイ時にStorageClassをオーバーライド
helm upgrade --install postgres ./deployment/charts/postgres \
  -n app \
  -f ./deployment/environments/local/postgres-values.yaml \
  --set persistence.storageClassName=standard
```

## クリーンアップ

### 部分的な削除

```bash
# APIのみ削除
helm -n app uninstall api

# PostgreSQLのみ削除（データは保持）
helm -n app uninstall postgres
```

### 完全な削除

```bash
# すべてのHelmリリースを削除
helm -n app uninstall api
helm -n app uninstall postgres

# PVCを削除（データも削除される）
kubectl -n app delete pvc --all

# Namespaceごと削除
kubectl delete namespace app
```

### minikubeの停止・削除

```bash
# minikube停止（データは保持）
minikube stop

# minikube削除（完全にクリーンな状態に）
minikube delete

# 再起動
minikube start
```

## Tips

### 1. minikube dashboard

GUIでリソースを確認：

```bash
minikube dashboard
```

ブラウザで以下が確認できます：
- Pod状態
- ログ
- リソース使用率
- イベント

### 2. 複数環境の管理

```bash
# 別のkubectl contextを使用
kubectl config use-context minikube  # ローカル
kubectl config use-context production  # リモート

# 現在のcontextを常に表示
kubectl config current-context
```

### 3. イメージの自動リロード

コード変更後、自動的にminikubeに反映：

```bash
# minikubeのDockerを使用
eval $(minikube docker-env)

# ビルド
cd /Users/s30764/Personal/todo-k3s/packages/api
docker build -t docker.io/subaru88/home-kube:latest --target development .

# Podを再起動（イメージ再Pull）
kubectl -n app rollout restart deployment api

# 元に戻す
eval $(minikube docker-env -u)
```

### 4. 開発フロー

```bash
# 1. コード変更
vim packages/api/src/index.ts

# 2. イメージビルド（minikube Docker環境）
eval $(minikube docker-env)
cd packages/api
docker build -t docker.io/subaru88/home-kube:latest --target development .

# 3. 再デプロイ
kubectl -n app rollout restart deployment api

# 4. ログ確認
kubectl -n app logs -f deployment/api

# 5. テスト
kubectl -n app port-forward svc/api 3000:3000
curl http://localhost:3000/healthz
```

## まとめ

### デプロイの最短手順

```bash
# 1. minikube起動確認
minikube status

# 2. デプロイ
cd /Users/s30764/Personal/todo-k3s
./deployment/scripts/deploy.sh local

# 3. 状態確認
kubectl -n app get pods

# 4. アクセス
kubectl -n app port-forward svc/api 3000:3000

# 5. テスト（別ターミナル）
curl http://localhost:3000/healthz
curl http://localhost:3000/api/todos
```

### 次のステップ

ローカル環境でのデプロイが成功したら：

1. **リモートサーバーの調査**: [07-remote-server-investigation.md](07-remote-server-investigation.md)
2. **本番環境へのデプロイ**: 同じ手順で`./deployment/scripts/deploy.sh prod sha-xxx`

ローカル環境は、本番環境へのデプロイ前のテストに最適です。問題があればローカルで解決してから本番に適用しましょう。
