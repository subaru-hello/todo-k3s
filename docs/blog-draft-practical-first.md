# なんちゃってお家kubernetes DB + API編

## はじめに

このブログでは、実際に手を動かしながらKubernetesでPostgreSQLデータベースとNode.js APIアプリケーションをデプロイしていきます。

今回やること：
- 自宅サーバー（またはローカル環境）にk3s（軽量Kubernetes）をセットアップ
- PostgreSQLをStatefulSetとしてデプロイ
- Node.js APIをDeploymentとしてデプロイ
- Pod間通信の仕組みを理解
- Todo APIの動作確認

実際にデプロイしながら、「なぜこの設定が必要なのか」「どうやってPod同士が通信するのか」を解説していきます。

### 対象読者

- Dockerの基本を理解している方
- Kubernetesを初めて触る、または実践的な経験を積みたい方
- 自宅や開発環境でアプリケーションを動かしてみたい方

---

## 1. 環境準備

今回は、DBとAPIサーバーを立てていきます。自宅サーバーは1つなので、1つのノードにクラスターを作成し、そこにサービスを2つ用意します。

まずはローカル環境で動作確認をするため、**k3d**を使います。k3dは、Docker内でk3s（軽量Kubernetes）を実行できるツールです。k3sを直接インストールするとホストOSに影響を与えるため、Docker内で仮想的に動かすk3dを使用します。

### k3dのインストール

```bash
brew install k3d
```

インストール結果: k3d バージョン 5.8.3

### Helmのインストール

Helmは、Kubernetesのパッケージマネージャーです。複雑なアプリケーションを簡単にデプロイできます。

```bash
brew install helm
```

インストール結果: Helm バージョン 3.19.0

### k3dクラスタの作成

```bash
k3d cluster create todo-local \
  --api-port 6443 \
  --port 8080:80@loadbalancer \
  --port 8443:443@loadbalancer
```

作成結果:
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

クラスタ情報:
- クラスタ名: `todo-local`
- Kubernetesバージョン: v1.31.5+k3s1

### 環境確認

```bash
# Context確認
kubectl config current-context
```

出力: `k3d-todo-local`

```bash
# Node確認
kubectl get nodes
```

出力:
```
NAME                      STATUS   ROLES                  AGE   VERSION
k3d-todo-local-server-0   Ready    control-plane,master   1m    v1.31.5+k3s1
```

```bash
# StorageClass確認
kubectl get storageclass
```

出力:
```
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  1m
```

StorageClassが`local-path`になっています。これはk3sのデフォルトで、後ほどPostgreSQLのデータを永続化するときに使用します。

### Namespaceの作成

Kubernetesでは、リソースを論理的に分離するためにNamespaceを使います。今回は`app`という名前のNamespaceを作成します。

```bash
kubectl create namespace app
```

出力: `namespace/app created`

```bash
# 確認
kubectl get namespaces
```

`app` namespaceが作成されました。

---

## 2. アプリケーションの準備

### Node.js APIの実装

まずはNodejsから始めます。TODOをCRUDできるサーバーを立てます。今回は**Hono**というフレームワークを使用します。ORMには**TypeORM**を使います。

実装例（`packages/api/src/index.ts`）:

```typescript
import { Hono } from 'hono'
import { AppDataSource } from './db/dataSource'
import { todoRoutes } from './routes/todos'

const app = new Hono()

// データベース接続
AppDataSource.initialize()
  .then(() => {
    console.log('Database connected successfully')
  })
  .catch((error) => console.error('Error connecting to database:', error))

// ルーティング
app.route('/api/todos', todoRoutes)
app.get('/healthz', (c) => c.json({ status: 'healthy' }))

export default app
```

詳細の実装はリポジトリを参照してください。

### Dockerfileの作成とイメージビルド

Dockerfile（`packages/api/Dockerfile`）:

```dockerfile
# ビルダーステージ
FROM node:24-alpine AS builder
WORKDIR /app
RUN npm install -g pnpm
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

# 本番ステージ（Distroless）
FROM gcr.io/distroless/nodejs20-debian12 AS production
WORKDIR /app
COPY --from=builder /app/dist /app/dist
COPY --from=builder /app/node_modules /app/node_modules
COPY --from=builder /app/package.json /app/package.json
USER nonroot
CMD ["dist/index.js"]
```

イメージビルド:

```bash
cd packages/api
docker build -t docker.io/yourusername/todo-api:sha-e432059 --target production .
```

ビルド結果:
```
[+] Building 8.5s (15/15) FINISHED
 => [internal] load build definition from Dockerfile
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
 => => writing image sha256:...
 => => naming to docker.io/yourusername/todo-api:sha-e432059
```

イメージビルド成功（ビルド時間: 約8秒）

### k3dクラスタへイメージインポート

ローカル開発では、private registryへのpushを省略し、直接k3dへインポートします。

```bash
k3d image import docker.io/yourusername/todo-api:sha-e432059 -c todo-local
```

インポート結果:
```
INFO[0000] Importing image(s) into cluster 'todo-local'
INFO[0004] Successfully imported 1 image(s) into 1 cluster(s)
```

イメージがk3dクラスタ内で使用可能になりました。

---

## 3. PostgreSQLのデプロイ

では、データベースからデプロイしていきます。

### なぜStatefulSetを使うのか？

KubernetesにはPodを管理する方法がいくつかありますが、データベースのような**ステートフルなアプリケーション**には**StatefulSet**を使います。

StatefulSetの特徴:
- **固定された識別子**: Podに永続的な名前が付く（例: postgres-0）
- **安定したストレージ**: Pod再作成時も同じストレージが割り当てられる
- **順序保証**: Podの起動・終了が順序通りに実行される

```mermaid
graph TB
    SS[StatefulSet<br/>postgres]
    P1[Pod<br/>postgres-0]
    PVC1[PVC<br/>postgres-data-0]
    PV1[PV<br/>local-path-xxx]

    SS -->|作成| P1
    P1 -->|マウント| PVC1
    PVC1 -->|バインド| PV1
```

これに対して、後ほどデプロイするNode.js APIは**Deployment**を使います。Deploymentはステートレスなアプリケーション向けで、Podが再起動しても状態を保持する必要がありません。

### Secretの作成

データベースの認証情報をSecretとして保存します。Secretは、パスワードやAPIキーなどの機密情報を安全に保存するためのKubernetesリソースです。

```bash
kubectl -n app create secret generic postgres-secret \
  --from-literal=POSTGRES_USER=myuser \
  --from-literal=POSTGRES_PASSWORD=mypassword \
  --from-literal=POSTGRES_DB=todos
```

出力: `secret/postgres-secret created`

### StatefulSetのデプロイ

postgres-statefulset.yaml:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: app
spec:
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432
  clusterIP: None  # Headless Service
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: app
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:16-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: POSTGRES_USER
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: POSTGRES_PASSWORD
        - name: POSTGRES_DB
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: POSTGRES_DB
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: local-path
      resources:
        requests:
          storage: 5Gi
```

ここで注目すべきポイント:

1. **volumeClaimTemplates**: StatefulSet専用の機能で、Podごとに永続ボリューム（PVC）を自動作成します
2. **storageClassName: local-path**: 先ほど確認したStorageClassを指定
3. **env**: 環境変数にSecretの値を注入

デプロイ実行:

```bash
kubectl apply -f postgres-statefulset.yaml
```

出力:
```
service/postgres created
statefulset.apps/postgres created
```

確認:

```bash
kubectl -n app get statefulset
kubectl -n app get pods
kubectl -n app get pvc
```

Pod状態:
```
NAME         READY   STATUS    RESTARTS   AGE
postgres-0   1/1     Running   0          30s
```

PVC状態:
```
NAME                     STATUS   VOLUME                                     CAPACITY   STORAGECLASS
postgres-data-postgres-0 Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   5Gi        local-path
```

PostgreSQLが正常に起動し、PVCもBindされました。

### PVC（PersistentVolumeClaim）とは？

**PVC**は、永続的なストレージを要求するためのリソースです。

```mermaid
graph TB
    Pod[Pod<br/>postgres-0]
    PVC[PVC<br/>postgres-data-0<br/>要求: 5Gi]
    PV[PersistentVolume<br/>実体: /var/lib/rancher/k3s/storage/]
    SC[StorageClass<br/>local-path<br/>プロビジョナー]

    Pod -->|マウント| PVC
    PVC -->|バインド| PV
    SC -->|自動作成| PV
```

仕組み:
1. **PVC作成**: アプリケーションが「5Giのストレージが欲しい」と要求
2. **PVの自動作成**: StorageClassが自動的にPersistentVolume（PV）を作成
3. **バインド**: PVCとPVが紐付けられる
4. **マウント**: PodがPVCをマウントしてデータを保存

これにより、Podが再起動してもデータが失われません。

### 動作確認

```bash
# PostgreSQL Podのログ確認
kubectl -n app logs postgres-0
```

出力:
```
PostgreSQL Database directory appears to contain a database; Skipping initialization
...
LOG:  database system is ready to accept connections
```

```bash
# PostgreSQL接続テスト
kubectl -n app exec -it postgres-0 -- psql -U myuser -d todos -c "\dt"
```

出力: データベース接続成功

PostgreSQLが正常に動作しています。

---

## 4. Node.js APIのデプロイ

次に、APIサーバーをデプロイします。

### DeploymentとStatefulSetの違い

Node.js APIには**Deployment**を使います。Deploymentの特徴:

- **レプリカ管理**: 指定した数のPodを常に稼働させる
- **ローリングアップデート**: ダウンタイムなしでアプリケーションを更新
- **ロールバック**: 問題が発生した場合、以前のバージョンに戻す

```mermaid
graph TB
    D[Deployment<br/>api]
    RS[ReplicaSet<br/>api-xxx]
    P1[Pod<br/>api-xxx-abc]
    P2[Pod<br/>api-xxx-def]

    D -->|管理| RS
    RS -->|作成| P1
    RS -->|作成| P2
```

StatefulSetと違い、Podは特定の順序なく起動し、どのPodも同じ役割を果たします（ステートレス）。

### Deploymentのデプロイ

api-deployment.yaml:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: app
spec:
  selector:
    app: api
  ports:
    - protocol: TCP
      port: 80
      targetPort: 3000
  type: ClusterIP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: docker.io/yourusername/todo-api:sha-e432059
        ports:
        - containerPort: 3000
        env:
        - name: NODE_ENV
          value: "production"
        - name: PORT
          value: "3000"
        - name: PGHOST
          value: "postgres.app.svc.cluster.local"
        - name: PGPORT
          value: "5432"
        - name: PGUSER
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: POSTGRES_USER
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: POSTGRES_PASSWORD
        - name: PGDATABASE
          value: "todos"
        livenessProbe:
          httpGet:
            path: /healthz
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /healthz
            port: 3000
          initialDelaySeconds: 3
          periodSeconds: 5
```

ここで注目すべきポイント:

1. **replicas: 2**: APIサーバーを2つ起動（負荷分散）
2. **PGHOST: postgres.app.svc.cluster.local**: PostgreSQL Serviceへの接続（後述）
3. **livenessProbe/readinessProbe**: Podの健全性チェック

デプロイ実行:

```bash
kubectl apply -f api-deployment.yaml
```

出力:
```
service/api created
deployment.apps/api created
```

確認:

```bash
kubectl -n app get deployments
kubectl -n app get pods
```

Pod状態:
```
NAME                   READY   STATUS    RESTARTS   AGE
api-586858cdb6-zkvkk   1/1     Running   0          39s
api-586858cdb6-abc123  1/1     Running   0          39s
postgres-0             1/1     Running   0          5m
```

APIのPodが2つ起動しています。

---

## 5. Pod間通信の仕組み

ここで重要な疑問が生まれます：**どうやってNode.js APIからPostgreSQLに接続できているのか？**

### Serviceの役割

YAMLファイルで`PGHOST: postgres.app.svc.cluster.local`と指定しましたが、これは**Service**というリソースを指しています。

**Service**は、Podへの安定したネットワークアクセスを提供します。Podは再起動時にIPアドレスが変わるため、Serviceを使って固定のエンドポイントを作成します。

```mermaid
graph LR
    subgraph Cluster
        S[Service: postgres<br/>ClusterIP: 10.43.100.50<br/>DNS: postgres.app.svc.cluster.local]
        P1[Pod: postgres-0<br/>IP: 10.42.0.20]
    end

    Client[API Pod] -->|postgres.app.svc.cluster.local:5432| S
    S -->|ルーティング| P1
```

### DNS命名規則

KubernetesのServiceには、以下の形式で自動的にDNS名が割り当てられます：

```
<service-name>.<namespace>.svc.cluster.local
```

例:
- `postgres.app.svc.cluster.local` → PostgreSQL Service
- `api.app.svc.cluster.local` → API Service

### 実際の通信フロー

Node.js APIからPostgreSQLに接続する際の詳細なフローを見てみましょう。

```mermaid
sequenceDiagram
    participant App as Node.js App Pod<br/>(api-xxx)
    participant DNS as CoreDNS
    participant Proxy as kube-proxy
    participant Service as Service<br/>(postgres)
    participant DB as PostgreSQL Pod<br/>(postgres-0)

    App->>DNS: "postgres" のIPアドレスは？
    DNS->>App: 10.43.100.50 (Service IP)

    App->>Proxy: 10.43.100.50:5432 に接続
    Note over Proxy: iptablesルールで<br/>バックエンドPodを選択
    Proxy->>DB: 10.42.0.20:5432 に転送

    DB->>Proxy: レスポンス
    Proxy->>App: レスポンス転送

    Note over App,DB: 以降の通信は直接接続<br/>（接続確立後はプロキシ不要）
```

ステップ詳細:

1. **DNS解決**:
   - Node.js Appが`PGHOST=postgres`で接続試行
   - **CoreDNS**（Kubernetes内部のDNSサーバー）が`postgres.app.svc.cluster.local` → `10.43.100.50`（Service ClusterIP）に解決

2. **Service経由のルーティング**:
   - Appが`10.43.100.50:5432`に接続
   - **kube-proxy**（各ノード上で動作するネットワークプロキシ）のiptablesルールが発火
   - バックエンドPod（`postgres-0`: `10.42.0.20`）に転送

3. **直接通信**:
   - TCPコネクション確立後は、PodのIPアドレスで直接通信
   - kube-proxyは新しい接続のルーティングのみを担当

重要ポイント:
- ServiceのIPアドレスは仮想的（どのPodにも割り当てられていない）
- kube-proxyが実際のPod IPに変換
- Podが再起動してIPが変わっても、ServiceのIPは変わらないため、アプリケーション側は再起動不要

### 現在の構成図

```mermaid
graph TB
    subgraph "Kubernetes Cluster"
        subgraph "Namespace: app"
            subgraph "Node.js API"
                D1[Deployment: api<br/>replicas: 2]
                P1[Pod: api-xxx-abc]
                P2[Pod: api-xxx-def]
                S1[Service: api<br/>ClusterIP<br/>DNS: api.app.svc.cluster.local]
            end

            subgraph "PostgreSQL"
                SS[StatefulSet: postgres<br/>replicas: 1]
                P3[Pod: postgres-0]
                S2[Service: postgres<br/>ClusterIP<br/>DNS: postgres.app.svc.cluster.local]
                PVC[PVC: postgres-data-0<br/>5Gi]
            end

            SEC[Secret: postgres-secret]
        end
    end

    D1 -->|作成| P1
    D1 -->|作成| P2
    S1 -->|ルーティング| P1
    S1 -->|ルーティング| P2

    SS -->|作成| P3
    S2 -->|ルーティング| P3
    P3 -->|マウント| PVC

    P1 -.->|環境変数| SEC
    P2 -.->|環境変数| SEC
    P3 -.->|環境変数| SEC

    P1 -->|DB接続| S2
    P2 -->|DB接続| S2
```

---

## 6. 動作確認

### Port Forwardでアクセス

```bash
kubectl -n app port-forward svc/api 3000:80 &
```

### ヘルスチェック

```bash
curl http://localhost:3000/healthz
```

出力:
```json
{"status":"healthy"}
```

```bash
curl http://localhost:3000/dbcheck
```

出力:
```json
{"status":"ok","db":"connected"}
```

APIとデータベース接続が正常です。

### Todo API機能テスト

#### Todo一覧取得（空のリスト）

```bash
curl http://localhost:3000/api/todos
```

出力:
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

レスポンス:
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

Todo作成成功。

#### Todo一覧取得（作成後）

```bash
curl http://localhost:3000/api/todos
```

レスポンス:
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

データの永続化が確認できました。

#### Todo更新

```bash
curl -X PUT http://localhost:3000/api/todos/1 \
  -H "Content-Type: application/json" \
  -d '{
    "title": "k3dデプロイテスト",
    "description": "更新済み",
    "completed": true
  }'
```

Todo更新成功。

#### Todo削除

```bash
curl -X DELETE http://localhost:3000/api/todos/1
```

Todo削除成功。

---

## 7. トラブルシューティング

実際のデプロイでは、さまざまな問題が発生する可能性があります。よくある問題と解決方法を紹介します。

### Podが起動しない（ImagePullBackOff）

症状:
```bash
kubectl -n app get pods
```

出力:
```
NAME       READY   STATUS             RESTARTS   AGE
api-xxx    0/1     ImagePullBackOff   0          2m
```

原因: プライベートなDockerイメージにアクセスできない

解決方法:

```bash
# ImagePullSecretを作成
kubectl -n app create secret docker-registry dockerhub-secret \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=<your-docker-username> \
  --docker-password=$DOCKER_PASSWORD
```

出力: `secret/dockerhub-secret created`

```bash
# Deploymentに追加
kubectl -n app patch deployment api -p '
{
  "spec": {
    "template": {
      "spec": {
        "imagePullSecrets": [{"name": "dockerhub-secret"}]
      }
    }
  }
}'
```

出力: `deployment.apps/api patched`

ImagePullSecretを設定することで、プライベートイメージにアクセスできるようになります。

### Podがクラッシュする（CrashLoopBackOff）

症状:
```bash
kubectl -n app get pods
```

出力:
```
NAME       READY   STATUS             RESTARTS   AGE
api-xxx    0/1     CrashLoopBackOff   5          3m
```

原因: アプリケーションエラー（PostgreSQL接続失敗など）

調査方法:

```bash
# ログを確認
kubectl -n app logs api-xxx
```

出力例:
```
Error connecting to database: AggregateError [ECONNREFUSED]:
    at internalConnectMultiple (node:net:1122:18)
  code: 'ECONNREFUSED',
  address: '127.0.0.1',
  port: 5432
```

原因: 環境変数の設定ミス

環境変数の確認:

```bash
kubectl -n app describe pod api-xxx | grep -A 20 "Environment:"
```

問題のある環境変数例:
```
DB_HOST=postgres  # ❌ 新しいイメージはPGHOSTを使用
DB_PORT=5432      # ❌ 新しいイメージはPGPORTを使用
```

解決方法:

PostgreSQL標準環境変数（PG*）を使用するように修正します：

```bash
kubectl -n app patch deployment api -p '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "api",
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

デプロイ監視:

```bash
kubectl -n app rollout status deployment/api
```

出力:
```
Waiting for deployment "api" rollout to finish: 1 old replicas are pending termination...
deployment "api" successfully rolled out
```

正しい環境変数でデプロイ成功。

### データベース接続エラー

確認手順:

```bash
# 1. PostgreSQL Podが起動しているか
kubectl -n app get pods postgres-0
```

```bash
# 2. PostgreSQL Serviceが存在するか
kubectl -n app get svc postgres
```

```bash
# 3. DNS解決ができるか
kubectl -n app exec -it api-xxx -- nslookup postgres.app.svc.cluster.local
```

```bash
# 4. ポート接続確認
kubectl -n app exec -it api-xxx -- nc -zv postgres.app.svc.cluster.local 5432
```

```bash
# 5. PostgreSQLログ確認
kubectl -n app logs postgres-0
```

---

## 8. ローリングアップデートとスケーリング

### ローリングアップデート

新しいバージョンのアプリケーションをダウンタイムなしでデプロイします。

```bash
# イメージタグを更新
kubectl -n app set image deployment/api \
  api=docker.io/yourusername/todo-api:v1.1.0
```

出力: `deployment.apps/api image updated`

```bash
# ローリングアップデートの監視
kubectl -n app rollout status deployment/api
```

出力:
```
Waiting for deployment "api" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "api" rollout to finish: 1 old replicas are pending termination...
deployment "api" successfully rolled out
```

ローリングアップデート成功。古いPodから新しいPodへ段階的に切り替わりました。

ロールバック:

問題が発生した場合、前のバージョンに戻します。

```bash
# 前のバージョンにロールバック
kubectl -n app rollout undo deployment/api
```

出力: `deployment.apps/api rolled back`

```bash
# 特定のリビジョンにロールバック
kubectl -n app rollout history deployment/api
kubectl -n app rollout undo deployment/api --to-revision=2
```

### スケーリング

負荷に応じてPod数を増減させます。

```bash
# レプリカ数を5に増やす
kubectl -n app scale deployment api --replicas=5
```

出力: `deployment.apps/api scaled`

```bash
# 確認
kubectl -n app get pods
```

出力:
```
NAME                   READY   STATUS    RESTARTS   AGE
api-586858cdb6-zkvkk   1/1     Running   0          10m
api-586858cdb6-abc123  1/1     Running   0          10m
api-586858cdb6-def456  1/1     Running   0          10s
api-586858cdb6-ghi789  1/1     Running   0          10s
api-586858cdb6-jkl012  1/1     Running   0          10s
postgres-0             1/1     Running   0          15m
```

Podが5つに増えました。

```bash
# 元に戻す
kubectl -n app scale deployment api --replicas=2
```

出力: `deployment.apps/api scaled`

---

## 9. クラスター全体像の振り返り

ここまでで、PostgreSQLとNode.js APIのデプロイが完了しました。最後に、Kubernetesクラスター全体の構成を振り返りましょう。

### 自宅Kubernetesのアーキテクチャ

今回構築した環境は、1台のマシンでControl PlaneとWorker Nodeの両方を稼働させています。

```mermaid
graph TB
    subgraph "Single Node (自宅サーバー1台)"
        subgraph "Control Plane"
            API[API Server]
            ETCD[SQLite<br/>※etcdの代わり]
            SCHED[Scheduler]
            CTRL[Controller Manager]
        end

        subgraph "Worker"
            KUBELET[kubelet]
            PROXY[kube-proxy]
            RUNTIME[containerd]
        end

        subgraph "Application Pods"
            P1[api-xxx]
            P2[postgres-0]
        end
    end

    Client[kubectl]

    Client -->|API リクエスト| API
    API -->|状態保存| ETCD
    SCHED -->|スケジューリング| KUBELET
    KUBELET -->|Pod起動| RUNTIME
    RUNTIME -->|コンテナ実行| P1
    RUNTIME -->|コンテナ実行| P2
```

k3sの特徴:
- **軽量**: メモリ使用量が少ない（512MB～）
- **シンプル**: 単一バイナリで配布
- **etcd不要**: デフォルトでSQLiteを使用
- **組み込みLoadBalancer**: ServiceLB（Klipper）が標準搭載

### 標準的なKubernetesクラスター（参考）

本番環境では、役割に応じて複数のノードで構成されることが一般的です。

```mermaid
graph TB
    subgraph "Control Plane Nodes（管理ノード）"
        CP1[Master 1<br/>API Server<br/>etcd<br/>Scheduler<br/>Controller Manager]
        CP2[Master 2]
        CP3[Master 3]
    end

    subgraph "Worker Nodes（ワーカーノード）"
        W1[Worker 1<br/>kubelet<br/>kube-proxy<br/>Container Runtime]
        W2[Worker 2]
        W3[Worker 3]
    end

    Client[kubectl]

    Client -->|API リクエスト| CP1
    CP1 -.->|同期| CP2
    CP1 -.->|同期| CP3

    CP1 -->|Pod スケジューリング| W1
    CP1 -->|Pod スケジューリング| W2
    CP1 -->|Pod スケジューリング| W3

    W1 -.->|ヘルスチェック| CP1
    W2 -.->|ヘルスチェック| CP1
    W3 -.->|ヘルスチェック| CP1
```

Control Plane（コントロールプレーン）: クラスター全体を管理する「頭脳」部分
Worker Node（ワーカーノード）: 実際にアプリケーション（Pod）が動作するノード

今回学んだ内容は、本番環境の標準的なKubernetesでもそのまま適用できます。

---

## まとめ

この記事では、実際にPostgreSQLとNode.js APIをデプロイしながら、Kubernetesの基本的な仕組みを学びました。

### 学んだこと

**Kubernetesのリソース**:
- **StatefulSet**: ステートフルなアプリケーション（データベース）向け
- **Deployment**: ステートレスなアプリケーション（Web API）向け
- **Service**: Podへの安定したネットワークアクセスを提供
- **PVC**: 永続的なストレージ
- **Secret**: 機密情報の管理

**Pod間通信の仕組み**:
- **CoreDNS**: ServiceのDNS名前解決
- **kube-proxy**: トラフィックルーティング
- **通信フロー**: DNS → Service → kube-proxy → Pod

**実践スキル**:
- PostgreSQLのStatefulSetデプロイ
- Node.js APIのDeploymentデプロイ
- トラブルシューティング手法
- ローリングアップデートとロールバック
- スケーリング

### 成功のポイント

1. **ローカル環境での検証**: k3dでローカルテストを行い、問題を事前に発見
2. **環境変数の正確な設定**: PostgreSQL標準環境変数（PG*）の使用
3. **段階的デプロイ**: ロールバック可能なデプロイ戦略
4. **適切なリソース管理**: StatefulSet（DB）とDeployment（API）の使い分け

### 次のステップ

1. **高可用性構成**: 複数ノードでクラスターを構築
2. **Ingress**: 外部からのHTTP/HTTPSアクセスを管理
3. **ConfigMap**: アプリケーション設定の外部化
4. **Horizontal Pod Autoscaler**: CPU/メモリ使用率に応じた自動スケーリング
5. **Monitoring**: Prometheus + Grafanaで監視
6. **CI/CD**: GitHub ActionsからKubernetesへ自動デプロイ

### 参考資料

- [Kubernetes公式ドキュメント](https://kubernetes.io/docs/)
- [k3s公式サイト](https://k3s.io/)
- [Helm公式ドキュメント](https://helm.sh/docs/)

---

## 付録: 便利なkubectlコマンド

### リソース確認

```bash
# すべてのリソースを表示
kubectl -n app get all

# Podの詳細情報
kubectl -n app describe pod <pod-name>

# ログ表示
kubectl -n app logs <pod-name>
kubectl -n app logs -f <pod-name>  # リアルタイム表示

# 前回のクラッシュログ
kubectl -n app logs <pod-name> --previous

# イベント一覧
kubectl -n app get events --sort-by='.lastTimestamp'
```

### デバッグ

```bash
# Pod内でコマンド実行
kubectl -n app exec -it <pod-name> -- sh

# 一時的なデバッグPod
kubectl run debug --image=busybox -it --rm --restart=Never -n app -- sh

# ポートフォワード
kubectl -n app port-forward <pod-name> 8080:3000
kubectl -n app port-forward svc/<service-name> 8080:80
```

### リソース操作

```bash
# 再起動
kubectl -n app rollout restart deployment/<deployment-name>

# スケーリング
kubectl -n app scale deployment/<deployment-name> --replicas=3

# 削除
kubectl -n app delete pod <pod-name>
kubectl -n app delete deployment <deployment-name>
```

これでKubernetesでの実践的なデプロイ方法を習得できました。自宅や開発環境でぜひ試してみてください！
