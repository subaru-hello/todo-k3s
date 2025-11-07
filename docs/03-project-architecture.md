# Todo-k3s プロジェクトアーキテクチャ

## 目次
- [プロジェクト概要](#プロジェクト概要)
- [アプリケーション構成](#アプリケーション構成)
- [Dockerfile構成](#dockerfile構成)
- [Kubernetesデプロイメント](#kubernetesデプロイメント)
- [デプロイメント変遷](#デプロイメント変遷)
- [CI/CDパイプライン](#cicdパイプライン)
- [アーキテクチャ図](#アーキテクチャ図)

## プロジェクト概要

このプロジェクトは、自宅k3sクラスタで稼働するTodo管理APIアプリケーションです。

### 技術スタック

- **フレームワーク**: Hono (軽量Node.jsウェブフレームワーク)
- **ランタイム**: Node.js 24 (@hono/node-server)
- **ORM**: TypeORM (PostgreSQL連携)
- **言語**: TypeScript
- **データベース**: PostgreSQL 16
- **コンテナランタイム**: k3s (軽量Kubernetes)
- **パッケージマネージャ**: pnpm

## アプリケーション構成

### ディレクトリ構造

```
todo-k3s/
├── packages/
│   └── api/                    # Todo APIアプリケーション
│       ├── src/
│       │   ├── index.ts        # エントリーポイント
│       │   ├── db/
│       │   │   └── dataSource.ts  # TypeORM設定
│       │   ├── entities/
│       │   │   └── Todo.ts     # Todoエンティティ
│       │   └── routes/
│       │       └── todos.ts    # Todoルーティング
│       ├── Dockerfile          # マルチステージビルド
│       └── package.json
├── deployment/
│   ├── charts/                 # Helmチャート
│   │   ├── api/
│   │   └── postgres/
│   ├── environments/           # 環境別設定
│   │   ├── local/
│   │   └── prod/
│   └── scripts/
│       └── deploy.sh           # デプロイスクリプト
└── .github/
    └── workflows/
        └── build-and-push.yml  # CI/CDワークフロー
```

### APIエンドポイント

#### ヘルスチェック
- `GET /healthz` - サービスヘルスチェック
- `GET /dbcheck` - データベース接続確認

#### Todo CRUD
- `GET /api/todos` - Todo一覧取得
- `GET /api/todos/:id` - Todo詳細取得
- `POST /api/todos` - Todo作成
- `PUT /api/todos/:id` - Todo更新
- `DELETE /api/todos/:id` - Todo削除

#### リクエスト/レスポンス例

**Todo作成 (POST /api/todos)**
```json
// リクエスト
{
  "title": "新しいタスク",
  "description": "タスクの説明",
  "completed": false
}

// レスポンス
{
  "id": 1,
  "title": "新しいタスク",
  "description": "タスクの説明",
  "completed": false,
  "createdAt": "2025-10-08T12:00:00.000Z",
  "updatedAt": "2025-10-08T12:00:00.000Z"
}
```

### データモデル

**Todoエンティティ** (`packages/api/src/entities/Todo.ts`)

```typescript
@Entity()
export class Todo {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  title: string;

  @Column({ nullable: true })
  description: string;

  @Column({ default: false })
  completed: boolean;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
```

### 環境変数

#### 必須環境変数
- `NODE_ENV`: 実行環境 (development/production)
- `PGHOST`: PostgreSQLホスト名
- `PGPORT`: PostgreSQLポート (デフォルト: 5432)
- `PGUSER`: PostgreSQLユーザー名
- `PGPASSWORD`: PostgreSQLパスワード
- `PGDATABASE`: データベース名

#### オプション環境変数
- `ALLOWED_ORIGINS`: CORS許可オリジン (カンマ区切り)
- `JWT_SECRET`: JWT署名用シークレット

## Dockerfile構成

### マルチステージビルド

**ファイル**: `packages/api/Dockerfile`

#### 1. builderステージ
```dockerfile
FROM node:24-alpine AS builder
WORKDIR /app
# pnpmインストール
# 依存関係インストール
# TypeScriptビルド
```

#### 2. developmentステージ
```dockerfile
FROM node:24-alpine AS development
# シェルあり、デバッグ可能
# ローカル開発向け
```

#### 3. productionステージ
```dockerfile
FROM gcr.io/distroless/nodejs20-debian12 AS production
# シェルなし、セキュア
# 最小限のランタイム
# 本番環境向け
```

### ビルド方法

```bash
# 開発用イメージ
docker build -t todo-api:dev --target development .

# 本番用イメージ
docker build -t todo-api:prod --target production .

# マルチアーキテクチャビルド（CI/CD）
docker buildx build --platform linux/amd64,linux/arm64 \
  --target production \
  -t docker.io/subaru88/home-kube:latest .
```

## Kubernetesデプロイメント

### 現在の構成（Helmベース）

#### Namespace
- `app`: アプリケーションリソース用

#### Helmチャート

**PostgreSQL Chart** (`deployment/charts/postgres/`)
- **StatefulSet**: 永続化されたPostgreSQLインスタンス
- **Service**: ClusterIP (postgres.app.svc.cluster.local)
- **Secret**: 認証情報 (postgres-secret)
- **PVC**: データ永続化 (5-20Gi)
- **NetworkPolicy**: Pod間通信制御（本番のみ）

**API Chart** (`deployment/charts/api/`)
- **Deployment**: APIサーバー（レプリカ数は環境により変動）
- **Service**: ClusterIP (api.app.svc.cluster.local)
- **Probes**:
  - Readiness: `/healthz` (初期3秒、間隔5秒)
  - Liveness: `/healthz` (初期10秒、間隔10秒)

#### 環境別設定

**ローカル環境** (`deployment/environments/local/`)

```yaml
# api-values.yaml
namespace: app
image:
  repository: docker.io/subaru88/home-kube
  tag: "latest"
replicaCount: 1
env:
  NODE_ENV: development
  ALLOWED_ORIGINS: "http://localhost:5173,http://localhost:3001"
postgres:
  host: postgres.app.svc.cluster.local
resources:
  requests: {cpu: 50m, memory: 128Mi}
  limits: {cpu: 500m, memory: 512Mi}

# postgres-values.yaml
auth:
  username: localuser
  password: localpass
  database: todos
persistence:
  size: 5Gi
```

**本番環境** (`deployment/environments/prod/`)

```yaml
# api-values.yaml
replicaCount: 2
env:
  NODE_ENV: production
  ALLOWED_ORIGINS: "https://app.octomblog.com"
postgres:
  useSecret: true
  secretName: postgres-secret
resources:
  requests: {cpu: 100m, memory: 256Mi}
  limits: {cpu: 1000m, memory: 1Gi}

# postgres-values.yaml
persistence:
  size: 20Gi
  storageClassName: "local-path"
networkPolicy:
  enabled: true  # Pod間通信を制限
```

### デプロイコマンド

```bash
# ローカル環境
./deployment/scripts/deploy.sh local

# 本番環境（イメージタグ指定推奨）
./deployment/scripts/deploy.sh prod sha-abc1234
```

## デプロイメント変遷

### 旧構成: Kustomizeベース（削除済み）

**デプロイメント名**: `node-app`

- Kustomizeによるマニフェスト管理
- 環境別overlays
- 手動でのSecret管理

**問題点**:
- 設定の重複
- 環境間の差分管理が複雑
- バージョン管理が困難

### 現在の構成: Helmベース

**デプロイメント名**: `api`

**改善点**:
- テンプレート化による再利用性向上
- values.yamlでの環境別設定
- デプロイスクリプトの統一化
- Secret管理の自動化

**移行履歴**:
```
git log --oneline | grep -E "kustomize|helm"
5b1a339 fix: kustomizeリソースを削除
757766e fix: Secret作成の競合を解消
```

### クリーンアップ

古いKustomizeリソースを削除するスクリプト：

```bash
./deployment/cleanup-old-deployments.sh
```

削除対象：
- Deployment: node-app
- Service: node-app
- ConfigMap: node-app-config
- 関連するReplicaSet/Pod

## CI/CDパイプライン

### GitHub Actions Workflow

**ファイル**: `.github/workflows/build-and-push.yml`

#### トリガー

```yaml
on:
  push:
    branches: [main]
    paths:
      - 'packages/api/**'
  workflow_dispatch:
```

#### ビルドプロセス

1. **チェックアウト**: ソースコード取得
2. **Docker Buildxセットアップ**: マルチアーキテクチャビルド準備
3. **Docker Hubログイン**: 認証
4. **イメージビルド＆プッシュ**:
   - プラットフォーム: `linux/amd64`, `linux/arm64`
   - ターゲット: `production`
   - タグ:
     - `sha-{commit}` (推奨、例: sha-329968d)
     - `main`
     - `latest`

#### 使用されるSecrets

- `DOCKERHUB_USERNAME`: Docker Hubユーザー名
- `DOCKERHUB_TOKEN`: Docker Hubアクセストークン

#### デプロイフロー

```
コード変更 (packages/api/**)
  ↓
GitHub Push (main branch)
  ↓
GitHub Actions Trigger
  ↓
Docker Image Build (production, multi-arch)
  ↓
Push to Docker Hub (docker.io/subaru88/home-kube)
  ↓ (タグ: sha-xxx, main, latest)
手動デプロイ
  ↓
./deployment/scripts/deploy.sh prod sha-xxx
  ↓
Helm Upgrade (api chart)
  ↓
Rolling Update
```

### ベストプラクティス

#### イメージタグ管理

**推奨**: SHAタグ（`sha-{commit}`）を使用
- 不変性が保証される
- ロールバックが容易
- デプロイ履歴が明確

**非推奨**: `latest`タグ
- どのバージョンか不明確
- 予期しない変更が混入する可能性

```bash
# Good
./deployment/scripts/deploy.sh prod sha-329968d

# Bad
./deployment/scripts/deploy.sh prod latest
```

## アーキテクチャ図

### 全体構成

```
┌─────────────────────────────────────────────┐
│          インターネット                       │
└──────────────┬──────────────────────────────┘
               │ HTTPS
               ↓
┌─────────────────────────────────────────────┐
│    Cloudflare Tunnel Pod (本番のみ)          │
└──────────────┬──────────────────────────────┘
               │
               ↓
┌─────────────────────────────────────────────┐
│         Kubernetes (k3s Cluster)             │
│  ┌──────────────────────────────────────┐   │
│  │      Namespace: app                   │   │
│  │                                       │   │
│  │  ┌─────────────────────────────┐     │   │
│  │  │  API Deployment             │     │   │
│  │  │  ├─ Pod 1 (api-xxx)         │     │   │
│  │  │  └─ Pod 2 (api-yyy)         │     │   │
│  │  │    Image: home-kube:sha-xxx │     │   │
│  │  │    Port: 3000               │     │   │
│  │  │    Probes: /healthz         │     │   │
│  │  └──────────┬──────────────────┘     │   │
│  │             │                         │   │
│  │             ↓                         │   │
│  │  ┌─────────────────────────────┐     │   │
│  │  │  Service: api (ClusterIP)   │     │   │
│  │  │  DNS: api.app.svc.cluster.local   │   │
│  │  └──────────┬──────────────────┘     │   │
│  │             │                         │   │
│  │             │ PostgreSQL接続          │   │
│  │             ↓                         │   │
│  │  ┌─────────────────────────────┐     │   │
│  │  │  PostgreSQL StatefulSet     │     │   │
│  │  │  └─ Pod: postgres-0         │     │   │
│  │  │    Image: postgres:16-alpine│     │   │
│  │  │    Port: 5432               │     │   │
│  │  └──────────┬──────────────────┘     │   │
│  │             │                         │   │
│  │             ↓                         │   │
│  │  ┌─────────────────────────────┐     │   │
│  │  │  PVC (local-path)           │     │   │
│  │  │  Size: 5Gi (local) / 20Gi (prod)  │   │
│  │  └─────────────────────────────┘     │   │
│  └──────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

### データフロー

```
┌─────────┐      HTTP      ┌─────────┐
│ Client  │ ─────────────> │   API   │
└─────────┘                └────┬────┘
                                │
                                │ TypeORM
                                ↓
                          ┌──────────┐
                          │PostgreSQL│
                          └──────────┘
```

### デプロイフロー

```
┌──────────────┐
│ 開発者       │
└──────┬───────┘
       │ git push
       ↓
┌──────────────┐
│ GitHub       │
└──────┬───────┘
       │ webhook
       ↓
┌──────────────┐
│ GitHub Actions│
└──────┬───────┘
       │ docker build & push
       ↓
┌──────────────┐
│ Docker Hub   │
└──────┬───────┘
       │
       │ ./deploy.sh prod sha-xxx
       ↓
┌──────────────┐
│ Helm         │
└──────┬───────┘
       │ kubectl apply
       ↓
┌──────────────┐
│ k3s Cluster  │
└──────────────┘
```

## まとめ

### 主要な特徴

1. **モダンなスタック**: Hono + TypeORM + PostgreSQL
2. **コンテナ最適化**: マルチステージビルド、Distroless本番イメージ
3. **Kubernetes Native**: Helm管理、環境別values
4. **自動化されたCI/CD**: GitHub Actions、マルチアーキテクチャビルド
5. **セキュアな運用**: Secret管理、NetworkPolicy、最小権限

### node-appに関する注意点

**重要**: `node-app`は過去に使用されていた古いデプロイメント名です。

- 現在は`api`という名前で運用
- Kustomize → Helmへの移行に伴う名称変更
- クリーンアップスクリプトで削除推奨

もし`node-app`のPodが残っている場合は、古いリソースの削除が必要です：

```bash
kubectl -n default delete deployment node-app
kubectl -n default delete service node-app
```

詳細は [05-troubleshooting.md](05-troubleshooting.md) を参照してください。
