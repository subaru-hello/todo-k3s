# トラブルシューティング

このドキュメントでは、Kubernetesクラスタの運用で遭遇する一般的な問題と解決方法をまとめています。

## 目次
- [kubectl接続エラー](#kubectl接続エラー)
- [Context管理](#context管理)
- [リモートサーバーへの接続](#リモートサーバーへの接続)
- [Pod起動の問題](#pod起動の問題)
- [ネットワークの問題](#ネットワークの問題)
- [ストレージの問題](#ストレージの問題)

## kubectl接続エラー

### エラー: Connection Refused

**症状**:
```bash
$ kubectl get pods
E1107 08:36:58.116451   35510 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"https://127.0.0.1:59300/api?timeout=32s\": dial tcp 127.0.0.1:59300: connect: connection refused"
The connection to the server 127.0.0.1:59300 was refused - did you specify the right host or port?
```

**原因**:
- kubectlが指しているKubernetesクラスタが存在しないか、停止している
- 誤ったkubectl contextが設定されている
- クラスタが起動していない

**解決方法**:

#### 1. 現在のcontextを確認

```bash
# 現在のcontext
kubectl config current-context

# 利用可能なcontext一覧
kubectl config get-contexts

# 出力例:
# CURRENT   NAME       CLUSTER    AUTHINFO   NAMESPACE
# *         minikube   minikube   minikube   default
#           k3s        k3s        k3s        default
```

#### 2. 正しいcontextに切り替え

```bash
# ローカル（minikube）に切り替え
kubectl config use-context minikube

# リモートサーバー（k3s）に切り替え
kubectl config use-context default  # k3sのデフォルトcontext名
```

#### 3. クラスタが起動しているか確認

**minikubeの場合**:
```bash
# minikube状態確認
minikube status

# 停止している場合は起動
minikube start
```

**リモートk3sの場合**:
```bash
# SSH経由で接続して確認
ssh octom@192.168.0.50
sudo systemctl status k3s

# 停止している場合は起動
sudo systemctl start k3s
```

#### 4. kubeconfig設定の確認

```bash
# kubeconfigファイルの内容を確認
kubectl config view

# 特定contextの詳細
kubectl config view --minify
```

**問題のある設定例**:
```yaml
clusters:
- cluster:
    server: https://127.0.0.1:59300  # ← 存在しないサーバー
  name: minikube
```

**解決策**: 正しいサーバーアドレスに修正または、contextを削除して再設定

```bash
# 問題のあるcontextを削除
kubectl config delete-context minikube
kubectl config delete-cluster minikube

# minikubeを再起動して設定を再生成
minikube delete
minikube start
```

## Context管理

### 複数のKubernetesクラスタを管理する

#### Context一覧の確認

```bash
# すべてのcontextを表示
kubectl config get-contexts

# 現在のcontextのみ表示
kubectl config current-context
```

#### Contextの切り替え

```bash
# minikube（ローカル）に切り替え
kubectl config use-context minikube

# リモートk3sに切り替え
kubectl config use-context default
```

#### 新しいContextの追加

```bash
# contextを手動で追加
kubectl config set-context my-k3s \
  --cluster=my-k3s-cluster \
  --user=my-k3s-user \
  --namespace=app

# 追加したcontextを使用
kubectl config use-context my-k3s
```

#### Contextの削除

```bash
# contextを削除
kubectl config delete-context old-context

# clusterとuser情報も削除
kubectl config delete-cluster old-cluster
kubectl config delete-user old-user
```

#### 環境変数でkubeconfigを切り替え

```bash
# 別のkubeconfigファイルを使用
export KUBECONFIG=~/.kube/k3s-remote.yaml

# 元に戻す
unset KUBECONFIG

# 複数のkubeconfigをマージ
export KUBECONFIG=~/.kube/config:~/.kube/k3s-remote.yaml
```

### Context名の分かりやすい管理

```bash
# Context名を変更
kubectl config rename-context minikube local-dev
kubectl config rename-context default k3s-remote

# Namespace付きでcontextを作成
kubectl config set-context local-dev \
  --cluster=minikube \
  --user=minikube \
  --namespace=app
```

## リモートサーバーへの接続

### オプション1: SSH経由でkubectlを使用（推奨）

最も簡単で安全な方法です。

```bash
# リモートサーバーにSSH
ssh octom@192.168.0.50

# リモートサーバー上でkubectlを実行
kubectl get pods -A
kubectl -n default get pods
```

**メリット**:
- 設定不要
- セキュア
- サーバーの状態を直接確認可能

**デメリット**:
- 毎回SSHが必要
- ローカルマシンから直接操作できない

### オプション2: リモートk3s kubeconfigをローカルに設定

ローカルマシンからリモートk3sクラスタに直接接続します。

#### ステップ1: リモートからkubeconfigを取得

```bash
# リモートサーバーのkubeconfigを取得
ssh octom@192.168.0.50 "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/k3s-remote.yaml

# パーミッション設定
chmod 600 ~/.kube/k3s-remote.yaml
```

#### ステップ2: サーバーアドレスを変更

k3sのkubeconfigは`127.0.0.1`を指しているため、リモートIPに変更します。

```bash
# 127.0.0.1をリモートサーバーIPに置換（macOS）
sed -i '' 's/127.0.0.1/192.168.0.50/g' ~/.kube/k3s-remote.yaml

# Linux
sed -i 's/127.0.0.1/192.168.0.50/g' ~/.kube/k3s-remote.yaml
```

#### ステップ3: kubeconfigを設定

**方法A: 環境変数で指定**
```bash
export KUBECONFIG=~/.kube/k3s-remote.yaml
kubectl get nodes

# 元に戻す
unset KUBECONFIG
```

**方法B: 既存のconfigにマージ**
```bash
# マージ
KUBECONFIG=~/.kube/config:~/.kube/k3s-remote.yaml \
  kubectl config view --flatten > ~/.kube/merged_config

# バックアップしてから置き換え
cp ~/.kube/config ~/.kube/config.backup
mv ~/.kube/merged_config ~/.kube/config

# contextを確認
kubectl config get-contexts

# k3s contextに切り替え
kubectl config use-context default  # k3sのデフォルトcontext名
```

#### ステップ4: 接続確認

```bash
# Node確認
kubectl get nodes

# Pod確認
kubectl get pods -A
```

**注意点**:
- ポート6443がファイアウォールで開放されている必要がある
- SSL証明書の検証が必要（k3sは自己署名証明書を使用）

### オプション3: kubectl proxyでトンネリング

```bash
# SSHトンネルを作成
ssh -L 6443:localhost:6443 octom@192.168.0.50

# 別ターミナルで
export KUBECONFIG=~/.kube/k3s-remote.yaml
kubectl get nodes
```

## Pod起動の問題

### ImagePullBackOff

**症状**:
```bash
$ kubectl get pods -n app
NAME       READY   STATUS             RESTARTS   AGE
api-xxx    0/1     ImagePullBackOff   0          2m
```

**原因**:
- イメージが存在しない
- イメージ名/タグが間違っている
- プライベートレジストリの認証失敗
- ネットワーク接続の問題

**解決方法**:

```bash
# 詳細確認
kubectl -n app describe pod api-xxx

# Events部分を確認:
# Events:
#   Warning  Failed     2m   kubelet  Failed to pull image "docker.io/subaru88/home-kube:latest": rpc error: ...

# イメージが存在するか確認
docker pull docker.io/subaru88/home-kube:latest

# minikubeの場合、イメージをロード
minikube image load docker.io/subaru88/home-kube:latest

# Podを削除して再作成
kubectl -n app delete pod api-xxx

# またはDeploymentを再起動
kubectl -n app rollout restart deployment api
```

### CrashLoopBackOff

**症状**:
```bash
$ kubectl get pods -n app
NAME       READY   STATUS             RESTARTS   AGE
api-xxx    0/1     CrashLoopBackOff   5          3m
```

**原因**:
- アプリケーションエラー（起動失敗）
- 設定ミス（環境変数、Secret）
- 依存サービスへの接続失敗（PostgreSQLなど）
- ヘルスチェック失敗

**解決方法**:

```bash
# ログ確認（最も重要）
kubectl -n app logs api-xxx

# 前回のクラッシュログ
kubectl -n app logs api-xxx --previous

# リアルタイムでログ監視
kubectl -n app logs -f api-xxx

# 詳細情報
kubectl -n app describe pod api-xxx

# 環境変数の確認
kubectl -n app describe pod api-xxx | grep -A 20 "Environment:"

# Secretの確認
kubectl -n app get secret postgres-secret -o yaml
```

**よくある原因と対処**:

1. **PostgreSQL接続失敗**:
   ```bash
   # PostgreSQL Pod確認
   kubectl -n app get pods postgres-0

   # PostgreSQLログ確認
   kubectl -n app logs postgres-0

   # Pod内から接続テスト
   kubectl -n app exec -it api-xxx -- sh
   nc -zv postgres.app.svc.cluster.local 5432
   ```

2. **環境変数の設定ミス**:
   ```bash
   # Secretを再作成
   kubectl -n app delete secret postgres-secret

   # デプロイスクリプトを再実行
   ./deployment/scripts/deploy.sh local
   ```

3. **TypeORMの同期エラー**:
   ```bash
   # ログで以下を確認:
   # "Error: ER_ACCESS_DENIED_ERROR"
   # → データベース認証情報が間違っている

   # "Error: ECONNREFUSED"
   # → PostgreSQLに接続できない
   ```

### Pending状態

**症状**:
```bash
$ kubectl get pods -n app
NAME          READY   STATUS    RESTARTS   AGE
postgres-0    0/1     Pending   0          5m
```

**原因**:
- リソース不足（CPU/メモリ）
- PVCがBindできない
- Nodeセレクタが一致しない
- Taintによる制限

**解決方法**:

```bash
# 詳細確認
kubectl -n app describe pod postgres-0

# Events部分を確認:
# Warning  FailedScheduling  5m  default-scheduler  0/1 nodes are available: 1 Insufficient memory.

# Node情報確認
kubectl describe nodes

# PVC状態確認
kubectl -n app get pvc

# PVCがPendingの場合
kubectl -n app describe pvc postgres-data-postgres-0
```

**リソース不足の場合**:
```bash
# 不要なPodを削除してリソース確保
kubectl delete pod <不要なpod>

# リソース制限を緩和（values.yamlを編集）
resources:
  requests:
    cpu: 50m      # 100m → 50m
    memory: 128Mi # 256Mi → 128Mi
```

## ネットワークの問題

### Service経由で接続できない

**症状**:
```bash
# Pod内から他のServiceに接続できない
kubectl -n app exec -it api-xxx -- curl http://postgres.app.svc.cluster.local:5432
curl: (7) Failed to connect to postgres.app.svc.cluster.local port 5432: Connection refused
```

**解決方法**:

```bash
# Service確認
kubectl -n app get svc
kubectl -n app describe svc postgres

# Endpointsの確認（Podが紐付いているか）
kubectl -n app get endpoints postgres

# Selectorが正しいか確認
kubectl -n app get pods --show-labels
kubectl -n app describe svc postgres | grep Selector

# NetworkPolicyで通信がブロックされていないか
kubectl -n app get networkpolicy
```

### DNS解決できない

**症状**:
```bash
kubectl -n app exec -it api-xxx -- nslookup postgres.app.svc.cluster.local
# Server:    10.43.0.10
# ** server can't find postgres.app.svc.cluster.local: NXDOMAIN
```

**解決方法**:

```bash
# CoreDNS Pod確認
kubectl -n kube-system get pods -l k8s-app=kube-dns

# CoreDNSログ確認
kubectl -n kube-system logs -l k8s-app=kube-dns

# DNS設定確認
kubectl -n app exec -it api-xxx -- cat /etc/resolv.conf

# CoreDNS再起動
kubectl -n kube-system rollout restart deployment coredns
```

## ストレージの問題

### PVC Pending状態

**症状**:
```bash
$ kubectl -n app get pvc
NAME                  STATUS    VOLUME   CAPACITY   STORAGECLASS
postgres-data-0       Pending                       local-path
```

**原因**:
- StorageClassが存在しない
- Dynamic Provisionerが稼働していない
- PVが不足している

**解決方法**:

```bash
# StorageClass確認
kubectl get storageclass

# minikubeの場合
# NAME                 PROVISIONER                RECLAIMPOLICY
# standard (default)   k8s.io/minikube-hostpath   Delete

# k3sの場合
# NAME                 PROVISIONER                RECLAIMPOLICY
# local-path (default) rancher.io/local-path      Delete

# PVC詳細確認
kubectl -n app describe pvc postgres-data-postgres-0

# StorageClassを変更してデプロイ
helm upgrade --install postgres ./deployment/charts/postgres \
  -n app \
  -f ./deployment/environments/local/postgres-values.yaml \
  --set persistence.storageClassName=standard
```

### ディスク容量不足

**症状**:
```bash
# Podログにディスク容量不足エラー
kubectl -n app logs postgres-0
# Error: No space left on device
```

**解決方法**:

```bash
# Node のディスク使用状況確認
kubectl describe nodes | grep -A 5 "Allocated resources"

# minikubeの場合、ディスク容量を増やす
minikube delete
minikube start --disk-size=50g

# 不要なイメージを削除
docker system prune -a
minikube image rm <不要なイメージ>

# 不要なPVCを削除
kubectl -n app delete pvc <不要なpvc>
```

## まとめ

### 問題発生時の基本フロー

1. **状態確認**:
   ```bash
   kubectl get pods -A
   kubectl get nodes
   ```

2. **詳細情報取得**:
   ```bash
   kubectl describe pod <pod名>
   kubectl logs <pod名>
   ```

3. **関連リソース確認**:
   ```bash
   kubectl get svc
   kubectl get pvc
   kubectl get events --sort-by='.lastTimestamp'
   ```

4. **解決策適用**:
   - ログから原因を特定
   - 設定を修正
   - リソースを再起動

5. **動作確認**:
   ```bash
   kubectl get pods -w
   kubectl logs -f <pod名>
   ```

### 便利なデバッグコマンド

```bash
# すべてのイベントを時系列で表示
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# 特定Podのリソース使用状況
kubectl top pod <pod名> -n <namespace>

# Podの詳細情報（JSON形式）
kubectl get pod <pod名> -n <namespace> -o json

# 一時的なデバッグPodを起動
kubectl run debug --image=busybox -it --rm --restart=Never -- sh
```

これらの方法を使えば、ほとんどのKubernetes運用上の問題を解決できます。
