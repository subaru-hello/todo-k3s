# kubeadmクラスタ トラブルシューティングガイド

このドキュメントでは、kubeadmクラスタの構築・運用中に発生する可能性のある問題と、その解決方法を説明します。

## 目次

1. [kubeadm init関連](#kubeadm-init関連)
2. [containerd関連](#containerd関連)
3. [CNI（Cilium）関連](#cnicilium関連)
4. [Pod起動エラー](#pod起動エラー)
5. [ストレージ関連](#ストレージ関連)
6. [ネットワーク関連](#ネットワーク関連)
7. [アプリケーション関連](#アプリケーション関連)
8. [一般的なトラブルシューティング手順](#一般的なトラブルシューティング手順)

---

## kubeadm init関連

### エラー: [ERROR CRI]: container runtime is not running

**症状**:
```
[ERROR CRI]: container runtime is not running: output: time="..." level=fatal msg="validate service connection: validate CRI v1 runtime API for endpoint \"unix:///var/run/containerd/containerd.sock\": rpc error: code = Unimplemented desc = unknown service runtime.v1.RuntimeService"
```

**原因**: containerdの設定でCRI pluginが無効化されている

**解決方法**:
```bash
# containerd設定ファイルの再生成
sudo rm /etc/containerd/config.toml
sudo containerd config default | sudo tee /etc/containerd/config.toml

# SystemdCgroupを有効化
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# containerdを再起動
sudo systemctl restart containerd
sudo systemctl status containerd

# kubeadm initを再試行
sudo kubeadm reset -f
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
```

### エラー: [ERROR Swap]: running with swap on is not supported

**症状**:
```
[ERROR Swap]: running with swap on is not supported. Please disable swap
```

**原因**: スワップが有効になっている

**解決方法**:
```bash
# スワップを無効化
sudo swapoff -a

# 永続的に無効化
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# 確認
free -h
# Swap行が全て0になっていることを確認
```

### エラー: [ERROR Port-6443]: Port 6443 is in use

**症状**:
```
[ERROR Port-6443]: Port 6443 is in use
```

**原因**: 以前のkubeadm initが完全にクリーンアップされていない

**解決方法**:
```bash
# kubeadm resetでクリーンアップ
sudo kubeadm reset -f

# 関連プロセスの確認と停止
sudo systemctl stop kubelet
sudo systemctl stop containerd

# ポート使用状況の確認
sudo lsof -i :6443
sudo netstat -tulpn | grep 6443

# 必要に応じてプロセスを強制終了
sudo kill -9 [PID]

# containerdとkubeletを再起動
sudo systemctl start containerd
sudo systemctl start kubelet

# kubeadm initを再試行
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
```

### エラー: [ERROR FileContent--proc-sys-net-bridge-bridge-nf-call-iptables]

**症状**:
```
[ERROR FileContent--proc-sys-net-bridge-bridge-nf-call-iptables]: /proc/sys/net/bridge/bridge-nf-call-iptables does not exist
```

**原因**: カーネルモジュール `br_netfilter` がロードされていない

**解決方法**:
```bash
# カーネルモジュールのロード
sudo modprobe br_netfilter
sudo modprobe overlay

# 永続化
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# sysctlパラメータの設定
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# 確認
lsmod | grep br_netfilter
cat /proc/sys/net/bridge/bridge-nf-call-iptables
# 1が出力されればOK
```

---

## containerd関連

### エラー: failed to load cni during init

**症状**:
```
Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox "...": plugin type="..." failed (add): failed to load cni config
```

**原因**: CNIプラグインがまだインストールされていない

**解決方法**:

これは正常な状態です。Ciliumをインストールすることで解決します。

```bash
# Ciliumのインストール
cilium install --version 1.16.5
cilium status --wait

# ノードがReadyになることを確認
kubectl get nodes
```

### エラー: containerdサービスが起動しない

**症状**:
```bash
sudo systemctl status containerd
# Active: failed
```

**解決方法**:
```bash
# ログの確認
sudo journalctl -xeu containerd

# 設定ファイルの文法エラーをチェック
sudo containerd config dump

# 設定ファイルを再生成
sudo rm /etc/containerd/config.toml
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# containerdを再起動
sudo systemctl restart containerd
sudo systemctl enable containerd
```

---

## CNI（Cilium）関連

### エラー: ノードがNotReadyのまま

**症状**:
```bash
kubectl get nodes
# NAME     STATUS     ROLES           AGE   VERSION
# node1    NotReady   control-plane   10m   v1.31.x
```

**原因**: CNI（Cilium）がまだインストールされていない、または正常に動作していない

**解決方法**:
```bash
# Ciliumの状態確認
cilium status

# Cilium Podの確認
kubectl get pods -n kube-system -l k8s-app=cilium

# Cilium Podのログ確認
kubectl logs -n kube-system -l k8s-app=cilium --all-containers=true

# Ciliumの再インストール（必要な場合）
cilium uninstall
cilium install --version 1.16.5
cilium status --wait

# ノード状態の確認
kubectl get nodes
```

### エラー: Cilium Podが起動しない

**症状**:
```bash
kubectl get pods -n kube-system -l k8s-app=cilium
# NAME          READY   STATUS             RESTARTS   AGE
# cilium-xxxxx  0/1     CrashLoopBackOff   5          5m
```

**解決方法**:
```bash
# Cilium Podのログを確認
kubectl logs -n kube-system cilium-xxxxx

# 一般的な問題と対処：

# 1. カーネルバージョンが古い
uname -r
# 5.x以上を推奨

# 2. BPFファイルシステムがマウントされていない
mount | grep /sys/fs/bpf
# 出力がない場合：
sudo mount bpffs -t bpf /sys/fs/bpf

# 3. Ciliumの再インストール
cilium uninstall
kubectl delete namespace cilium

# Pod CIDRを明示的に指定して再インストール
cilium install --version 1.16.5 \
  --set ipam.mode=kubernetes \
  --set tunnel=vxlan

cilium status --wait
```

### NetworkPolicyが機能しない

**症状**: NetworkPolicyを作成しても、通信が制限されない

**解決方法**:
```bash
# CiliumでNetworkPolicyが有効になっているか確認
kubectl get ciliumnetworkpolicies -A
kubectl get networkpolicies -A

# Cilium agentの設定確認
kubectl exec -n kube-system cilium-xxxxx -- cilium config | grep policy

# Ciliumの接続テストでNetworkPolicyをテスト
cilium connectivity test

# NetworkPolicyのデバッグ
kubectl describe networkpolicy -n app postgres-network-policy

# Ciliumのエンドポイント確認
kubectl exec -n kube-system cilium-xxxxx -- cilium endpoint list
```

---

## Pod起動エラー

### エラー: ImagePullBackOff

**症状**:
```bash
kubectl get pods -n app
# NAME                   READY   STATUS             RESTARTS   AGE
# api-xxxxxxxxxx-xxxxx   0/1     ImagePullBackOff   0          2m
```

**解決方法**:
```bash
# Podの詳細確認
kubectl describe pod -n app api-xxxxxxxxxx-xxxxx

# イメージ名とタグを確認
kubectl get deployment -n app api -o jsonpath='{.spec.template.spec.containers[0].image}'

# containerdでイメージをpull試行
sudo nerdctl pull docker.io/subaru88/home-kube:sha-329968d

# または
sudo ctr image pull docker.io/subaru88/home-kube:sha-329968d

# イメージタグが間違っている場合は、Helm valuesを修正して再デプロイ
helm upgrade api ./charts/api \
  -f environments/prod/api-values.yaml \
  --set image.tag=sha-329968d \
  -n app
```

### エラー: CrashLoopBackOff

**症状**:
```bash
kubectl get pods -n app
# NAME                   READY   STATUS             RESTARTS   AGE
# api-xxxxxxxxxx-xxxxx   0/1     CrashLoopBackOff   3          2m
```

**解決方法**:
```bash
# Podのログを確認
kubectl logs -n app api-xxxxxxxxxx-xxxxx

# 以前のコンテナのログを確認
kubectl logs -n app api-xxxxxxxxxx-xxxxx --previous

# よくある原因：

# 1. 環境変数が設定されていない
kubectl exec -n app api-xxxxxxxxxx-xxxxx -- env | grep POSTGRES

# Secretの確認
kubectl get secret -n app postgres-secret -o yaml

# 2. PostgreSQLに接続できない
kubectl exec -n app api-xxxxxxxxxx-xxxxx -- nc -zv postgres.app.svc.cluster.local 5432

# 3. アプリケーションのエラー
kubectl logs -n app api-xxxxxxxxxx-xxxxx | tail -n 50
```

### エラー: Pending

**症状**:
```bash
kubectl get pods -n app
# NAME         READY   STATUS    RESTARTS   AGE
# postgres-0   0/1     Pending   0          5m
```

**解決方法**:
```bash
# Podの詳細を確認
kubectl describe pod -n app postgres-0

# よくある原因：

# 1. PVCがBindされていない
kubectl get pvc -n app
kubectl describe pvc -n app postgres-pgdata-0

# StorageClassの確認
kubectl get storageclass

# Local Path Provisionerが動作しているか確認
kubectl get pods -n local-path-storage

# 2. リソース不足
kubectl describe node
# Allocated resourcesセクションを確認

# 3. Node Selectorやtaintの問題
kubectl describe pod -n app postgres-0 | grep -A5 "Events:"
```

---

## ストレージ関連

### エラー: PVCがPendingのまま

**症状**:
```bash
kubectl get pvc -n app
# NAME                  STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# postgres-pgdata-0     Pending                                      local-path     5m
```

**解決方法**:
```bash
# PVCの詳細確認
kubectl describe pvc -n app postgres-pgdata-0

# StorageClassの確認
kubectl get storageclass local-path

# Local Path Provisionerの確認
kubectl get pods -n local-path-storage
kubectl logs -n local-path-storage -l app=local-path-provisioner

# StorageClassがない場合はインストール
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml

# WaitForFirstConsumerの場合、Podがスケジュールされるまでバインドされない
# これは正常な動作です。Podが起動すると自動的にBindされます。
```

### エラー: PVのマウントに失敗

**症状**:
```bash
kubectl describe pod -n app postgres-0
# Events:
#   Warning  FailedMount  5s  kubelet  MountVolume.SetUp failed for volume "pvc-xxxxx" : rpc error: code = Internal desc = failed to create directory /opt/local-path-provisioner/pvc-xxxxx: mkdir /opt/local-path-provisioner: permission denied
```

**解決方法**:
```bash
# ディレクトリの権限を確認
ls -ld /opt/local-path-provisioner

# ディレクトリが存在しない場合は作成
sudo mkdir -p /opt/local-path-provisioner
sudo chmod 755 /opt/local-path-provisioner

# SELinuxが有効な場合
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# Podを再作成
kubectl delete pod -n app postgres-0
# StatefulSetが自動的に再作成します
```

### Local Path Provisionerのパスを変更したい

**解決方法**:
```bash
# ConfigMapを編集
kubectl -n local-path-storage edit configmap local-path-config

# paths配下を変更
# paths: /opt/local-path-provisioner → /data/kubernetes/local-path

# 変更後、Local Path Provisioner Podを再起動
kubectl delete pod -n local-path-storage -l app=local-path-provisioner

# 新しいパスのディレクトリを作成
sudo mkdir -p /data/kubernetes/local-path
sudo chmod 755 /data/kubernetes/local-path
```

---

## ネットワーク関連

### エラー: PodからServiceに接続できない

**症状**:
```bash
kubectl exec -n app deployment/api -- curl -f http://postgres.app.svc.cluster.local:5432
# curl: (7) Failed to connect to postgres.app.svc.cluster.local port 5432: Connection refused
```

**解決方法**:
```bash
# 1. Serviceの確認
kubectl get svc -n app postgres
kubectl describe svc -n app postgres

# Endpointsの確認
kubectl get endpoints -n app postgres
# Endpointsが空の場合、Podのラベルが一致していない

# 2. Podのラベル確認
kubectl get pod -n app postgres-0 --show-labels

# 3. CoreDNSの動作確認
kubectl get pods -n kube-system -l k8s-app=kube-dns

# DNS解決テスト
kubectl run test-dns --image=busybox --rm -it -- nslookup postgres.app.svc.cluster.local

# 4. NetworkPolicyが通信をブロックしていないか確認
kubectl get networkpolicy -n app
kubectl describe networkpolicy -n app postgres-network-policy

# 5. Ciliumのエンドポイント確認
kubectl exec -n kube-system cilium-xxxxx -- cilium endpoint list
```

### エラー: 外部からCloudflare Tunnel経由でアクセスできない

**症状**:
```bash
curl -I https://api.octomblog.com/healthz
# curl: (7) Failed to connect to api.octomblog.com port 443: Connection refused
```

**解決方法**:
```bash
# 1. Cloudflare Tunnel Podの確認
kubectl get pods -n cloudflare-tunnel
kubectl logs -n cloudflare-tunnel -l app=cloudflared

# よくあるログエラー：
# "Cannot reach the origin service" → API ServiceまたはPodが起動していない
# "Authentication failed" → credentialsが間違っている

# 2. API Serviceの確認
kubectl get svc -n app api
kubectl get endpoints -n app api

# 3. Cloudflare Tunnel設定の確認
kubectl get configmap -n cloudflare-tunnel cloudflared-config -o yaml

# service項目が正しいか確認：
# http://api.app.svc.cluster.local:3000

# 4. API Podのヘルスチェック
kubectl exec -n app deployment/api -- curl -f http://localhost:3000/healthz

# 5. Cloudflare Dashboardでトンネル状態を確認
# https://dash.cloudflare.com/ → Zero Trust → Access → Tunnels
```

---

## アプリケーション関連

### エラー: PostgreSQLに接続できない

**症状**:
```bash
kubectl logs -n app api-xxxxxxxxxx-xxxxx
# Error: connect ECONNREFUSED postgres.app.svc.cluster.local:5432
```

**解決方法**:
```bash
# 1. PostgreSQL Podが起動しているか確認
kubectl get pods -n app -l app=postgres

# 2. PostgreSQL Serviceの確認
kubectl get svc -n app postgres

# 3. PostgreSQLへの接続テスト
kubectl exec -n app postgres-0 -- pg_isready -U postgres

# 4. 環境変数の確認
kubectl exec -n app deployment/api -- env | grep POSTGRES

# 期待される値：
# PGHOST=postgres.app.svc.cluster.local
# PGPORT=5432
# PGUSER=postgres
# PGPASSWORD=xxxxx
# PGDATABASE=tododb

# 5. Secretの確認
kubectl get secret -n app postgres-secret -o yaml

# 6. NetworkPolicyの確認
kubectl get networkpolicy -n app
# API PodにはNetworkPolicyで許可されているか確認

# 7. 手動接続テスト
kubectl exec -n app deployment/api -- nc -zv postgres.app.svc.cluster.local 5432
```

### エラー: JWTトークンが無効

**症状**:
```bash
curl -X POST https://api.octomblog.com/todos \
  -H "Authorization: Bearer xxx" \
  -d '{"title":"test"}'
# {"error": "Invalid token"}
```

**解決方法**:
```bash
# 1. JWT_SECRETが設定されているか確認
kubectl exec -n app deployment/api -- env | grep JWT_SECRET

# 2. Secretの確認
kubectl get secret -n app postgres-secret -o jsonpath='{.data.JWT_SECRET}' | base64 -d

# 3. API Podを再起動（環境変数を再読み込み）
kubectl rollout restart deployment -n app api

# 4. 新しいトークンを取得
curl -X POST https://api.octomblog.com/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"testpass123"}'
```

---

## 一般的なトラブルシューティング手順

### 基本的な確認コマンド

```bash
# 1. ノードの状態確認
kubectl get nodes -o wide
kubectl describe node [NODE_NAME]

# 2. 全Podの状態確認
kubectl get pods -A -o wide

# 3. システムPodの確認
kubectl get pods -n kube-system

# 4. イベントの確認
kubectl get events -A --sort-by='.lastTimestamp'

# 5. リソース使用状況
kubectl top nodes
kubectl top pods -A
```

### ログの確認方法

```bash
# Podのログ
kubectl logs -n [NAMESPACE] [POD_NAME]
kubectl logs -n [NAMESPACE] [POD_NAME] --previous  # 前回のコンテナ
kubectl logs -n [NAMESPACE] [POD_NAME] -f  # リアルタイム表示

# 複数コンテナのPodの場合
kubectl logs -n [NAMESPACE] [POD_NAME] -c [CONTAINER_NAME]

# システムログ
sudo journalctl -xeu kubelet
sudo journalctl -xeu containerd

# Ciliumのログ
kubectl logs -n kube-system -l k8s-app=cilium --all-containers=true
```

### デバッグ用の一時Pod

```bash
# ネットワークデバッグ用Pod
kubectl run debug-pod --image=nicolaka/netshoot -it --rm -- /bin/bash

# 基本的なデバッグPod
kubectl run debug-pod --image=busybox -it --rm -- sh

# 特定のNamespaceでデバッグPod起動
kubectl run debug-pod -n app --image=busybox -it --rm -- sh

# デバッグPod内での確認コマンド例：
# - DNS: nslookup postgres.app.svc.cluster.local
# - 接続: nc -zv postgres.app.svc.cluster.local 5432
# - HTTP: wget -O- http://api.app.svc.cluster.local:3000/healthz
```

### クリーンアップとリセット

```bash
# 特定のリソースを削除
kubectl delete pod -n app [POD_NAME]
kubectl delete pvc -n app [PVC_NAME]

# Namespaceごと削除
kubectl delete namespace app

# Helmリリースの削除
helm uninstall -n app postgres
helm uninstall -n app api

# kubeadmクラスタのリセット（完全にやり直す場合）
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d
sudo rm -rf /etc/kubernetes
sudo rm -rf /var/lib/etcd
sudo rm -rf /var/lib/kubelet
sudo rm -rf /var/lib/cni
sudo rm -rf ~/.kube

# Ciliumの完全削除
cilium uninstall
kubectl delete namespace cilium

# containerdのクリーンアップ
sudo systemctl stop containerd
sudo rm -rf /var/lib/containerd
sudo systemctl start containerd
```

---

## よくある質問（FAQ）

### Q1: kubeadm initに失敗した場合、どうすればいいですか？

```bash
# kubeadm resetでクリーンアップしてから再試行
sudo kubeadm reset -f
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
```

### Q2: Podが起動しない場合、どこから調査すべきですか？

優先順位：
1. `kubectl describe pod` でEventsを確認
2. `kubectl logs` でコンテナログを確認
3. `kubectl get events` でクラスタ全体のイベントを確認
4. ノードのリソース状況を確認

### Q3: Local Path Provisionerで作成されたPVを削除するには？

```bash
# PVCとPodを削除
kubectl delete pod -n app postgres-0
kubectl delete pvc -n app postgres-pgdata-0

# PVが自動削除されない場合
kubectl delete pv [PV_NAME]

# ホスト上のデータも削除
sudo rm -rf /opt/local-path-provisioner/pvc-xxxxx
```

### Q4: Ciliumを再インストールしたい

```bash
# Ciliumのアンインストール
cilium uninstall

# Namespaceも削除（クリーンアップ）
kubectl delete namespace cilium

# 再インストール
cilium install --version 1.16.5
cilium status --wait
```

---

## サポートとリソース

### 公式ドキュメント

- [Kubernetes公式ドキュメント](https://kubernetes.io/docs/)
- [kubeadmトラブルシューティング](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/)
- [Ciliumトラブルシューティング](https://docs.cilium.io/en/stable/operations/troubleshooting/)
- [Local Path Provisioner](https://github.com/rancher/local-path-provisioner)

### コミュニティリソース

- [Kubernetes Slack](https://kubernetes.slack.com/)
- [Cilium Slack](https://cilium.io/slack)
- [Stack Overflow - Kubernetes](https://stackoverflow.com/questions/tagged/kubernetes)

### デバッグに便利なツール

- `kubectl` plugins: [krew](https://krew.sigs.k8s.io/)
- `stern`: 複数Podのログを同時表示
- `k9s`: TUIベースのKubernetes管理ツール
- `cilium` CLI: Ciliumのデバッグツール

---

このトラブルシューティングガイドで解決しない問題がある場合は、上記の公式ドキュメントやコミュニティリソースを参照してください。
