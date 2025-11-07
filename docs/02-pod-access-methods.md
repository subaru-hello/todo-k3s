# Podへリクエストを投げる方法

このドキュメントでは、Kubernetes上で稼働しているPodへHTTPリクエストを送信する様々な方法を解説します。

## 目次
- [方法1: kubectl port-forward（開発・デバッグ向け）](#方法1-kubectl-port-forward開発デバッグ向け)
- [方法2: kubectl exec（クラスタ内からテスト）](#方法2-kubectl-execクラスタ内からテスト)
- [方法3: Service経由でアクセス（推奨）](#方法3-service経由でアクセス推奨)
- [方法4: kubectl proxy](#方法4-kubectl-proxy)
- [実例: http-echoへのアクセス](#実例-http-echoへのアクセス)

## 方法1: kubectl port-forward（開発・デバッグ向け）

**最も簡単な方法**で、ローカルマシンから直接Podにアクセスできます。

### 基本的な使い方

```bash
# ローカルの8080ポートをPodの5678ポートにフォワード
kubectl port-forward pod/hello-84bf6f98f5-d2fl8 8080:5678

# 別のターミナルから
curl http://localhost:8080
```

### Deployment経由でport-forward

```bash
# Deploymentを指定（自動的に適切なPodを選択）
kubectl port-forward deployment/hello 8080:5678

# Service経由
kubectl port-forward service/hello 8080:5678
```

### 特定のnamespaceを指定

```bash
kubectl port-forward -n app pod/api-xxx 3000:3000
```

### メリット・デメリット

**メリット**:
- 設定不要で即座にアクセス可能
- デバッグに最適
- Service作成が不要

**デメリット**:
- ターミナルを占有する
- 一時的なアクセスのみ
- ローカルマシンからのみアクセス可能

### 実用例

```bash
# APIへのアクセス
kubectl -n app port-forward svc/api 3000:3000

# 別ターミナルで
curl http://localhost:3000/healthz
curl http://localhost:3000/api/todos
```

## 方法2: kubectl exec（クラスタ内からテスト）

クラスタ内の別のPodから対象Podへアクセスする方法です。

### 一時的なPodを起動してアクセス

```bash
# curlコンテナを起動してアクセス
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl http://10.42.0.48:5678

# busyboxでwgetを使用
kubectl run busybox-test --image=busybox --rm -it --restart=Never -- \
  wget -O- http://10.42.0.48:5678
```

### 既存のPodからアクセス

```bash
# 既存のPod内でコマンドを実行
kubectl exec -it <既存のpod名> -- curl http://10.42.0.48:5678

# 特定のコンテナを指定（Multi-container Podの場合）
kubectl exec -it <pod名> -c <container名> -- curl http://10.42.0.48:5678
```

### Podのシェルに入って対話的に操作

```bash
# Podのシェルに入る
kubectl exec -it api-xxx -n app -- sh

# シェル内でcurlを実行
curl http://postgres.app.svc.cluster.local:5432
nc -zv postgres.app.svc.cluster.local 5432
exit
```

### メリット・デメリット

**メリット**:
- クラスタ内のネットワーク動作を確認できる
- DNS解決やService Discoveryのテストに最適
- 本番環境に近い状態でテスト可能

**デメリット**:
- curlやwgetがインストールされているイメージが必要
- 一時的なテストのみ

### 実用例

```bash
# PostgreSQLへの接続確認
kubectl -n app exec -it api-xxx -- sh
nc -zv postgres.app.svc.cluster.local 5432

# Service経由でAPIにアクセス
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl http://api.app.svc.cluster.local:3000/healthz
```

## 方法3: Service経由でアクセス（推奨）

本番環境や永続的なアクセスには、Serviceを作成して公開します。

### Service Typeごとのアクセス方法

#### ClusterIP（クラスタ内のみ）

```yaml
apiVersion: v1
kind: Service
metadata:
  name: hello-service
  namespace: default
spec:
  selector:
    app: hello
  ports:
    - protocol: TCP
      port: 80
      targetPort: 5678
  type: ClusterIP
```

```bash
# クラスタ内からアクセス
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl http://hello-service.default.svc.cluster.local
```

#### NodePort（Node経由で外部公開）

```yaml
apiVersion: v1
kind: Service
metadata:
  name: hello-service
spec:
  selector:
    app: hello
  ports:
    - protocol: TCP
      port: 80
      targetPort: 5678
      nodePort: 30080  # 30000-32767の範囲
  type: NodePort
```

```bash
# kubectl exposeコマンドで作成
kubectl expose deployment hello --type=NodePort --port=5678

# Serviceの情報を確認
kubectl get service hello
# NAME    TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)          AGE
# hello   NodePort   10.43.123.45   <none>        5678:30080/TCP   1m

# NodeのIPとNodePort経由でアクセス
curl http://192.168.0.50:30080
```

#### LoadBalancer（外部ロードバランサー）

```yaml
apiVersion: v1
kind: Service
metadata:
  name: hello-service
spec:
  selector:
    app: hello
  ports:
    - protocol: TCP
      port: 80
      targetPort: 5678
  type: LoadBalancer
```

```bash
# kubectl exposeで作成
kubectl expose deployment hello --type=LoadBalancer --port=80 --target-port=5678

# External-IPが割り当てられるまで待つ
kubectl get service hello -w

# External-IP経由でアクセス
curl http://<EXTERNAL-IP>
```

**注意**: k3s/minikubeではLoadBalancerのExternal-IPが`<pending>`のままになることがあります。その場合は:
- k3s: [MetalLB](https://metallb.universe.tf/)などを導入
- minikube: `minikube tunnel`を実行

### Service作成の実例

```bash
# 既存のDeploymentをNodePortで公開
kubectl expose deployment hello --type=NodePort --port=5678 --name=hello-service

# Service情報を確認
kubectl get svc hello-service
kubectl describe svc hello-service

# NodePort経由でアクセス
NODE_IP=$(kubectl get node -o jsonpath='{.items[0].status.addresses[0].address}')
NODE_PORT=$(kubectl get svc hello-service -o jsonpath='{.spec.ports[0].nodePort}')
curl http://$NODE_IP:$NODE_PORT
```

### メリット・デメリット

**メリット**:
- 本番環境に適した方法
- 複数Podへのロードバランシング
- 永続的なエンドポイント
- DNS名でアクセス可能

**デメリット**:
- Serviceリソースの作成が必要
- NodePort/LoadBalancerは外部公開されるためセキュリティ考慮が必要

## 方法4: kubectl proxy

Kubernetes APIプロキシを使用してPodにアクセスします。

### 基本的な使い方

```bash
# 別ターミナルでproxyを起動
kubectl proxy

# APIプロキシ経由でアクセス
curl http://localhost:8001/api/v1/namespaces/default/pods/hello-84bf6f98f5-d2fl8:5678/proxy/
```

### メリット・デメリット

**メリット**:
- Kubernetes APIの認証を利用
- デバッグに便利

**デメリット**:
- URLが長く複雑
- 一時的なアクセスのみ

## 実例: http-echoへのアクセス

以下のPodに対する具体的なアクセス例を示します：

```
Name:         hello-84bf6f98f5-d2fl8
Namespace:    default
IP:           10.42.0.48
Port:         5678/TCP
```

### 1. port-forwardでアクセス

```bash
kubectl port-forward pod/hello-84bf6f98f5-d2fl8 8080:5678

# 別ターミナル
curl http://localhost:8080
# 出力: hello from k3s
```

### 2. クラスタ内からアクセス

```bash
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl http://10.42.0.48:5678
# 出力: hello from k3s
```

### 3. Serviceを作成してアクセス

```bash
# NodePort Serviceを作成
kubectl expose deployment hello --type=NodePort --port=5678

# NodePort番号を確認
kubectl get svc hello

# アクセス
curl http://192.168.0.50:30080
# 出力: hello from k3s
```

## 方法の選び方

| 状況 | 推奨方法 | 理由 |
|-----|---------|------|
| 開発・デバッグ | `kubectl port-forward` | 最も簡単で迅速 |
| ネットワーク確認 | `kubectl exec` | クラスタ内の動作を確認 |
| 本番環境 | `Service (ClusterIP/NodePort)` | 永続的で安定したアクセス |
| 外部公開 | `Service (LoadBalancer)` + Ingress | スケーラブルで管理しやすい |

## Tips

### 1. Service DiscoveryのDNS名

Kubernetes内では以下のDNS名でServiceにアクセスできます：

```
<service-name>.<namespace>.svc.cluster.local
```

例:
- `api.app.svc.cluster.local`
- `postgres.app.svc.cluster.local`

同一namespace内では、サービス名だけでもアクセス可能：
```bash
curl http://api:3000
```

### 2. Ingressでパスベースルーティング

複数のサービスを1つのIPで公開：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
spec:
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 3000
      - path: /web
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

### 3. NetworkPolicyで通信制御

Podへのアクセスを制限：

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-network-policy
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: web
    ports:
    - protocol: TCP
      port: 3000
```

## まとめ

- **開発**: `kubectl port-forward` で簡単アクセス
- **テスト**: `kubectl exec` でクラスタ内動作確認
- **本番**: `Service` で永続的なエンドポイント提供
- **外部公開**: `NodePort` / `LoadBalancer` + `Ingress`

それぞれの方法を状況に応じて使い分けることで、効率的にKubernetes上のアプリケーションにアクセスできます。
