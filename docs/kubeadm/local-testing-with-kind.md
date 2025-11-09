# kindを使ったローカルテスト環境セットアップガイド

このガイドでは、**kind（Kubernetes in Docker）**を使用して、ローカル環境でkubeadmベースのKubernetesクラスタを構築し、リモート環境と同じ構成で動作確認する方法を説明します。

## 目次

1. [kindとは](#kindとは)
2. [前提条件](#前提条件)
3. [kindのインストール](#kindのインストール)
4. [kindクラスタの作成](#kindクラスタの作成)
5. [Cilium CNIのインストール](#cilium-cniのインストール)
6. [Local Path Provisionerのインストール](#local-path-provisionerのインストール)
7. [アプリケーションのデプロイ](#アプリケーションのデプロイ)
8. [動作確認](#動作確認)
9. [リモート環境への移行](#リモート環境への移行)
10. [クリーンアップ](#クリーンアップ)

---

## kindとは

**kind（Kubernetes in Docker）** は、Dockerコンテナの中でKubernetesクラスタを実行するツールです。

### kindの特徴

- **内部でkubeadmを使用**: kindはDockerコンテナ内で**kubeadm**を使ってクラスタを構築するため、リモート環境のkubeadmクラスタと同じ構成になります
- **軽量で高速**: VMを使わず、Dockerコンテナで動作するため起動が速い
- **複数クラスタ対応**: 複数のクラスタを同時に実行可能
- **マルチノード対応**: Control PlaneとWorkerノードの複数ノード構成も可能

### なぜkindを使うのか？

リモート環境で直接kubeadmクラスタを構築する前に、ローカルで以下を確認できます：

- Helm Chartsが正しくデプロイできるか
- Cilium CNIが正常に動作するか
- Local Path Provisionerでストレージが使えるか
- NetworkPolicyが期待通りに機能するか
- アプリケーションが正常に起動するか

**ローカルで動作確認できたら、リモート環境でも同じように動作します！**

---

## 前提条件

### 必要なソフトウェア

- **Docker Desktop** (macOS/Windows) または **Docker Engine** (Linux)
  - バージョン: 20.10以上
  - 確認: `docker version`

- **kubectl**
  - バージョン: 1.28以上
  - 確認: `kubectl version --client`

### リソース要件

Docker Desktopのリソース設定（推奨）：

- **CPU**: 4コア以上
- **メモリ**: 4GB以上（推奨: 8GB）
- **ディスク**: 20GB以上の空き容量

設定方法（macOS）：
```
Docker Desktop → Settings → Resources → CPU/Memory を調整
```

---

## kindのインストール

### macOS

```bash
# Homebrewを使用
brew install kind

# バージョン確認
kind version
```

### Linux

```bash
# 最新バージョンをダウンロード
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.25.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# バージョン確認
kind version
```

### その他のOS

公式サイトを参照: https://kind.sigs.k8s.io/docs/user/quick-start/#installation

---

## kindクラスタの作成

### 1. kind設定ファイルの作成

リモート環境と同じ構成（Cilium CNI使用）でkindクラスタを作成するため、設定ファイルを準備します。

```bash
# プロジェクトルートで作業
cd /Users/s30764/Personal/todo-k3s

# kind設定ファイルを作成
cat <<EOF > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: todo-k3s-test
nodes:
  - role: control-plane
    extraPortMappings:
      # APIポートを30000番にマッピング（localhost:30000からアクセス可能）
      - containerPort: 30000
        hostPort: 30000
        protocol: TCP
networking:
  # デフォルトCNIを無効化（Ciliumを使用するため）
  disableDefaultCNI: true
  # Pod CIDR（Ciliumの推奨設定）
  podSubnet: "10.244.0.0/16"
  # Service CIDR
  serviceSubnet: "10.96.0.0/12"
EOF
```

**設定のポイント**:
- `disableDefaultCNI: true`: kindのデフォルトCNI（kindnet）を無効化し、Ciliumを使用
- `podSubnet: "10.244.0.0/16"`: リモート環境のkubeadmと同じPod CIDR
- `extraPortMappings`: APIをlocalhost:30000で公開（後でポートフォワード用）

### 2. kindクラスタの作成

```bash
# クラスタ作成（1-2分かかります）
kind create cluster --config kind-config.yaml

# 出力例：
# Creating cluster "todo-k3s-test" ...
#  ✓ Ensuring node image (kindest/node:v1.31.4) 🖼
#  ✓ Preparing nodes 📦
#  ✓ Writing configuration 📜
#  ✓ Starting control-plane 🕹️
# Set kubectl context to "kind-todo-k3s-test"
# You can now use your cluster with:
# kubectl cluster-info --context kind-todo-k3s-test
```

### 3. kubectlコンテキストの確認

```bash
# 現在のコンテキスト確認
kubectl config current-context
# kind-todo-k3s-test

# ノード確認（NotReadyは正常 - CNIがまだない）
kubectl get nodes
# NAME                          STATUS     ROLES           AGE   VERSION
# todo-k3s-test-control-plane   NotReady   control-plane   1m    v1.31.4
```

**注意**: ノードが`NotReady`なのは、CNI（Cilium）がまだインストールされていないためです。これは正常な状態です。

---

## Cilium CNIのインストール

リモート環境と同じCiliumをインストールします。

### 1. Cilium CLIのインストール

すでにインストール済みの場合はスキップしてください。

```bash
# macOS
brew install cilium-cli

# Linux
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

# バージョン確認
cilium version --client
```

### 2. Ciliumのインストール

```bash
# Ciliumをkindクラスタにインストール
cilium install --version 1.16.5

# インストール状況の確認（完了まで1-2分）
cilium status --wait

# 期待される出力：
#     /¯¯\
#  /¯¯\__/¯¯\    Cilium:             OK
#  \__/¯¯\__/    Operator:           OK
#  /¯¯\__/¯¯\    Envoy DaemonSet:    disabled (using embedded mode)
#  \__/¯¯\__/    Hubble Relay:       disabled
#     \__/       ClusterMesh:        disabled
```

### 3. ノードのステータス確認

```bash
kubectl get nodes
# NAME                          STATUS   ROLES           AGE   VERSION
# todo-k3s-test-control-plane   Ready    control-plane   5m    v1.31.4
```

ノードが`Ready`になっていれば成功です！

### 4. Ciliumの接続テスト（オプション）

```bash
# Ciliumの接続テストを実行（5-10分かかります）
cilium connectivity test

# テストをスキップする場合は Ctrl+C
```

---

## Local Path Provisionerのインストール

リモート環境と同じLocal Path Provisionerをインストールします。

```bash
# Local Path Provisionerのデプロイ
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml

# Podの起動確認
kubectl get pods -n local-path-storage

# StorageClassの確認
kubectl get storageclass
# NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
# local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  30s
```

これでリモート環境と同じ`local-path` StorageClassが使用可能になりました。

---

## アプリケーションのデプロイ

既存のHelm Charts（`deployment/charts/*`）を使用してアプリケーションをデプロイします。

### 1. Namespaceの作成

```bash
kubectl create namespace app
```

### 2. Secretの作成

ローカル環境用の設定値を使用してSecretを作成します。

```bash
# Secretを直接作成（ローカルテスト用の値）
kubectl create secret generic postgres-secret \
  --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PASSWORD=localpassword \
  --from-literal=POSTGRES_DB=tododb \
  --from-literal=JWT_SECRET=local-test-jwt-secret-key-12345 \
  -n app
```

### 3. PostgreSQLのデプロイ

```bash
cd deployment

# PostgreSQL Helmチャートをデプロイ（local環境用）
helm install postgres ./charts/postgres \
  -f environments/local/postgres-values.yaml \
  -n app

# Pod起動確認（1-2分かかります）
kubectl get pods -n app -w
# Ctrl+C で停止

# 期待される出力：
# NAME         READY   STATUS    RESTARTS   AGE
# postgres-0   1/1     Running   0          2m
```

### 4. APIのデプロイ

```bash
# API Helmチャートをデプロイ（local環境用）
helm install api ./charts/api \
  -f environments/local/api-values.yaml \
  -n app

# Pod起動確認
kubectl get pods -n app

# 期待される出力：
# NAME                   READY   STATUS    RESTARTS   AGE
# postgres-0             1/1     Running   0          3m
# api-xxxxxxxxxx-xxxxx   1/1     Running   0          1m
```

### 5. PVCの確認

```bash
# PVCがBindされていることを確認
kubectl get pvc -n app
# NAME                  STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# postgres-pgdata-0     Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   5Gi        RWO            local-path     3m

# PVも確認
kubectl get pv
```

---

## 動作確認

### 1. Pod/Service/PVCの確認

```bash
# 全リソースの確認
kubectl get all,pvc -n app

# 期待される出力：
# NAME                       READY   STATUS    RESTARTS   AGE
# pod/postgres-0             1/1     Running   0          5m
# pod/api-xxxxxxxxxx-xxxxx   1/1     Running   0          3m
#
# NAME               TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
# service/postgres   ClusterIP   10.96.xxx.xxx   <none>        5432/TCP   5m
# service/api        ClusterIP   10.96.xxx.xxx   <none>        3000/TCP   3m
#
# NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
# deployment.apps/api   1/1     1            1           3m
#
# NAME                             DESIRED   CURRENT   READY   AGE
# replicaset.apps/api-xxxxxxxxxx   1         1         1       3m
#
# NAME                        READY   AGE
# statefulset.apps/postgres   1/1     5m
#
# NAME                                STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# persistentvolumeclaim/postgres-pgdata-0   Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   5Gi        RWO            local-path     5m
```

### 2. ネットワーク接続テスト

```bash
# APIからPostgreSQLへの接続確認
kubectl exec -n app deployment/api -- nc -zv postgres.app.svc.cluster.local 5432
# postgres.app.svc.cluster.local (10.96.xxx.xxx:5432) open

# PostgreSQLの疎通確認
kubectl exec -n app postgres-0 -- pg_isready -U postgres
# /var/run/postgresql:5432 - accepting connections
```

### 3. API Healthcheckの確認

```bash
# API Podのヘルスチェック
kubectl exec -n app deployment/api -- curl -f http://localhost:3000/healthz
# {"status":"ok"}
```

### 4. ポートフォワードでローカルアクセス

```bash
# APIをlocalhost:3000にポートフォワード
kubectl port-forward -n app service/api 3000:3000

# 別のターミナルで確認
curl http://localhost:3000/healthz
# {"status":"ok"}

# ユーザー登録テスト
curl -X POST http://localhost:3000/register \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","email":"test@example.com","password":"testpass123"}'

# ログインテスト
curl -X POST http://localhost:3000/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"testpass123"}'
# {"token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."}

# Ctrl+C でポートフォワードを停止
```

### 5. NetworkPolicyの確認

```bash
# NetworkPolicyの確認
kubectl get networkpolicy -n app
kubectl describe networkpolicy -n app postgres-network-policy

# NetworkPolicyが機能しているか確認（外部からの接続は失敗するはず）
kubectl run test-pod --image=busybox --rm -it -- nc -zv postgres.app.svc.cluster.local 5432
# nc: postgres.app.svc.cluster.local (10.96.xxx.xxx:5432): Connection timed out
# ← これが期待される結果（NetworkPolicyでブロックされている）

# API Podからは接続できることを確認
kubectl exec -n app deployment/api -- nc -zv postgres.app.svc.cluster.local 5432
# postgres.app.svc.cluster.local (10.96.xxx.xxx:5432) open
# ← APIからは接続できる（NetworkPolicyで許可されている）
```

### 6. Ciliumエンドポイントの確認

```bash
# Ciliumのエンドポイント確認
kubectl exec -n kube-system ds/cilium -- cilium endpoint list

# NetworkPolicyの状態確認
kubectl exec -n kube-system ds/cilium -- cilium policy get
```

---

## リモート環境への移行

ローカル環境（kind）で動作確認ができたら、リモート環境に同じ構成を適用できます。

### ローカル環境とリモート環境の違い

| 項目 | ローカル（kind） | リモート（kubeadm） |
|-----|-----------------|-------------------|
| クラスタ構築方法 | `kind create cluster` | `kubeadm init` |
| CNI | Cilium | Cilium（同じ） |
| StorageClass | Local Path Provisioner | Local Path Provisioner（同じ） |
| Helm Charts | 同じ | 同じ |
| 環境変数（values） | `environments/local/` | `environments/prod/` |
| 外部公開 | Port Forward | Cloudflare Tunnel |

### 移行手順

1. **リモートサーバーでkubeadmクラスタを構築**
   - [setup-guide.md](./setup-guide.md) に従ってkubeadmクラスタを構築
   - Cilium CNI、Local Path Provisionerをインストール

2. **Helm Chartsのデプロイ**
   - ローカルで動作確認済みのHelm Chartsをそのままデプロイ
   - valuesファイルを`environments/prod/`に変更するだけ

3. **Cloudflare Tunnelのデプロイ**
   - ローカルでは不要だったCloudflare Tunnelを追加

詳細は[migration-plan.md](./migration-plan.md)を参照してください。

---

## クリーンアップ

### アプリケーションの削除

```bash
# Helmリリースの削除
helm uninstall -n app api
helm uninstall -n app postgres

# Namespaceの削除
kubectl delete namespace app
```

### kindクラスタの削除

```bash
# kindクラスタを削除
kind delete cluster --name todo-k3s-test

# クラスタリストの確認（空になる）
kind get clusters
```

### kind設定ファイルの削除

```bash
# プロジェクトルートのkind-config.yamlを削除
rm kind-config.yaml
```

---

## トラブルシューティング

### Podが起動しない

```bash
# Podの詳細確認
kubectl describe pod -n app [POD_NAME]

# ログ確認
kubectl logs -n app [POD_NAME]

# イベント確認
kubectl get events -n app --sort-by='.lastTimestamp'
```

### Docker Desktopのリソース不足

**症状**: Podが`Pending`や`OOMKilled`になる

**解決方法**:
```
Docker Desktop → Settings → Resources
- CPU: 4コア以上
- Memory: 8GB以上
に増やす
```

### kindクラスタが作成できない

```bash
# Dockerが起動しているか確認
docker ps

# 既存のkindクラスタを削除
kind delete cluster --name todo-k3s-test

# 再作成
kind create cluster --config kind-config.yaml
```

### Ciliumが起動しない

```bash
# Cilium Podのログ確認
kubectl logs -n kube-system -l k8s-app=cilium

# Ciliumの再インストール
cilium uninstall
cilium install --version 1.16.5
```

詳細は[troubleshooting.md](./troubleshooting.md)を参照してください。

---

## まとめ

kindを使うことで、リモート環境のkubeadmクラスタと同じ構成をローカルで簡単にテストできます。

### ローカルで確認できたこと

- ✅ Helm Chartsが正しくデプロイできる
- ✅ Cilium CNIが正常に動作する
- ✅ Local Path Provisionerでストレージが使える
- ✅ NetworkPolicyが期待通りに機能する
- ✅ アプリケーションが正常に起動する
- ✅ APIとPostgreSQLが正常に通信できる

### 次のステップ

ローカルで動作確認ができたら、以下のドキュメントに従ってリモート環境に適用してください：

1. [setup-guide.md](./setup-guide.md) - kubeadmクラスタのセットアップ
2. [migration-plan.md](./migration-plan.md) - k3sからの移行手順
3. [troubleshooting.md](./troubleshooting.md) - トラブルシューティング

**ローカルで動作したものは、リモートでも動作します！**

---

## 参考リンク

- [kind公式ドキュメント](https://kind.sigs.k8s.io/)
- [kindとCiliumの統合](https://docs.cilium.io/en/stable/installation/kind/)
- [Kubernetes公式ドキュメント](https://kubernetes.io/docs/)
