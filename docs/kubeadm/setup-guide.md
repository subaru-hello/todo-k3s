# kubeadmクラスタセットアップガイド

このガイドでは、kubeadmを使用してKubernetesクラスタ（シングルノード構成）を構築する手順を説明します。

## 目次

1. [システム要件](#システム要件)
2. [事前準備](#事前準備)
3. [containerdのインストール](#containerdのインストール)
4. [kubeadmのインストール](#kubeadmのインストール)
5. [Control Planeの初期化](#control-planeの初期化)
6. [Cilium CNIの導入](#cilium-cniの導入)
7. [Local Path Provisionerの導入](#local-path-provisionerの導入)
8. [動作確認](#動作確認)

---

## システム要件

- **OS**: Ubuntu 20.04/22.04, Debian 11/12, RHEL 8/9, Rocky Linux 8/9
- **CPU**: 2コア以上
- **メモリ**: 2GB以上（推奨4GB以上）
- **ディスク**: 20GB以上の空き容量
- **ネットワーク**: インターネット接続
- **権限**: rootまたはsudo権限

---

## 事前準備

### 1. スワップの無効化

Kubernetesはスワップが無効化されている必要があります。

```bash
# スワップを一時的に無効化
sudo swapoff -a

# 永続的に無効化（/etc/fstabからスワップエントリを削除またはコメントアウト）
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

### 2. カーネルモジュールの読み込み

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

### 3. sysctlパラメータの設定

```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

### 4. ファイアウォール設定（必要に応じて）

以下のポートを開放します：

- **Control Plane**:
  - 6443: Kubernetes API Server
  - 2379-2380: etcd
  - 10250: Kubelet API
  - 10259: kube-scheduler
  - 10257: kube-controller-manager

```bash
# UFWの場合
sudo ufw allow 6443/tcp
sudo ufw allow 2379:2380/tcp
sudo ufw allow 10250/tcp
sudo ufw allow 10259/tcp
sudo ufw allow 10257/tcp

# firewalldの場合
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=2379-2380/tcp
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --permanent --add-port=10259/tcp
sudo firewall-cmd --permanent --add-port=10257/tcp
sudo firewall-cmd --reload
```

---

## containerdのインストール

### 1. Docker公式リポジトリからインストール（推奨）

```bash
# 依存パッケージのインストール
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release

# Docker GPGキーの追加
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Dockerリポジトリの追加
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# containerdのインストール
sudo apt-get update
sudo apt-get install -y containerd.io
```

### 2. containerdの設定

```bash
# デフォルト設定を生成
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# SystemdCgroupを有効化（重要！）
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# containerdを再起動
sudo systemctl restart containerd
sudo systemctl enable containerd

# 動作確認
sudo systemctl status containerd
```

---

## kubeadmのインストール

### 1. Kubernetes公式リポジトリの追加

```bash
# パッケージリストの更新と必要なパッケージのインストール
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# Kubernetes GPGキーの追加
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Kubernetesリポジトリの追加（v1.31）
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

### 2. kubeadm、kubelet、kubectlのインストール

```bash
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# バージョン確認
kubeadm version
kubelet --version
kubectl version --client
```

---

## Control Planeの初期化

### 1. kubeadm initの実行

```bash
# Pod CIDRを指定してControl Planeを初期化（Ciliumは10.244.0.0/16を推奨）
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# 出力例：
# Your Kubernetes control-plane has initialized successfully!
#
# To start using your cluster, you need to run the following as a regular user:
#   mkdir -p $HOME/.kube
#   sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
#   sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 2. kubeconfigの設定

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 3. Control PlaneノードでのPodスケジューリングを有効化

シングルノード構成の場合、Control PlaneノードでもPodをスケジュールできるようにtaintを削除します。

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# 確認
kubectl get nodes
# NAME     STATUS     ROLES           AGE   VERSION
# node1    NotReady   control-plane   1m    v1.31.x
```

**注意**: ノードのSTATUSは`NotReady`です。これはCNIがまだインストールされていないためです。

---

## Cilium CNIの導入

### 1. Cilium CLIのインストール

```bash
# 最新バージョンを取得
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi

# Cilium CLIをダウンロード
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

# バージョン確認
cilium version --client
```

### 2. Ciliumのインストール

```bash
# CiliumをKubernetesクラスタにインストール
cilium install --version 1.16.5

# インストール状況の確認
cilium status --wait

# 出力例：
#     /¯¯\
#  /¯¯\__/¯¯\    Cilium:             OK
#  \__/¯¯\__/    Operator:           OK
#  /¯¯\__/¯¯\    Envoy DaemonSet:    disabled (using embedded mode)
#  \__/¯¯\__/    Hubble Relay:       disabled
#     \__/       ClusterMesh:        disabled
```

### 3. Ciliumの接続テスト（オプション）

```bash
cilium connectivity test
```

### 4. ノードのステータス確認

```bash
kubectl get nodes
# NAME     STATUS   ROLES           AGE   VERSION
# node1    Ready    control-plane   5m    v1.31.x
```

ノードが`Ready`になっていればCNIが正常に動作しています。

---

## Local Path Provisionerの導入

k3sと同じLocal Path Provisionerをkubeadmクラスタにインストールします。

### 1. Local Path Provisionerのインストール

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
```

### 2. StorageClassの確認

```bash
kubectl get storageclass
# NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
# local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  30s
```

### 3. デフォルトStorageClassの設定（必要に応じて）

```bash
# local-pathをデフォルトStorageClassに設定
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### 4. Local Path Provisionerの設定確認

デフォルトではPVは`/opt/local-path-provisioner`に作成されます。変更する場合：

```bash
kubectl -n local-path-storage get configmap local-path-config -o yaml
```

必要に応じてConfigMapを編集：

```bash
kubectl -n local-path-storage edit configmap local-path-config
```

---

## 動作確認

### 1. ノードとPodの確認

```bash
# ノード確認
kubectl get nodes -o wide

# システムPodの確認
kubectl get pods -A

# 全てのPodがRunningになっていることを確認
```

### 2. テストPodのデプロイ

```bash
# テストPodを作成
kubectl run test-nginx --image=nginx:alpine

# Pod状態確認
kubectl get pods

# Podの詳細確認
kubectl describe pod test-nginx

# テストPodの削除
kubectl delete pod test-nginx
```

### 3. PVCのテスト

```bash
# テスト用のPVCを作成
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
EOF

# PVC状態確認（WaitForFirstConsumerのため、Podがマウントするまでは"Pending"）
kubectl get pvc test-pvc

# テストPodでPVCをマウント
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-pvc
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: test-pvc
EOF

# PVC状態確認（Boundになる）
kubectl get pvc test-pvc

# クリーンアップ
kubectl delete pod test-pod-pvc
kubectl delete pvc test-pvc
```

---

## 次のステップ

クラスタのセットアップが完了したら、以下を実施してください：

1. **アプリケーションのデプロイ**: 既存のHelm Chartsを使用してアプリケーションをデプロイ
   ```bash
   ./deployment/scripts/deploy.sh prod [IMAGE_TAG]
   ```

2. **Cloudflare Tunnelのデプロイ**: 外部アクセスを有効化
   ```bash
   kubectl apply -f deployment/cloudflare-tunnel/
   ```

3. **モニタリングの設定（オプション）**:
   - Prometheus
   - Grafana
   - Hubble（Ciliumの可視化ツール）

---

## トラブルシューティング

問題が発生した場合は、[troubleshooting.md](./troubleshooting.md)を参照してください。

---

## 参考リンク

- [Kubernetes公式ドキュメント - kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Cilium公式ドキュメント](https://docs.cilium.io/)
- [Local Path Provisioner GitHub](https://github.com/rancher/local-path-provisioner)
- [containerd公式ドキュメント](https://containerd.io/)
