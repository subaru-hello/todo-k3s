# Kubernetes リソース確認の基本コマンド集

このドキュメントでは、Kubernetesで現在稼働しているリソースを調べるための`kubectl`コマンドをまとめています。

## 目次
- [Namespace](#namespace)
- [Pod](#pod)
- [Deployment](#deployment)
- [ReplicaSet](#replicaset)
- [ConfigMap](#configmap)
- [Secret](#secret)
- [便利なオプション](#便利なオプション)
- [リアルタイム監視](#リアルタイム監視)

## Namespace

```bash
# 全てのnamespaceを表示
kubectl get namespaces

# 短縮形
kubectl get ns
```

## Pod

```bash
# デフォルトnamespaceのpodを表示
kubectl get pods

# 全namespaceのpodを表示
kubectl get pods --all-namespaces
# または
kubectl get pods -A

# 詳細情報付き（IPアドレス、Node名など）
kubectl get pods -o wide

# 特定のnamespaceのpod
kubectl get pods -n <namespace名>
```

## Deployment

```bash
# デフォルトnamespaceのdeploymentを表示
kubectl get deployments
# または
kubectl get deploy

# 全namespaceのdeploymentを表示
kubectl get deployments -A
```

## ReplicaSet

```bash
# デフォルトnamespaceのreplicasetを表示
kubectl get replicasets
# または
kubectl get rs

# 全namespaceのreplicasetを表示
kubectl get rs -A
```

## ConfigMap

```bash
# デフォルトnamespaceのconfigmapを表示
kubectl get configmaps
# または
kubectl get cm

# 全namespaceのconfigmapを表示
kubectl get cm -A
```

## Secret

```bash
# デフォルトnamespaceのsecretを表示
kubectl get secrets

# 全namespaceのsecretを表示
kubectl get secrets -A

# Secretの内容を確認（base64デコード）
kubectl get secret <secret名> -o yaml
kubectl get secret <secret名> -o jsonpath='{.data.KEY}' | base64 -d
```

## 便利なオプション

### 特定のnamespaceを指定
```bash
kubectl get pods -n <namespace名>
```

### YAML形式で詳細を表示
```bash
kubectl get pod <pod名> -o yaml
kubectl get deployment <deployment名> -o yaml
```

### JSON形式で表示
```bash
kubectl get pod <pod名> -o json
```

### 全てのリソースを一度に確認
```bash
# 特定namespaceの主要リソースを全て表示
kubectl get all -n <namespace名>

# 全namespaceの主要リソースを全て表示
kubectl get all -A
```

### リソースの詳細情報を確認
```bash
kubectl describe pod <pod名>
kubectl describe deployment <deployment名>
kubectl describe service <service名>
kubectl describe node <node名>
```

## リアルタイム監視

### Watchモード
リソースの変化をリアルタイムで監視：

```bash
# Pod状態の変化を監視
kubectl get pods -w

# 特定namespaceで監視
kubectl get pods -n app -w

# 全namespaceで監視
kubectl get pods -A -w
```

## ラベルセレクタでフィルタリング

```bash
# 特定のラベルを持つPodを表示
kubectl get pods -l app=hello

# 複数のラベル条件
kubectl get pods -l 'app=hello,environment=production'
```

## ログの確認

```bash
# Podのログを表示
kubectl logs <pod名>

# 特定のコンテナのログ（Multi-container Podの場合）
kubectl logs <pod名> -c <container名>

# リアルタイムでログを追跡
kubectl logs -f <pod名>

# 過去N行のログを表示
kubectl logs --tail=100 <pod名>

# タイムスタンプ付きでログを表示
kubectl logs --timestamps <pod名>

# ラベルで複数Podのログを表示
kubectl logs -l app=api --all-containers=true
```

## コンテキストの確認と切り替え

```bash
# 現在のcontextを確認
kubectl config current-context

# 利用可能なcontext一覧
kubectl config get-contexts

# contextを切り替え
kubectl config use-context <context名>

# 現在の設定を表示
kubectl config view
```

## リソースの使用状況

```bash
# Nodeのリソース使用状況
kubectl top nodes

# Podのリソース使用状況
kubectl top pods

# 特定namespaceのPod
kubectl top pods -n <namespace名>
```

## Tips

1. **エイリアスの設定**: `~/.bashrc`や`~/.zshrc`に追加すると便利
   ```bash
   alias k='kubectl'
   alias kgp='kubectl get pods'
   alias kgpa='kubectl get pods -A'
   alias kgd='kubectl get deployments'
   alias kdp='kubectl describe pod'
   alias kl='kubectl logs'
   ```

2. **kubectlの自動補完**: シェルの自動補完を有効化
   ```bash
   # Bash
   source <(kubectl completion bash)

   # Zsh
   source <(kubectl completion zsh)
   ```

3. **k9s**: ターミナルUIでKubernetesを管理
   ```bash
   brew install k9s
   k9s
   ```

## まとめ

基本的なリソース確認は以下のパターンで覚えておくと便利です：

- `kubectl get <resource>` - リソース一覧
- `kubectl get <resource> -A` - 全namespace
- `kubectl get <resource> -n <namespace>` - 特定namespace
- `kubectl describe <resource> <name>` - 詳細情報
- `kubectl logs <pod>` - ログ確認
- `kubectl get <resource> -w` - リアルタイム監視
