# GitHub Actions ワークフロー

このディレクトリには、CI/CDパイプライン用のGitHub Actionsワークフローが含まれています。

## 📁 ワークフロー一覧

### `build-and-push.yml`

API（packages/api/）の変更を検知して、自動的にDockerイメージをビルド・pushします。

**トリガー**:
- `main` ブランチへのpush（packages/api/ の変更時）
- 手動実行（workflow_dispatch）

**処理内容**:
1. リポジトリをチェックアウト
2. Docker Buildx セットアップ
3. Docker Hub へログイン（DOCKER_USERNAME, DOCKER_PASSWORD）
4. メタデータ抽出（タグ、ラベル）
5. マルチアーキテクチャビルド（amd64, arm64）
6. Docker Hub へ push
7. ビルド結果をサマリーに出力

**生成されるイメージタグ**:
- `sha-{commit}`: コミットハッシュ（短縮形）
- `main`: mainブランチ
- `latest`: mainブランチの最新（デフォルトブランチの場合のみ）

## 🔧 セットアップ

### 1. GitHub Secrets の設定

GitHubリポジトリの Settings → Secrets and variables → Actions で以下を設定：

```
DOCKER_USERNAME: Docker Hubのユーザー名
DOCKER_PASSWORD: Docker Hub Personal Access Token (PAT)
```

**Docker Hub PATの取得方法**:
1. https://hub.docker.com/settings/security にアクセス
2. "New Access Token" をクリック
3. Description: `github-actions-todo-api`
4. Permissions: `Read & Write`
5. "Generate" → トークンをコピー

### 2. ワークフローの有効化

リポジトリの Actions タブで、ワークフローが有効になっていることを確認。

## 🚀 使い方

### 自動実行（推奨）

```bash
# 開発PC
cd packages/api
# コード編集
git add .
git commit -m "feat: add new endpoint"
git push origin main

# GitHub Actions が自動実行される
```

### 手動実行

1. GitHub → Actions タブ
2. "Build and Push Docker Image" をクリック
3. "Run workflow" ボタン
4. ブランチを選択（デフォルト: main）
5. （オプション）Custom image tag を入力
6. "Run workflow" を実行

### デプロイ（別サーバー）

```bash
# 1. GitHub Actions完了を確認
# GitHub → Actions → 成功したワークフローを確認

# 2. イメージタグを確認
# ワークフローの Summary から "Docker Image Published" セクションを確認

# 3. 別サーバーでデプロイ
cd /path/to/todo-k3s
git pull
sudo nerdctl -n k8s.io pull docker.io/subaru88/home-kube:sha-abc1234
./deployment/scripts/deploy.sh prod sha-abc1234
```

## 🔍 トラブルシューティング

### ワークフローが実行されない

**原因**: `packages/api/` 以外の変更
```yaml
# build-and-push.yml の paths で制限
paths:
  - 'packages/api/**'
```

**解決**: 手動実行するか、packages/api/ を変更

### Docker Hub 認証エラー

```
Error: buildx failed with: error: failed to solve: failed to authorize:
failed to fetch oauth token: 401 Unauthorized
```

**原因**: DOCKER_USERNAME または DOCKER_PASSWORD が間違っている

**解決**:
1. GitHub Settings → Secrets → Actions
2. DOCKER_PASSWORD を再設定（新しいPATを生成）

### ビルドエラー

```
Error: failed to solve: failed to read dockerfile:
open /tmp/buildkit-mount.../Dockerfile: no such file or directory
```

**原因**: Dockerfileのパスが間違っている

**解決**: `build-and-push.yml` の `context` と `file` を確認
```yaml
with:
  context: ./packages/api
  file: ./packages/api/Dockerfile
```

### マルチアーキテクチャビルドが遅い

**原因**: amd64とarm64の両方をビルドしているため

**対策（一時的）**:
```yaml
# platforms を1つに絞る（開発中のみ）
platforms: linux/amd64
```

### キャッシュが効かない

**確認**:
```yaml
cache-from: type=gha
cache-to: type=gha,mode=max
```

**対策**:
- Actions → Caches でキャッシュサイズを確認
- 10GBを超える場合は古いキャッシュが削除されている可能性

## 📊 ワークフロー実行履歴

### 確認方法

1. GitHub → Actions タブ
2. "Build and Push Docker Image" をクリック
3. 実行履歴を確認

### ログの確認

1. 該当のワークフロー実行をクリック
2. "build-and-push" ジョブをクリック
3. 各ステップのログを展開

### サマリーの確認

ワークフロー実行後、Summaryに以下が表示されます：

```markdown
### 🐳 Docker Image Published

**Registry:** `docker.io/subaru88/home-kube`

**Tags:**
```
docker.io/subaru88/home-kube:sha-abc1234
docker.io/subaru88/home-kube:main
docker.io/subaru88/home-kube:latest
```

**デプロイコマンド例:**
```bash
sudo nerdctl -n k8s.io pull docker.io/subaru88/home-kube:sha-abc1234
./deployment/scripts/deploy.sh prod sha-abc1234
```
```

## 🔐 セキュリティ

### Secrets の管理

- ✅ GitHub Secrets に保存（暗号化）
- ✅ コードには一切含まれない
- ✅ ログにマスキングされて表示
- ❌ PRのフォークからは参照不可（セキュリティ）

### 権限の最小化

Docker Hub PATは **Read & Write** のみ：
- ✅ イメージの読み書き
- ❌ アカウント設定の変更不可
- ❌ 他のリポジトリへのアクセス不可

### イメージの署名（将来対応）

```yaml
# Docker Content Trust (DCT) の有効化
- name: Sign image
  env:
    DOCKER_CONTENT_TRUST: 1
  run: docker push $IMAGE
```

## 📚 参考

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Docker Build Push Action](https://github.com/docker/build-push-action)
- [Docker Metadata Action](https://github.com/docker/metadata-action)
- [GitHub Actions Cache](https://docs.github.com/en/actions/using-workflows/caching-dependencies-to-speed-up-workflows)
