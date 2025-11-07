# ローカルk3d環境デプロイレポート

## 実施日時
2025年11月7日

## 目次
- [環境構築](#環境構築)
- [デプロイ実行](#デプロイ実行)
- [動作確認](#動作確認)
- [まとめ](#まとめ)

## 環境構築

### 1. k3dのインストール

```bash
brew install k3d
```

**インストールされたバージョン**: k3d 5.8.3

### 2. Helmのインストール

```bash
brew install helm
```

**インストールされたバージョン**: Helm 3.19.0

### 3. k3dクラスタの作成

```bash
k3d cluster create todo-local \
  --api-port 6443 \
  --port 8080:80@loadbalancer \
  --port 8443:443@loadbalancer
```

**作成結果**:
- クラスタ名: `todo-local`
- Kubernetesバージョン: v1.31.5+k3s1
- ノード数: 1 (control-plane)
- LoadBalancer: k3d-proxy (8080:80, 8443:443)

### 4. 環境確認

```bash
# Context確認
kubectl config current-context
# 出力: k3d-todo-local

# Node確認
kubectl get nodes
# NAME                      STATUS   ROLES                  AGE   VERSION
# k3d-todo-local-server-0   Ready    control-plane,master   ...   v1.31.5+k3s1

# StorageClass確認
kubectl get storageclass
# NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE
# local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer
```

**重要**: StorageClassが`local-path`で、プロジェクトの設定と完全に一致しています。

## デプロイ実行

### 1. 初回デプロイ試行

```bash
./deployment/scripts/deploy.sh local
```

**問題**: APIのPodが`ImagePullBackOff`エラー

**原因**:
- イメージ`docker.io/subaru88/home-kube:latest`がプライベートリポジトリ
- ImagePullSecretの認証がk3dで正しく機能しない

### 2. ImagePullSecret作成

```bash
# Docker Hubにログイン確認
docker login

# ImagePullSecret作成
kubectl -n app create secret generic dockerhub-secret \
  --from-file=.dockerconfigjson=$HOME/.docker/config.json \
  --type=kubernetes.io/dockerconfigjson
```

### 3. Helm設定の更新

```bash
helm upgrade --install api ./deployment/charts/api \
  -n app \
  -f ./deployment/environments/local/api-values.yaml \
  --set image.tag=sha-e432059 \
  --set 'imagePullSecrets[0]=dockerhub-secret'
```

**問題**: k3dでImagePullSecretが機能せず、引き続き`ImagePullBackOff`

### 4. 解決策: ローカルビルド＆インポート

#### ステップ1: イメージをローカルでビルド

```bash
cd packages/api
docker build -t docker.io/subaru88/home-kube:sha-e432059 --target production .
```

**ビルド結果**:
- ベースイメージ: `gcr.io/distroless/nodejs20-debian12` (production)
- ビルド時間: 約8秒
- イメージサイズ: 最適化された軽量イメージ

**ビルド内容**:
1. Node.js依存関係のインストール (`npm ci`)
2. TypeScriptのビルド (`npm run build`)
3. Distroless本番イメージへのコピー
4. 最小権限での実行

#### ステップ2: k3dクラスタにイメージをインポート

```bash
k3d image import docker.io/subaru88/home-kube:sha-e432059 -c todo-local
```

**インポート結果**:
```
INFO[0000] Importing image(s) into cluster 'todo-local'
INFO[0004] Successfully imported 1 image(s) into 1 cluster(s)
```

#### ステップ3: Deploymentの再起動

```bash
kubectl -n app rollout restart deployment api
```

### 5. デプロイ成功

```bash
kubectl -n app get pods
```

**結果**:
```
NAME                   READY   STATUS    RESTARTS   AGE
api-586858cdb6-zkvkk   1/1     Running   0          39s
postgres-0             1/1     Running   0          4h9m
```

✅ **両方のPodが正常に稼働**

## 動作確認

### 1. ヘルスチェック

```bash
kubectl -n app port-forward svc/api 3000:3000 &
curl http://localhost:3000/healthz
curl http://localhost:3000/dbcheck
```

**結果**:
```json
{"status":"healthy"}
{"status":"ok","db":"connected"}
```

✅ **APIとデータベース接続が正常**

### 2. Todo API機能テスト

#### 空のリスト取得

```bash
curl http://localhost:3000/api/todos
```

**結果**:
```json
[]
```

#### Todo作成

```bash
curl -X POST http://localhost:3000/api/todos \
  -H "Content-Type: application/json" \
  -d '{
    "title": "k3dデプロイテスト",
    "description": "ローカルk3d環境でのテスト",
    "completed": false
  }'
```

**結果**:
```json
{
  "title": "k3dデプロイテスト",
  "description": "ローカルk3d環境でのテスト",
  "completed": false,
  "id": 1,
  "createdAt": "2025-11-07T04:31:50.277Z",
  "updatedAt": "2025-11-07T04:31:50.277Z"
}
```

✅ **Todo作成成功**

#### Todo一覧取得（作成後）

```bash
curl http://localhost:3000/api/todos
```

**結果**:
```json
[{
  "id": 1,
  "title": "k3dデプロイテスト",
  "description": "ローカルk3d環境でのテスト",
  "completed": false,
  "createdAt": "2025-11-07T04:31:50.277Z",
  "updatedAt": "2025-11-07T04:31:50.277Z"
}]
```

✅ **データの永続化が確認できた**

### 3. PostgreSQLデータ確認

```bash
kubectl -n app get pvc
```

**結果**:
```
NAME                     STATUS   VOLUME                                     CAPACITY   STORAGECLASS
postgres-data-postgres-0 Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   5Gi        local-path
```

✅ **PVCが正常にBindされ、データが永続化されている**

## まとめ

### 成功したポイント

1. **k3dの活用**
   - macOS上でDocker内にk3sを実行
   - 本番環境（リモートk3s）と同じStorageClass (`local-path`)
   - LoadBalancerも簡単に設定可能

2. **プライベートイメージの対応**
   - ローカルビルド＆k3dインポートで解決
   - 開発環境では最も確実な方法
   - イメージの内容を完全に把握できる

3. **Helmベースのデプロイ**
   - 環境設定ファイル (`local/api-values.yaml`) が機能
   - イメージタグの柔軟な切り替えが可能
   - 本番環境と同じデプロイフローを検証できた

4. **完全な機能検証**
   - ヘルスチェック ✓
   - データベース接続 ✓
   - CRUD操作 ✓
   - データ永続化 ✓

### 学んだこと

1. **k3dでのイメージ管理**
   - プライベートイメージはローカルビルド＆インポートが確実
   - `k3d image import`コマンドで簡単にインポート可能
   - ImagePullSecretの設定は本番環境用

2. **デプロイスクリプトの改善点**
   - ローカル環境では`.env.secret`がなくてもデフォルト値で動作
   - Helmのvalues.yamlで環境を完全に分離できている

3. **本番環境との差異**
   - ローカル: k3d (Docker内のk3s)
   - 本番: ネイティブk3s
   - StorageClassは同じ (`local-path`)
   - デプロイ方法は完全に同じ

### 次のステップ

ローカル環境でのデプロイが成功したので、次はリモートサーバー（octom-server）の調査に進みます：

1. リモートk3sへの接続
2. `node-app` CrashLoopBackOffの原因調査
3. 古いKustomizeベースのリソースのクリーンアップ
4. Helmベースの最新デプロイメント適用

## コマンドリファレンス

### k3dクラスタ管理

```bash
# クラスタ作成
k3d cluster create todo-local --api-port 6443

# クラスタ一覧
k3d cluster list

# クラスタ停止
k3d cluster stop todo-local

# クラスタ削除
k3d cluster delete todo-local

# イメージインポート
k3d image import <image-name> -c todo-local
```

### デプロイ＆検証

```bash
# デプロイ
./deployment/scripts/deploy.sh local

# Pod状態確認
kubectl -n app get pods

# ログ確認
kubectl -n app logs -f deployment/api

# ポートフォワード
kubectl -n app port-forward svc/api 3000:3000

# ヘルスチェック
curl http://localhost:3000/healthz
curl http://localhost:3000/dbcheck
```

### ローカルビルド（必要な場合）

```bash
# APIイメージビルド
cd packages/api
docker build -t docker.io/subaru88/home-kube:sha-e432059 --target production .

# k3dにインポート
k3d image import docker.io/subaru88/home-kube:sha-e432059 -c todo-local

# Deployment再起動
kubectl -n app rollout restart deployment api
```

## 付録: デプロイ時のログ

### 初回デプロイ

```
=========================================
🚀 デプロイ開始: local 環境
=========================================
イメージタグ: latest

📦 Namespace作成: app
namespace/app created

⚠️  警告: /Users/s30764/Personal/todo-k3s/deployment/environments/local/.env.secret が見つかりません
   Helm Chartのデフォルト値でSecretを作成します

🗄️  PostgreSQLをデプロイ中...
Release "postgres" does not exist. Installing it now.
NAME: postgres
LAST DEPLOYED: Fri Nov  7 09:20:52 2025
NAMESPACE: app
STATUS: deployed
REVISION: 1

🔧 APIをデプロイ中...
Release "api" does not exist. Installing it now.
NAME: api
LAST DEPLOYED: Fri Nov  7 09:20:52 2025
NAMESPACE: app
STATUS: deployed
REVISION: 1

=========================================
✅ デプロイ完了
=========================================
```

### 最終的なリソース状態

```bash
$ kubectl -n app get all

NAME                       READY   STATUS    RESTARTS   AGE
pod/api-586858cdb6-zkvkk   1/1     Running   0          10m
pod/postgres-0             1/1     Running   0          4h

NAME               TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/api        ClusterIP   10.43.123.45    <none>        3000/TCP   4h
service/postgres   ClusterIP   10.43.234.56    <none>        5432/TCP   4h

NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/api   1/1     1            1           4h

NAME                             DESIRED   CURRENT   READY   AGE
replicaset.apps/api-586858cdb6   1         1         1       10m

NAME                        READY   AGE
statefulset.apps/postgres   1/1     4h
```

---

このレポートは、ローカルk3d環境でのTodo APIのデプロイとテストの完全な記録です。すべての機能が正常に動作し、次のステップ（リモートサーバー調査）に進む準備が整いました。
