# k3sからkubeadmへの移行計画

このドキュメントでは、既存のk3sクラスタからkubeadmベースのKubernetesクラスタへの移行手順を説明します。

## 目次

1. [移行概要](#移行概要)
2. [現状分析](#現状分析)
3. [移行前の準備](#移行前の準備)
4. [移行手順](#移行手順)
5. [移行後の検証](#移行後の検証)
6. [ロールバック計画](#ロールバック計画)

---

## 移行概要

### 移行の目的

- k3sからkubeadmへの標準的なKubernetes環境への移行
- より柔軟なクラスタ管理とカスタマイズ性の向上
- Cilium CNIの採用によるネットワーク機能の強化

### 移行方式

**方式**: クラスタ再構築方式

- 既存k3sクラスタは停止せず、新しいkubeadmクラスタを構築
- アプリケーションデータは移行せず、新規に初期化
- Helm Chartsを使用して同じ構成を再デプロイ

### ダウンタイム

- **想定ダウンタイム**: 30分〜1時間
  - kubeadmクラスタ構築: 10-15分
  - アプリケーションデプロイ: 5-10分
  - 動作確認とDNS切り替え: 10-15分

---

## 現状分析

### 現在のk3s環境

#### デプロイ構成
- **Namespace**: app
- **アプリケーション**: Todo API（Hono + TypeORM）
- **データベース**: PostgreSQL 16（StatefulSet）
- **デプロイ方式**: Helm Charts
- **外部公開**: Cloudflare Tunnel

#### リソース構成
| リソース種別 | 名前 | 説明 |
|------------|------|------|
| StatefulSet | postgres | PostgreSQL 16 |
| Deployment | api | Todo API（2レプリカ） |
| Service | postgres | ClusterIP（5432） |
| Service | api | ClusterIP（3000） |
| Secret | postgres-secret | DB認証情報、JWT_SECRET |
| PVC | postgres-pgdata-0 | PostgreSQLデータ（20Gi） |
| Deployment | cloudflared | Cloudflare Tunnel |
| Secret | cloudflared-secret | Tunnel認証情報 |
| NetworkPolicy | postgres-network-policy | APIからのみDB接続許可 |

#### k3s特有の機能使用状況

| 機能 | 使用状況 | kubeadm移行時の対応 |
|-----|---------|-------------------|
| Local Path Provisioner | ✅ 使用中（StorageClass: `local-path`） | 手動導入が必要 |
| Traefik Ingress | ❌ 未使用 | 影響なし |
| ServiceLB | ❌ 未使用（全てClusterIP） | 影響なし |
| containerd | ✅ 使用中 | kubeadmでも継続使用 |

### 移行が必要な設定

#### 1. StorageClass（最重要）
- **現在**: `local-path`（k3s標準）
- **移行後**: `local-path`（手動導入）
- **対応**: Local Path Provisionerマニフェストを適用

#### 2. CNI
- **現在**: Flannel（k3s標準）
- **移行後**: Cilium
- **対応**: Cilium CLIでインストール、NetworkPolicy機能を有効化

#### 3. コンテナランタイム
- **現在**: containerd（k3s組み込み）
- **移行後**: containerd（個別インストール）
- **対応**: containerdをパッケージマネージャーでインストール

---

## 移行前の準備

### 1. データバックアップ（オプション）

本番環境でデータ保護が必要な場合は、以下の手順でバックアップを取得してください。

#### PostgreSQLデータのバックアップ

```bash
# k3sクラスタでPostgreSQL Podを特定
kubectl get pods -n app -l app=postgres

# pg_dumpでバックアップ
kubectl exec -n app postgres-0 -- pg_dumpall -U postgres > backup_$(date +%Y%m%d_%H%M%S).sql

# バックアップファイルの確認
ls -lh backup_*.sql
```

#### Kubernetes Secretのバックアップ

```bash
# Secretのエクスポート
kubectl get secret -n app postgres-secret -o yaml > postgres-secret-backup.yaml
kubectl get secret -n cloudflare-tunnel cloudflared-secret -o yaml > cloudflared-secret-backup.yaml
```

### 2. 現在の設定情報の記録

```bash
# デプロイ済みリソースの一覧を保存
kubectl get all -n app -o wide > k3s-resources.txt
kubectl get pvc -n app -o yaml > k3s-pvc.yaml
kubectl get secret -n app -o yaml > k3s-secrets.yaml
kubectl get networkpolicy -n app -o yaml > k3s-networkpolicy.yaml
```

### 3. イメージタグの確認

```bash
# 現在デプロイされているイメージタグを確認
kubectl get deployment -n app api -o jsonpath='{.spec.template.spec.containers[0].image}'

# 出力例: docker.io/subaru88/home-kube:sha-329968d
```

### 4. 必要なファイルの準備

以下のファイルがリモートサーバーに存在することを確認：

```bash
# リポジトリのクローン（sparse-checkout使用）
git clone --filter=blob:none --sparse https://github.com/[YOUR_USERNAME]/todo-k3s.git
cd todo-k3s
git sparse-checkout set deployment

# .env.secretファイルの準備（本番環境）
cp deployment/environments/prod/.env.secret.example deployment/environments/prod/.env.secret
# エディタで実際の値を設定
vim deployment/environments/prod/.env.secret
```

### 5. Cloudflare Tunnel認証情報の確認

```bash
# 既存のCloudflare Tunnel認証情報を確認
kubectl get secret -n cloudflare-tunnel cloudflared-secret -o jsonpath='{.data.credentials\.json}' | base64 -d > credentials.json
kubectl get secret -n cloudflare-tunnel cloudflared-secret -o jsonpath='{.data.config\.yaml}' | base64 -d > config.yaml
```

---

## 移行手順

### ステップ1: k3sクラスタの停止（オプション）

データの不整合を避けるため、移行中はk3sクラスタを停止することを推奨します。

```bash
# k3sサービスの停止
sudo systemctl stop k3s

# k3sのアンインストール（完全にクリーンアップする場合）
/usr/local/bin/k3s-uninstall.sh
```

**注意**: k3sをアンインストールすると、全てのPodとデータが削除されます。バックアップを確認してから実行してください。

### ステップ2: kubeadmクラスタのセットアップ

詳細は[setup-guide.md](./setup-guide.md)を参照してください。

#### 2.1 事前準備

```bash
# スワップ無効化
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# カーネルモジュール
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# sysctlパラメータ
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
```

#### 2.2 containerdのインストール

```bash
# Dockerリポジトリの追加
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# containerdのインストール
sudo apt-get update
sudo apt-get install -y containerd.io

# containerdの設定
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd
```

#### 2.3 kubeadmのインストール

```bash
# Kubernetesリポジトリの追加
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# kubeadm、kubelet、kubectlのインストール
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

#### 2.4 Control Planeの初期化

```bash
# kubeadm init（Cilium用にPod CIDR指定）
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# kubeconfigの設定
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Control Planeでのスケジューリングを有効化
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

#### 2.5 Cilium CNIのインストール

```bash
# Cilium CLIのインストール
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

# Ciliumのインストール
cilium install --version 1.16.5
cilium status --wait

# ノードがReadyになることを確認
kubectl get nodes
```

#### 2.6 Local Path Provisionerのインストール

```bash
# Local Path Provisionerのデプロイ
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml

# StorageClassの確認
kubectl get storageclass
```

### ステップ3: アプリケーションのデプロイ

#### 3.1 Namespaceの作成

```bash
kubectl create namespace app
```

#### 3.2 Secretの作成（本番環境）

```bash
cd ~/todo-k3s/deployment

# .env.secretファイルから環境変数を読み込んでSecretを作成
source environments/prod/.env.secret
kubectl create secret generic postgres-secret \
  --from-literal=POSTGRES_USER=$POSTGRES_USER \
  --from-literal=POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
  --from-literal=POSTGRES_DB=$POSTGRES_DB \
  --from-literal=JWT_SECRET=$JWT_SECRET \
  -n app
```

#### 3.3 Helm Chartsのデプロイ

```bash
# デプロイスクリプトを使用（推奨）
./scripts/deploy.sh prod sha-329968d

# または手動でHelm install
helm install postgres ./charts/postgres \
  -f environments/prod/postgres-values.yaml \
  -n app

helm install api ./charts/api \
  -f environments/prod/api-values.yaml \
  --set image.tag=sha-329968d \
  -n app
```

#### 3.4 Podの起動確認

```bash
# Pod状態の確認
kubectl get pods -n app -w

# 期待される出力（数分後）：
# NAME                   READY   STATUS    RESTARTS   AGE
# postgres-0             1/1     Running   0          2m
# api-xxxxxxxxxx-xxxxx   1/1     Running   0          1m
# api-xxxxxxxxxx-xxxxx   1/1     Running   0          1m
```

### ステップ4: Cloudflare Tunnelのデプロイ

#### 4.1 Namespaceの作成

```bash
kubectl create namespace cloudflare-tunnel
```

#### 4.2 Secretの作成

```bash
# 既存の認証情報を使用
kubectl create secret generic cloudflared-secret \
  --from-file=credentials.json=./credentials.json \
  --from-file=config.yaml=./config.yaml \
  -n cloudflare-tunnel
```

#### 4.3 Cloudflare Tunnelのデプロイ

```bash
kubectl apply -f cloudflare-tunnel/deployment-prod.yaml
kubectl apply -f cloudflare-tunnel/config-prod.yaml

# Pod状態の確認
kubectl get pods -n cloudflare-tunnel
```

---

## 移行後の検証

### 1. Pod状態の確認

```bash
# 全Namespace
kubectl get pods -A

# appネームスペース
kubectl get pods -n app -o wide

# cloudflare-tunnelネームスペース
kubectl get pods -n cloudflare-tunnel
```

### 2. Serviceの確認

```bash
kubectl get svc -n app
```

### 3. PVCとPVの確認

```bash
# PVC
kubectl get pvc -n app

# PV
kubectl get pv

# PostgreSQLデータの確認
kubectl exec -n app postgres-0 -- psql -U postgres -c "\l"
```

### 4. ネットワーク接続テスト

```bash
# APIからPostgreSQLへの接続テスト
kubectl exec -n app deployment/api -- nc -zv postgres.app.svc.cluster.local 5432

# API Healthcheck
kubectl exec -n app deployment/api -- curl -f http://localhost:3000/healthz
```

### 5. NetworkPolicyの確認

```bash
kubectl get networkpolicy -n app

# 外部からの接続テスト（失敗するはず）
kubectl run test-pod --image=busybox --rm -it -- nc -zv postgres.app.svc.cluster.local 5432
# 結果: 接続タイムアウト（NetworkPolicyにより拒否される）
```

### 6. 外部アクセステスト

```bash
# Cloudflare Tunnel経由でのアクセステスト
curl -I https://api.octomblog.com/healthz

# 期待される出力: HTTP/2 200
```

### 7. アプリケーション機能テスト

```bash
# ユーザー登録
curl -X POST https://api.octomblog.com/register \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","email":"test@example.com","password":"testpass123"}'

# ログイン
curl -X POST https://api.octomblog.com/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"testpass123"}'

# Todoの作成（JWT tokenを使用）
curl -X POST https://api.octomblog.com/todos \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{"title":"Test Todo","description":"Migration test"}'
```

---

## ロールバック計画

移行後に問題が発生した場合のロールバック手順です。

### シナリオ1: kubeadmクラスタに問題がある場合

k3sクラスタを停止していない場合は、k3sを再起動します。

```bash
# k3sの起動
sudo systemctl start k3s

# Pod状態確認
sudo k3s kubectl get pods -A
```

### シナリオ2: k3sをアンインストール済みの場合

k3sを再インストールし、バックアップからリストアします。

```bash
# k3sの再インストール
curl -sfL https://get.k3s.io | sh -

# kubeconfigの設定
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Secretのリストア
kubectl apply -f postgres-secret-backup.yaml
kubectl apply -f cloudflared-secret-backup.yaml

# Helm Chartsのデプロイ
./deployment/scripts/deploy.sh prod [IMAGE_TAG]

# PostgreSQLデータのリストア（必要な場合）
kubectl exec -n app postgres-0 -- psql -U postgres < backup_YYYYMMDD_HHMMSS.sql
```

### シナリオ3: データ損失が発生した場合

バックアップからデータをリストアします。

```bash
# PostgreSQL Podへのバックアップファイル転送
kubectl cp backup_YYYYMMDD_HHMMSS.sql app/postgres-0:/tmp/

# データベースのリストア
kubectl exec -n app postgres-0 -- psql -U postgres < /tmp/backup_YYYYMMDD_HHMMSS.sql

# リストア確認
kubectl exec -n app postgres-0 -- psql -U postgres -c "SELECT COUNT(*) FROM users;"
```

---

## チェックリスト

移行作業の進捗管理に使用してください。

### 移行前準備
- [ ] PostgreSQLデータのバックアップ（必要な場合）
- [ ] Kubernetes Secretのバックアップ
- [ ] 現在のリソース設定の記録
- [ ] イメージタグの確認
- [ ] .env.secretファイルの準備
- [ ] Cloudflare Tunnel認証情報の確認

### kubeadmクラスタ構築
- [ ] スワップ無効化
- [ ] カーネルモジュールとsysctl設定
- [ ] containerdのインストールと設定
- [ ] kubeadm、kubelet、kubectlのインストール
- [ ] kubeadm initの実行
- [ ] kubeconfigの設定
- [ ] Control Planeのtaint削除

### CNIとストレージ
- [ ] Cilium CLIのインストール
- [ ] Ciliumのインストールと確認
- [ ] ノードがReadyになることを確認
- [ ] Local Path Provisionerのインストール
- [ ] StorageClassの確認

### アプリケーションデプロイ
- [ ] Namespaceの作成（app）
- [ ] Secretの作成（postgres-secret）
- [ ] PostgreSQL StatefulSetのデプロイ
- [ ] API Deploymentのデプロイ
- [ ] Podの起動確認
- [ ] PVCのBound確認

### Cloudflare Tunnel
- [ ] Namespaceの作成（cloudflare-tunnel）
- [ ] Secretの作成（cloudflared-secret）
- [ ] Cloudflare Tunnelのデプロイ
- [ ] Podの起動確認

### 検証
- [ ] 全Pod状態の確認
- [ ] Serviceの確認
- [ ] PVCとPVの確認
- [ ] ネットワーク接続テスト
- [ ] NetworkPolicyの動作確認
- [ ] 外部アクセステスト
- [ ] アプリケーション機能テスト

### 後処理
- [ ] k3s関連ファイルのクリーンアップ（必要な場合）
- [ ] ドキュメントの更新
- [ ] モニタリング設定

---

## 参考情報

### 所要時間の目安

| 作業項目 | 所要時間 |
|---------|---------|
| 事前準備（バックアップ等） | 10分 |
| kubeadmクラスタ構築 | 15分 |
| CNIとストレージ導入 | 10分 |
| アプリケーションデプロイ | 10分 |
| Cloudflare Tunnelデプロイ | 5分 |
| 検証とテスト | 15分 |
| **合計** | **約65分** |

### リソース要件

kubeadmクラスタは、k3sよりも若干多くのリソースを消費します。

| コンポーネント | CPU | メモリ |
|-------------|-----|-------|
| Control Plane | 200m〜 | 512Mi〜 |
| Cilium | 100m〜 | 256Mi〜 |
| Local Path Provisioner | 10m | 64Mi |
| アプリケーション（既存） | 300m | 768Mi |
| **合計** | **610m〜** | **1.6Gi〜** |

---

## まとめ

この移行計画に従うことで、k3sからkubeadmへの安全な移行が可能です。移行作業中に問題が発生した場合は、[troubleshooting.md](./troubleshooting.md)を参照するか、ロールバック手順を実施してください。
