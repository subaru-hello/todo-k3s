# デプロイメントコマンド履歴

このドキュメントは、k3sのインストールからデプロイまでに実際に実行したコマンドと実行結果をまとめたものです。

## 目次
- [ローカル環境（k3d）](#ローカル環境k3d)
- [リモート環境（k3s）](#リモート環境k3s)

---

## ローカル環境（k3d）

### 1. 環境構築

#### k3dのインストール

```bash
brew install k3d
```

**インストール結果**:
- k3d バージョン: 5.8.3

#### Helmのインストール

```bash
brew install helm
```

**インストール結果**:
- Helm バージョン: 3.19.0

#### k3dクラスタの作成

```bash
k3d cluster create todo-local \
  --api-port 6443 \
  --port 8080:80@loadbalancer \
  --port 8443:443@loadbalancer
```

**作成結果**:
```
INFO[0000] Prep: Network
INFO[0000] Created network 'k3d-todo-local'
INFO[0000] Created image volume k3d-todo-local-images
INFO[0000] Creating node 'k3d-todo-local-server-0'
INFO[0009] Pulling image 'ghcr.io/k3d-io/k3d-tools:5.8.3'
INFO[0011] Pulling image 'docker.io/rancher/k3s:v1.31.5-k3s1'
INFO[0023] Starting Node 'k3d-todo-local-server-0'
INFO[0028] Creating LoadBalancer 'k3d-todo-local-serverlb'
INFO[0030] Cluster 'todo-local' created successfully!
```

**クラスタ情報**:
- クラスタ名: `todo-local`
- Kubernetesバージョン: v1.31.5+k3s1
- ノード数: 1 (control-plane)
- LoadBalancer: k3d-proxy (8080:80, 8443:443)

### 2. 環境確認

#### Context確認

```bash
kubectl config current-context
```

**出力**:
```
k3d-todo-local
```

#### Node確認

```bash
kubectl get nodes
```

**出力**:
```
NAME                      STATUS   ROLES                  AGE   VERSION
k3d-todo-local-server-0   Ready    control-plane,master   1m    v1.31.5+k3s1
```

#### StorageClass確認

```bash
kubectl get storageclass
```

**出力**:
```
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  1m
```

### 3. イメージの準備

#### Dockerイメージのビルド

```bash
cd packages/api
docker build -t docker.io/subaru88/home-kube:sha-e432059 --target production .
```

**ビルド結果**:
```
[+] Building 8.5s (15/15) FINISHED
 => [internal] load build definition from Dockerfile
 => => transferring dockerfile: 1.23kB
 => [internal] load .dockerignore
 => => transferring context: 2B
 => [internal] load metadata for gcr.io/distroless/nodejs20-debian12:latest
 => [internal] load metadata for docker.io/library/node:24-alpine
 => [builder 1/6] FROM docker.io/library/node:24-alpine
 => [stage-2 1/3] FROM gcr.io/distroless/nodejs20-debian12
 => [builder 2/6] WORKDIR /app
 => [builder 3/6] RUN npm install -g pnpm
 => [builder 4/6] COPY package.json pnpm-lock.yaml ./
 => [builder 5/6] RUN pnpm install --frozen-lockfile
 => [builder 6/6] RUN pnpm build
 => [stage-2 2/3] COPY --from=builder /app/dist /app/dist
 => [stage-2 3/3] COPY --from=builder /app/node_modules /app/node_modules
 => exporting to image
 => => exporting layers
 => => writing image sha256:...
 => => naming to docker.io/subaru88/home-kube:sha-e432059
```

**イメージ情報**:
- ベースイメージ: `gcr.io/distroless/nodejs20-debian12` (production)
- ビルド時間: 約8秒

#### k3dクラスタへイメージインポート

```bash
k3d image import docker.io/subaru88/home-kube:sha-e432059 -c todo-local
```

**インポート結果**:
```
INFO[0000] Importing image(s) into cluster 'todo-local'
INFO[0004] Successfully imported 1 image(s) into 1 cluster(s)
```

### 4. 初回デプロイ試行

#### デプロイスクリプト実行

```bash
./deployment/scripts/deploy.sh local
```

**デプロイ結果**:
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

**初回デプロイの問題**: APIのPodが`ImagePullBackOff`エラー

### 5. ImagePullSecretの作成（試行）

```bash
# Docker Hubにログイン確認
docker login

# ImagePullSecret作成
kubectl -n app create secret generic dockerhub-secret \
  --from-file=.dockerconfigjson=$HOME/.docker/config.json \
  --type=kubernetes.io/dockerconfigjson
```

**結果**: k3dでImagePullSecretが機能せず

### 6. イメージのインポート（解決策）

前述の「k3dクラスタへイメージインポート」を実行後、Deploymentを再起動：

```bash
kubectl -n app rollout restart deployment api
```

### 7. デプロイ成功確認

#### Pod状態確認

```bash
kubectl -n app get pods
```

**出力**:
```
NAME                   READY   STATUS    RESTARTS   AGE
api-586858cdb6-zkvkk   1/1     Running   0          39s
postgres-0             1/1     Running   0          4h9m
```

✅ **両方のPodが正常に稼働**

### 8. 動作確認

#### ヘルスチェック

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

#### Todo一覧取得（空）

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

#### PVC確認

```bash
kubectl -n app get pvc
```

**出力**:
```
NAME                     STATUS   VOLUME                                     CAPACITY   STORAGECLASS
postgres-data-postgres-0 Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   5Gi        local-path
```

✅ **PVCが正常にBindされ、データが永続化されている**

---

## リモート環境（k3s）

### 1. 初期状況確認

#### リモートサーバー情報

- **ホスト**: octom-server (ssh.octomblog.com経由でアクセス)
- **接続方法**: Cloudflare Tunnel経由のSSH
- **Kubernetes**: k3s v1.31.5+k3s1

#### SSH接続

```bash
ssh octom@ssh.octomblog.com
```

#### Pod状態確認

```bash
kubectl get pods -A
```

**初期状態**:
```
NAMESPACE     NAME                                             READY   STATUS             RESTARTS
default       node-app-b5dcdcf8f-hzvn5                         0/1     CrashLoopBackOff   4718
default       go-echo-86bb755986-lswvt                         0/1     CrashLoopBackOff   9622
default       cloudflared-cloudflare-tunnel-5d7fcf4f67-fgdzb   0/1     CrashLoopBackOff   9718
default       cloudflared-cloudflare-tunnel-5d7fcf4f67-qnwrt   0/1     CrashLoopBackOff   9719
app           cloudflared-6c88894cc9-fq2cz                     1/1     Running          0
todo-app      postgres-5b689f85f9-4bx5r                        1/1     Running          1 (29d ago)
todo-app      todo-api-5b7bdf4dc4-rr6mh                        1/1     Running          1 (29d ago)
```

### 2. 問題調査

#### node-app Pod詳細確認

```bash
kubectl -n default describe pod node-app-b5dcdcf8f-hzvn5
```

**重要な発見**:
- **イメージ**: `docker.io/library/node:24-alpine` （単なるNode.jsベースイメージ）
- **Exit Code**: 0（正常終了）
- **ログ**: 空
- **原因**: アプリケーションコードが含まれていない

#### 既存todo-appの動作確認

```bash
kubectl -n todo-app exec -it todo-api-5b7bdf4dc4-rr6mh -- sh -c "wget -qO- http://localhost:3000/healthz && echo"
```

**結果**:
```json
{"status":"healthy"}
```

```bash
kubectl -n todo-app exec -it todo-api-5b7bdf4dc4-rr6mh -- sh -c "wget -qO- http://localhost:3000/api/todos && echo"
```

**結果**:
```json
[{"id":1,"title":"first task","description":null,"completed":false,"createdAt":"2025-09-15T03:30:35.176Z","updatedAt":"2025-09-15T03:30:35.176Z"}]
```

✅ **既存のAPIは正常に動作**

### 3. クリーンアップ作業

#### 不要なDeploymentの削除

```bash
# node-app削除
kubectl -n default delete deployment node-app
```

**出力**:
```
deployment.apps "node-app" deleted
```

```bash
# go-echo削除
kubectl -n default delete deployment go-echo
```

**出力**:
```
deployment.apps "go-echo" deleted
```

```bash
# cloudflared-cloudflare-tunnel削除
kubectl -n default delete deployment cloudflared-cloudflare-tunnel
```

**出力**:
```
deployment.apps "cloudflared-cloudflare-tunnel" deleted
```

#### クリーンアップ後の状態確認

```bash
kubectl get pods -n default
```

**出力**:
```
NAME                           READY   STATUS    RESTARTS      AGE
cloudflared-6bfd89b687-pmt4c   1/1     Running   4 (29d ago)   34d
hello-84bf6f98f5-d2fl8         1/1     Running   1 (29d ago)   34d
postgres-67865ff6cc-2hqgm      1/1     Running   1 (29d ago)   55d
```

✅ **CrashLoopBackOffのPodが全て削除された**

### 4. ImagePullSecretの作成

```bash
kubectl create secret docker-registry dockerhub-secret \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=subaru88 \
  --docker-password=$PASSWORD \
  -n todo-app
```

**確認**:
```bash
kubectl -n todo-app get secret dockerhub-secret
```

**出力**:
```
NAME               TYPE                             DATA   AGE
dockerhub-secret   kubernetes.io/dockerconfigjson   1      18s
```

✅ **ImagePullSecret作成成功**

### 5. 初回デプロイ試行（失敗）

```bash
kubectl -n todo-app patch deployment todo-api -p '
{
  "spec": {
    "template": {
      "spec": {
        "imagePullSecrets": [{"name": "dockerhub-secret"}],
        "containers": [{
          "name": "todo-api",
          "image": "docker.io/subaru88/home-kube:sha-e432059"
        }]
      }
    }
  }
}'
```

**結果**: `CrashLoopBackOff`

#### エラーログ確認

```bash
kubectl -n todo-app logs todo-api-7b674f64f4-xxxxx
```

**エラー内容**:
```
Error connecting to database: AggregateError [ECONNREFUSED]:
    at internalConnectMultiple (node:net:1122:18)
  code: 'ECONNREFUSED',
  address: '127.0.0.1',
  port: 5432
```

**原因**: 環境変数の不一致（DB_* vs PG*）

### 6. 環境変数の調査

#### 古いPod（動作中）の環境変数

```bash
kubectl -n todo-app exec -it todo-api-5b7bdf4dc4-rr6mh -- env | grep -E "DB_|PG"
```

**出力**:
```
DB_NAME=todos
DB_HOST=postgres
DB_PORT=5432
DB_USER=myuser
DB_PASSWORD=mypassword
```

#### 新しいPod（失敗）の環境変数

```bash
kubectl -n todo-app exec -it todo-api-7b674f64f4-xxxxx -- env | grep -E "DB_|PG"
```

**出力**:
```
PORT=3000
DB_HOST=postgres
DB_PORT=5432
DB_USER=<from secret>
DB_PASSWORD=<from secret>
DB_NAME=todos
```

**問題**: 新しいイメージ（sha-e432059）はPG*変数を使用

### 7. ロールバック

```bash
kubectl -n todo-app rollout undo deployment/todo-api
```

**出力**:
```
deployment.apps/todo-api rolled back
```

```bash
kubectl -n todo-app rollout status deployment/todo-api
```

**出力**:
```
Waiting for deployment "todo-api" rollout to finish: 1 old replicas are pending termination...
deployment "todo-api" successfully rolled out
```

### 8. 正しい環境変数でデプロイ（成功）

```bash
kubectl -n todo-app patch deployment todo-api -p '
{
  "spec": {
    "template": {
      "spec": {
        "imagePullSecrets": [{"name": "dockerhub-secret"}],
        "containers": [{
          "name": "todo-api",
          "image": "docker.io/subaru88/home-kube:sha-e432059",
          "env": [
            {"name": "PORT", "value": "3000"},
            {"name": "NODE_ENV", "value": "production"},
            {"name": "PGHOST", "value": "postgres"},
            {"name": "PGPORT", "value": "5432"},
            {"name": "PGUSER", "valueFrom": {"secretKeyRef": {"name": "postgres-secret", "key": "POSTGRES_USER"}}},
            {"name": "PGPASSWORD", "valueFrom": {"secretKeyRef": {"name": "postgres-secret", "key": "POSTGRES_PASSWORD"}}},
            {"name": "PGDATABASE", "value": "todos"}
          ]
        }]
      }
    }
  }
}'
```

**出力**:
```
deployment.apps/todo-api patched
```

#### デプロイ監視

```bash
kubectl -n todo-app rollout status deployment/todo-api
```

**出力**:
```
Waiting for deployment "todo-api" rollout to finish: 1 old replicas are pending termination...
deployment "todo-api" successfully rolled out
```

✅ **デプロイ成功**

### 9. デプロイ確認

#### Pod状態確認

```bash
kubectl -n todo-app get pods
```

**出力**:
```
NAME                        READY   STATUS    RESTARTS      AGE
postgres-5b689f85f9-4bx5r   1/1     Running   1 (29d ago)   53d
todo-api-7b674f64f4-r588x   1/1     Running   0             29s
```

#### ログ確認

```bash
kubectl -n todo-app logs todo-api-7b674f64f4-r588x
```

**出力**:
```
Database connected successfully
Server is running on port 3000
```

✅ **アプリケーション正常起動**

### 10. 動作確認

#### 一時的なcurlコンテナでテスト

```bash
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -n todo-app -- \
  curl http://todo-api-service/api/todos
```

**出力**:
```
[{"id":1,"title":"first task","description":null,"completed":false,"createdAt":"2025-09-15T03:30:35.176Z","updatedAt":"2025-09-15T03:30:35.176Z"}]
pod "curl-test" deleted
```

✅ **既存データが正常に取得できた**

#### 最終リソース確認

```bash
kubectl -n todo-app get all
```

**出力**:
```
NAME                            READY   STATUS    RESTARTS      AGE
pod/postgres-5b689f85f9-4bx5r   1/1     Running   1 (29d ago)   53d
pod/todo-api-7b674f64f4-r588x   1/1     Running   0             5m

NAME                       TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/postgres           ClusterIP   10.43.xyz.xyz   <none>        5432/TCP   53d
service/todo-api-service   ClusterIP   10.43.132.9     <none>        80/TCP     53d

NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/postgres   1/1     1            1           53d
deployment.apps/todo-api   1/1     1            1           53d

NAME                                  DESIRED   CURRENT   READY   AGE
replicaset.apps/postgres-5b689f85f9   1         1         1       53d
replicaset.apps/todo-api-7b674f64f4   1         1         1       5m
```

---

## まとめ

### ローカル環境（k3d）の成功ポイント

1. **k3dクラスタ作成**: 軽量でローカル開発に最適
2. **イメージのローカルビルド＆インポート**: ImagePullSecretの問題を回避
3. **デフォルト設定の活用**: Helmチャートのデフォルト値で動作
4. **StorageClass互換性**: `local-path`がk3sと同じ

### リモート環境（k3s）の成功ポイント

1. **古いリソースのクリーンアップ**: CrashLoopBackOffの原因を排除
2. **ImagePullSecret活用**: プライベートイメージへのアクセス
3. **環境変数の正確な設定**: PG*変数の使用
4. **段階的デプロイ**: ロールバック可能なデプロイ戦略

### 重要なコマンド

#### デバッグ
```bash
kubectl get pods -A                      # 全Pod確認
kubectl describe pod <pod-name>          # Pod詳細
kubectl logs <pod-name>                  # ログ確認
kubectl exec -it <pod-name> -- sh        # Pod内でコマンド実行
```

#### デプロイ管理
```bash
kubectl rollout status deployment/<name>  # デプロイ状態確認
kubectl rollout undo deployment/<name>    # ロールバック
kubectl rollout restart deployment/<name> # 再起動
```

#### リソース確認
```bash
kubectl get all -n <namespace>           # 全リソース確認
kubectl get events --sort-by='.lastTimestamp'  # イベント確認
```

このコマンド履歴を参考に、今後のデプロイ作業をスムーズに進めることができます。
