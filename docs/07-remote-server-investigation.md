# リモートサーバー調査と最新イメージデプロイレポート

## 実施日時
2025年11月7日

## 目次
- [初期状況](#初期状況)
- [問題調査](#問題調査)
- [クリーンアップ作業](#クリーンアップ作業)
- [最新イメージのデプロイ](#最新イメージのデプロイ)
- [トラブルシューティング](#トラブルシューティング)
- [最終確認](#最終確認)
- [まとめ](#まとめ)

## 初期状況

### リモートサーバー情報
- **ホスト**: octom-server (ssh.octomblog.com経由でアクセス)
- **接続方法**: Cloudflare Tunnel経由のSSH
- **Kubernetes**: k3s v1.31.5+k3s1

### 発見された問題

**CrashLoopBackOff状態のPod一覧**:
```bash
$ kubectl get pods -A

NAMESPACE     NAME                                             READY   STATUS             RESTARTS
default       node-app-b5dcdcf8f-hzvn5                         0/1     CrashLoopBackOff   4718
default       go-echo-86bb755986-lswvt                         0/1     CrashLoopBackOff   9622
default       cloudflared-cloudflare-tunnel-5d7fcf4f67-fgdzb   0/1     CrashLoopBackOff   9718
default       cloudflared-cloudflare-tunnel-5d7fcf4f67-qnwrt   0/1     CrashLoopBackOff   9719
```

**正常に動作しているリソース**:
```bash
NAMESPACE     NAME                                      READY   STATUS    RESTARTS
app           cloudflared-6c88894cc9-fq2cz              1/1     Running   0
todo-app      postgres-5b689f85f9-4bx5r                 1/1     Running   1 (29d ago)
todo-app      todo-api-5b7bdf4dc4-rr6mh                 1/1     Running   1 (29d ago)
```

## 問題調査

### node-appの詳細調査

#### Pod情報確認
```bash
$ kubectl -n default describe pod node-app-b5dcdcf8f-hzvn5
```

**重要な発見**:
- **イメージ**: `docker.io/library/node:24-alpine` （単なるNode.jsベースイメージ）
- **Exit Code**: 0（正常終了）
- **ログ**: 空
- **原因**: アプリケーションコードが含まれていない

#### 結論
`node-app`は古いKustomizeベースのデプロイメントの残骸で、正しいアプリケーションイメージではありません。

### todo-appの動作確認

既存のtodo-apiが`todo-app` namespaceで正常に動作していることを確認：

```bash
$ kubectl -n todo-app exec -it todo-api-5b7bdf4dc4-rr6mh -- sh -c "wget -qO- http://localhost:3000/healthz && echo"
{"status":"healthy"}

$ kubectl -n todo-app exec -it todo-api-5b7bdf4dc4-rr6mh -- sh -c "wget -qO- http://localhost:3000/api/todos && echo"
[{"id":1,"title":"first task","description":null,"completed":false,"createdAt":"2025-09-15T03:30:35.176Z","updatedAt":"2025-09-15T03:30:35.176Z"}]
```

✅ **既存のAPIは正常に動作**

## クリーンアップ作業

### 不要なDeploymentの削除

```bash
# node-app削除
$ kubectl -n default delete deployment node-app
deployment.apps "node-app" deleted

# go-echo削除
$ kubectl -n default delete deployment go-echo
deployment.apps "go-echo" deleted

# cloudflared-cloudflare-tunnel削除
$ kubectl -n default delete deployment cloudflared-cloudflare-tunnel
deployment.apps "cloudflared-cloudflare-tunnel" deleted
```

### クリーンアップ後の状態

```bash
$ kubectl get pods -n default
NAME                           READY   STATUS    RESTARTS      AGE
cloudflared-6bfd89b687-pmt4c   1/1     Running   4 (29d ago)   34d
hello-84bf6f98f5-d2fl8         1/1     Running   1 (29d ago)   34d
postgres-67865ff6cc-2hqgm      1/1     Running   1 (29d ago)   55d
```

✅ **CrashLoopBackOffのPodが全て削除された**

## 最新イメージのデプロイ

### デプロイ戦略

**選択した方法**: ImagePullSecretを使用したプライベートイメージのPull

**理由**:
- Cloudflare Tunnel経由のSCPは大きなファイル転送に不向き
- 本番環境に適した方法
- 今後のデプロイが簡単になる

### ステップ1: ImagePullSecret作成

```bash
$ kubectl create secret docker-registry dockerhub-secret \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=subaru88 \
  --docker-password=$PASSWORD \
  -n todo-app

$ kubectl -n todo-app get secret dockerhub-secret
NAME               TYPE                             DATA   AGE
dockerhub-secret   kubernetes.io/dockerconfigjson   1      18s
```

✅ **ImagePullSecret作成成功**

### ステップ2: 初回デプロイ試行（失敗）

```bash
$ kubectl -n todo-app patch deployment todo-api -p '
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

**エラー内容**:
```
Error connecting to database: AggregateError [ECONNREFUSED]:
    at internalConnectMultiple (node:net:1122:18)
  code: 'ECONNREFUSED',
  address: '127.0.0.1',
  port: 5432
```

**原因**: 環境変数の不一致

## トラブルシューティング

### 環境変数の比較

#### 古いPod（動作中）
```bash
DB_NAME=todos
DB_HOST=postgres
DB_PORT=5432
DB_USER=myuser
DB_PASSWORD=mypassword
```

#### 新しいPod（失敗）
```bash
PORT=3000
DB_HOST=postgres
DB_PORT=5432
DB_USER=<from secret>
DB_PASSWORD=<from secret>
DB_NAME=todos
```

**問題**: 新しいイメージ（sha-e432059）は異なる環境変数名を使用

- 古いイメージ: `DB_*`
- 新しいイメージ: `PG*` (PostgreSQL標準)

### 解決策: 正しい環境変数で再デプロイ

#### ステップ1: ロールバック
```bash
$ kubectl -n todo-app rollout undo deployment/todo-api
$ kubectl -n todo-app rollout status deployment/todo-api
```

#### ステップ2: 正しい環境変数でpatch
```bash
$ kubectl -n todo-app patch deployment todo-api -p '
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

#### ステップ3: デプロイ監視
```bash
$ kubectl -n todo-app rollout status deployment/todo-api
Waiting for deployment "todo-api" rollout to finish: 1 old replicas are pending termination...
deployment "todo-api" successfully rolled out
```

✅ **デプロイ成功**

### デプロイ後のログ確認

```bash
$ kubectl -n todo-app get pods
NAME                        READY   STATUS    RESTARTS      AGE
postgres-5b689f85f9-4bx5r   1/1     Running   1 (29d ago)   53d
todo-api-7b674f64f4-r588x   1/1     Running   0             29s

$ kubectl -n todo-app logs todo-api-7b674f64f4-r588x
Database connected successfully
Server is running on port 3000
```

✅ **アプリケーション正常起動**

## 最終確認

### Distrolessイメージの制約

新しいイメージ（sha-e432059）はDistrolessで、シェルが含まれていません：

```bash
$ kubectl -n todo-app exec -it todo-api-7b674f64f4-r588x -- sh
error: executable file not found in $PATH
```

### 代替テスト方法

一時的なcurlコンテナを使用：

```bash
# API動作確認
$ kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -n todo-app -- \
  curl http://todo-api-service/api/todos

[{"id":1,"title":"first task","description":null,"completed":false,"createdAt":"2025-09-15T03:30:35.176Z","updatedAt":"2025-09-15T03:30:35.176Z"}]
pod "curl-test" deleted
```

✅ **既存データが正常に取得できた**

### デプロイ完了状態

```bash
$ kubectl -n todo-app get all

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

## まとめ

### 解決した問題

1. ✅ **node-appのCrashLoopBackOff**
   - 原因: 古いKustomizeデプロイメントの残骸（アプリコードなし）
   - 解決: Deployment削除

2. ✅ **最新イメージへの更新**
   - イメージ: `docker.io/subaru88/home-kube:sha-e432059`
   - 方法: ImagePullSecretを使用

3. ✅ **環境変数の不一致**
   - 原因: 旧イメージ（DB_*）と新イメージ（PG*）の環境変数名の違い
   - 解決: 正しい環境変数（PGHOST, PGPORT, etc.）で再デプロイ

### 主要な学び

#### 1. 環境変数の命名規則
- **旧イメージ**: カスタム環境変数（`DB_HOST`, `DB_USER`, etc.）
- **新イメージ**: PostgreSQL標準環境変数（`PGHOST`, `PGUSER`, etc.）
- **教訓**: イメージ更新時は環境変数の互換性を事前確認

#### 2. Distrolessイメージの特性
- シェルなし（`sh`, `bash`が使えない）
- セキュリティ向上
- デバッグには別途テストコンテナが必要

#### 3. ImagePullSecretの設定
- プライベートイメージの本番デプロイに最適
- 一度設定すれば、以降のデプロイが簡単
- 大きなイメージファイルの転送不要

#### 4. ローリングアップデート
- 環境変数のミスでCrashLoopBackOffになった場合
- `kubectl rollout undo`で簡単にロールバック可能
- ゼロダウンタイムで更新可能

### デプロイ成功の要因

1. **段階的アプローチ**
   - ローカルk3d環境で事前テスト
   - リモート環境の既存状態確認
   - ImagePullSecret設定
   - 段階的なデプロイ

2. **適切なトラブルシューティング**
   - ログの確認
   - 環境変数の比較
   - ロールバック→再試行

3. **本番環境に適した方法の選択**
   - ImagePullSecretの使用
   - Kubernetesネイティブな手法

### 今後のデプロイ手順

最新イメージへの更新は以下の手順で実行可能：

```bash
# 1. イメージタグを更新
kubectl -n todo-app set image deployment/todo-api \
  todo-api=docker.io/subaru88/home-kube:NEW_TAG

# 2. デプロイ監視
kubectl -n todo-app rollout status deployment/todo-api

# 3. 動作確認
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -n todo-app -- \
  curl http://todo-api-service/healthz
```

**注意**: 環境変数が異なる場合は、`kubectl patch`で環境変数も一緒に更新する必要があります。

### リソース状態

#### クリーンアップ完了
- ❌ `node-app` (default namespace) - 削除済み
- ❌ `go-echo` (default namespace) - 削除済み
- ❌ `cloudflared-cloudflare-tunnel` (default namespace) - 削除済み

#### 稼働中
- ✅ `todo-api` (todo-app namespace) - sha-e432059で稼働中
- ✅ `postgres` (todo-app namespace) - 正常稼働
- ✅ `cloudflared` (app namespace) - 正常稼働

### 参考情報

#### 使用したコマンド一覧

```bash
# 調査
kubectl get pods -A
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>

# クリーンアップ
kubectl delete deployment <deployment-name> -n <namespace>

# ImagePullSecret作成
kubectl create secret docker-registry dockerhub-secret \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=USERNAME \
  --docker-password=PASSWORD \
  -n <namespace>

# デプロイメント更新
kubectl patch deployment <deployment-name> -n <namespace> -p '{...}'
kubectl rollout status deployment/<deployment-name> -n <namespace>
kubectl rollout undo deployment/<deployment-name> -n <namespace>

# 動作確認
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -n <namespace> -- \
  curl http://<service-name>/<endpoint>
```

---

このレポートは、リモートk3sサーバーでのCrashLoopBackOff問題の調査から、最新イメージへのデプロイ成功までの完全な記録です。今後の運用やトラブルシューティングの参考資料として活用できます。
