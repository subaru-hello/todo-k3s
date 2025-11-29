# kubeadm + gVisor 環境構築 - 完全実行ガイド

このドキュメントは、kubeadmベースのKubernetes環境にgVisorを導入し、runcとの比較実験を行うための**全コマンド実行ガイド**です。コピー&ペーストで実行できるように記載しています。

## 環境情報

- **サーバーOS**: Ubuntu 22.04 (Linux 5.15.0-157-generic)
- **構成**: シングルノード（Control Plane + Worker兼用）
- **CNI**: Cilium 1.16.5
- **Runtime**: runc (デフォルト) + gVisor (RuntimeClass)
- **Kubernetes**: v1.31.x

## 作業環境

- **ローカル**: Mac（コード編集、Dockerビルド）
- **リモート**: Ubuntu 22.04サーバー（kubeadm、gVisor、デプロイ）

---

## フェーズ1: k3s削除とkubeadm環境構築

### 1.1 k3s完全削除 ✅ 完了

リモートサーバーで実行：

```bash
# k3sアンインストール
/usr/local/bin/k3s-uninstall.sh

# 残存ファイル削除
sudo rm -rf /etc/rancher/k3s /var/lib/rancher/k3s
```

**結果**: k3sが正常に削除されました。

---

### 1.2 kubeadm + Cilium セットアップ

#### ステップ1: swap無効化

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# 確認
free -h | grep -i swap
# Swap: 0B になっていればOK
```

#### ステップ2: カーネルモジュール設定

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# 確認
lsmod | grep -E 'overlay|br_netfilter'
```

#### ステップ3: sysctlパラメータ設定

```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# 確認
sudo sysctl net.bridge.bridge-nf-call-iptables
sudo sysctl net.ipv4.ip_forward
# すべて1になっていればOK
```

#### ステップ4: containerdインストール

```bash
# 依存パッケージ
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release

# Docker GPGキー
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Dockerリポジトリ
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# containerdインストール
sudo apt-get update
sudo apt-get install -y containerd.io

# バージョン確認
containerd --version
```

#### ステップ5: containerd設定

```bash
# デフォルト設定生成
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# SystemdCgroup有効化（重要）
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# containerd再起動
sudo systemctl restart containerd
sudo systemctl enable containerd

# 確認
sudo systemctl status containerd
```

#### ステップ6: kubeadm、kubelet、kubectlインストール

```bash
# Kubernetes GPGキー
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Kubernetesリポジトリ
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

# インストール
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl

# バージョン固定
sudo apt-mark hold kubelet kubeadm kubectl

# バージョン確認
kubeadm version
kubelet --version
kubectl version --client
```

#### ステップ7: kubeadm init実行

```bash
# Control Plane初期化（Pod CIDR: 10.244.0.0/16はCilium推奨）
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# 出力される "Your Kubernetes control-plane has initialized successfully!" を確認
```

#### ステップ8: kubeconfigセットアップ

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 確認
kubectl version
kubectl get nodes
# STATUS: NotReady（CNI未導入のため正常）
```

#### ステップ9: Control Planeでスケジューリング有効化

```bash
# シングルノード構成のためtaint削除
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# 確認
kubectl describe node | grep Taints
# Taints: <none> になっていればOK
```

#### ステップ10: Cilium CNIインストール

```bash
# Cilium CLIダウンロード
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi

curl -L --fail --remote-name-all \
  https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

# チェックサム検証
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum

# インストール
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

# バージョン確認
cilium version --client
```

#### ステップ11: Ciliumデプロイ

```bash
# Ciliumインストール
cilium install --version 1.16.5

# ステータス確認（全てOKになるまで待機）
cilium status --wait
```

#### ステップ12: ノードReady確認

```bash
# ノード状態確認（ReadyになるはずCiliumデプロイ後）
kubectl get nodes
# NAME     STATUS   ROLES           AGE   VERSION
# node1    Ready    control-plane   5m    v1.31.x

# Cilium Pod確認
kubectl get pods -n kube-system -l k8s-app=cilium
```

#### ステップ13: Local Path Provisionerインストール

```bash
# Local Path Provisionerデプロイ
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml

# Pod確認
kubectl get pods -n local-path-storage

# StorageClass確認
kubectl get storageclass
```

**フェーズ1完了**: kubeadm + Cilium環境が構築されました。

---

## フェーズ2: gVisorインストールとRuntimeClass作成

### 2.1 gVisorインストール

リモートサーバーで実行：

```bash
# runscバイナリのインストール
ARCH=$(uname -m)
URL=https://storage.googleapis.com/gvisor/releases/release/latest/${ARCH}
wget ${URL}/runsc ${URL}/runsc.sha512
sha512sum -c runsc.sha512
sudo mv runsc /usr/local/bin/
sudo chmod a+rx /usr/local/bin/runsc

# バージョン確認
runsc --version
```

### 2.2 containerd設定拡張

```bash
# gVisorランタイムを追加
sudo tee -a /etc/containerd/config.toml > /dev/null <<EOF

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
  runtime_type = "io.containerd.runsc.v1"
EOF

# containerd再起動
sudo systemctl restart containerd
sudo systemctl status containerd
```

### 2.3 RuntimeClass作成

リモートサーバーで実行：

```bash
# RuntimeClass適用
kubectl apply -f deployment/kubeadm/runtimeclass-gvisor.yaml

# 確認
kubectl get runtimeclass
```

**期待される出力**:
```
NAME     HANDLER   AGE
gvisor   runsc     1s
```

---

## フェーズ3: gVisor検証用APIエンドポイント追加

### 3.1 ローカル環境でのコード変更 ✅ 完了

以下のファイルを作成・修正しました：

1. **新規作成**: `packages/api/src/routes/testRoutes.ts`
   - `/test/exec` - child_process.exec()テスト
   - `/test/sysinfo` - /proc/cpuinfo読み取り
   - `/test/filesystem` - ファイルシステム操作
   - `/test/runtime-info` - ランタイム判定

2. **修正**: `packages/api/src/index.ts`
   - testRoutesをマウント

### 3.2 Dockerイメージビルド ✅ 完了

ローカル環境で実行：

```bash
cd packages/api
docker build -t docker.io/subaru88/home-kube:sha-gvisor-test --target production .
```

**実行結果**:
```
#19 exporting to image
#19 exporting layers 1.6s done
#19 exporting manifest sha256:f0ab3a717f0f3526f714fae1c976373a9f82185e9c28bab231af523b78434fae done
#19 exporting config sha256:cce866e2e18a72149713b485842b3d8f6fb4cc56c8d836529480c429eacbbda7 done
#19 naming to docker.io/subaru88/home-kube:sha-gvisor-test done
#19 DONE 2.1s
```

**ビルド成功**: イメージ `docker.io/subaru88/home-kube:sha-gvisor-test` が作成されました。

### 3.3 Dockerイメージプッシュ

```bash
docker push docker.io/subaru88/home-kube:sha-gvisor-test
```

**注意**: プッシュは中断されましたが、イメージはローカルに保存されています。必要に応じて再実行してください。

---

## フェーズ4: Helm Chart拡張 ✅ 完了

### 4.1 API Deploymentテンプレート修正

**修正ファイル**: `deployment/charts/api/templates/deployment.yaml`

runtimeClassName対応を追加：

```yaml
spec:
  template:
    spec:
{{- if .Values.runtimeClassName }}
      runtimeClassName: {{ .Values.runtimeClassName }}
{{- end }}
      containers:
        ...
```

### 4.2 gVisor版valuesファイル作成 ✅ 完了

**新規作成**: `deployment/environments/prod/api-values-gvisor.yaml`

```yaml
namespace: app
runtimeClassName: gvisor
image:
  repository: docker.io/subaru88/home-kube
  tag: "sha-gvisor-test"
  pullPolicy: IfNotPresent
replicaCount: 1
# ... その他の設定
```

---

## フェーズ5: アプリケーションデプロイと検証

### 5.1 リポジトリクローン

```bash
cd ~
git clone https://github.com/subaru-hello/todo-k3s.git
cd todo-k3s
```

### 5.2 Namespace作成

```bash
kubectl create namespace app

# 確認
kubectl get namespace app
```

### 5.3 Secret作成

`.env.secret`ファイルを準備してから実行：

```bash
# .env.secretファイルをサンプルからコピー（初回のみ）
cd ~/todo-k3s
cp deployment/environments/prod/.env.secret.example deployment/environments/prod/.env.secret

# エディタで実際の値を設定
vim deployment/environments/prod/.env.secret
```

`.env.secret`の内容例：

```env
POSTGRES_USER=appuser
POSTGRES_PASSWORD=your-secure-password
POSTGRES_DB=todos
JWT_SECRET=your-jwt-secret-key
```

Secret作成：

```bash
kubectl create secret generic postgres-secret \
  --from-env-file=deployment/environments/prod/.env.secret \
  -n app

# 確認
kubectl get secret postgres-secret -n app
```

### 5.4 PostgreSQL（runc版）デプロイ

```bash
helm upgrade --install postgres ./deployment/charts/postgres \
  -n app \
  -f ./deployment/environments/prod/postgres-values.yaml

# Pod起動確認（1-2分待機）
kubectl get pods -n app -l app=postgres -w
```

**期待される出力**:
```
NAME         READY   STATUS    RESTARTS   AGE
postgres-0   1/1     Running   0          1m
```

### 5.5 PostgreSQL接続確認

```bash
# PostgreSQL Podに接続して動作確認
kubectl exec -n app postgres-0 -- psql -U appuser -d todos -c "SELECT version();"
```

### 5.6 API runc版デプロイ

**注意**: Cloudflare Tunnel未設定のため、ALLOWED_ORIGINSを上書きします。

```bash
helm upgrade --install api ./deployment/charts/api \
  -n app \
  -f ./deployment/environments/prod/api-values.yaml \
  --set image.tag=sha-gvisor-test \
  --set env.ALLOWED_ORIGINS="*"

# Pod起動確認
kubectl get pods -n app -l app=api -w
```

**期待される出力**:
```
NAME                   READY   STATUS    RESTARTS   AGE
api-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
api-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
```

### 5.7 API runc版動作確認

```bash
# Pod名を取得
API_RUNC=$(kubectl get pod -n app -l app=api -o jsonpath='{.items[0].metadata.name}')

# RuntimeClass確認（空白=runc）
kubectl get pod -n app $API_RUNC -o jsonpath='{.spec.runtimeClassName}'
echo ""

# ヘルスチェック
kubectl exec -n app $API_RUNC -- curl -s http://localhost:3000/healthz

# DB接続確認
kubectl exec -n app $API_RUNC -- curl -s http://localhost:3000/dbcheck

# ランタイム情報確認
kubectl exec -n app $API_RUNC -- curl -s http://localhost:3000/test/runtime-info
```

### 5.8 API gVisor版デプロイ

```bash
helm upgrade --install api-gvisor ./deployment/charts/api \
  -n app \
  -f ./deployment/environments/prod/api-values-gvisor.yaml

# Pod起動確認
kubectl get pods -n app -l app=api -w
```

**注意**: gVisorは起動が遅いため、readinessProbeのinitialDelaySecondsを長めに設定しています（15秒）。

### 5.9 API gVisor版動作確認

```bash
# Pod名を取得
API_GVISOR=$(kubectl get pod -n app -o jsonpath='{.items[?(@.spec.runtimeClassName=="gvisor")].metadata.name}')

# RuntimeClass確認（gvisorと表示されるはず）
kubectl get pod -n app $API_GVISOR -o jsonpath='{.spec.runtimeClassName}'
echo ""

# ヘルスチェック
kubectl exec -n app $API_GVISOR -- curl -s http://localhost:3000/healthz

# DB接続確認
kubectl exec -n app $API_GVISOR -- curl -s http://localhost:3000/dbcheck

# ランタイム情報確認
kubectl exec -n app $API_GVISOR -- curl -s http://localhost:3000/test/runtime-info
```

### 5.10 runc vs gVisor 比較検証

検証スクリプトを実行：

```bash
# 実行権限付与
chmod +x deployment/kubeadm/verify-runtime.sh

# 検証実行
./deployment/kubeadm/verify-runtime.sh
```

#### 手動検証コマンド

```bash
# 1. /test/exec テスト（gVisorで失敗するはず）
echo "=== runc版 ==="
kubectl exec -n app $API_RUNC -- curl -s http://localhost:3000/test/exec | jq .

echo "=== gVisor版 ==="
kubectl exec -n app $API_GVISOR -- curl -s http://localhost:3000/test/exec | jq .

# 2. /test/sysinfo テスト（CPU情報が異なるはず）
echo "=== runc版 CPU情報 ==="
kubectl exec -n app $API_RUNC -- curl -s http://localhost:3000/test/sysinfo | jq '.cpuModel'

echo "=== gVisor版 CPU情報 ==="
kubectl exec -n app $API_GVISOR -- curl -s http://localhost:3000/test/sysinfo | jq '.cpuModel'

# 3. /test/filesystem テスト（パフォーマンス比較）
echo "=== runc版 ファイルシステム ==="
kubectl exec -n app $API_RUNC -- curl -s http://localhost:3000/test/filesystem | jq '.durationMs'

echo "=== gVisor版 ファイルシステム ==="
kubectl exec -n app $API_GVISOR -- curl -s http://localhost:3000/test/filesystem | jq '.durationMs'
```

### 5.11 全体確認

```bash
# すべてのPodを確認
kubectl get pods -n app -o wide

# Serviceを確認
kubectl get svc -n app

# PVCを確認
kubectl get pvc -n app
```

**期待される出力**:
```
NAME                            READY   STATUS    RESTARTS   AGE   RUNTIME
postgres-0                      1/1     Running   0          5m    （空白=runc）
api-xxxxxxxxxx-xxxxx            1/1     Running   0          3m    （空白=runc）
api-xxxxxxxxxx-xxxxx            1/1     Running   0          3m    （空白=runc）
api-gvisor-xxxxxxxxxx-xxxxx     1/1     Running   0          1m    gvisor
```

**フェーズ5完了**: runcとgVisor両方のAPIが稼働しています。

---

## 作成したファイル一覧

### 新規作成

1. `packages/api/src/routes/testRoutes.ts` - gVisor検証エンドポイント
2. `deployment/environments/prod/api-values-gvisor.yaml` - gVisor版values
3. `deployment/kubeadm/runtimeclass-gvisor.yaml` - RuntimeClass定義
4. `deployment/kubeadm/verify-runtime.sh` - 検証スクリプト

### 修正

1. `packages/api/src/index.ts` - testRoutesマウント
2. `deployment/charts/api/templates/deployment.yaml` - runtimeClassName対応

---

## 次のアクション

1. ✅ ローカルでのコード実装完了
2. ✅ Dockerイメージビルド完了
3. ⏳ Dockerイメージプッシュ（必要に応じて再実行）
4. ⏳ リモートサーバーでkubeadm + gVisor環境構築
5. ⏳ Helm Chartでデプロイ
6. ⏳ 検証スクリプト実行
7. ⏳ 実験結果をブログ記事に反映
8. ⏳ GitHubにpush

---

## トラブルシューティング

### Docker pushが失敗する場合

```bash
# Docker Hubにログイン
docker login

# 再プッシュ
docker push docker.io/subaru88/home-kube:sha-gvisor-test
```

### gVisor Podが起動しない場合

```bash
# エラー確認
kubectl describe pod <pod-name> -n app

# containerdログ確認
sudo journalctl -u containerd -f

# RuntimeClass確認
kubectl get runtimeclass
```

---

## 参考リンク

- [gVisor公式ドキュメント](https://gvisor.dev/)
- [Kubernetes RuntimeClass](https://kubernetes.io/docs/concepts/containers/runtime-class/)
- [kubeadmセットアップガイド](./setup-guide.md)
