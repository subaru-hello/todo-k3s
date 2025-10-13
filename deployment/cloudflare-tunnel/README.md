# Cloudflare Tunnel セットアップ手順（本番環境用）

## 前提条件

- Cloudflareアカウント（無料プランでOK）
- ドメイン（octomblog.com）がCloudflareで管理されている
- `cloudflared` CLIがインストール済み

## 1. Cloudflare Tunnelの作成

```bash
# cloudflared のインストール（macOS）
brew install cloudflare/cloudflare/cloudflared

# Cloudflareにログイン
cloudflared tunnel login

# Tunnelを作成
cloudflared tunnel create k3s-prod-tunnel

# 作成されたファイルを確認
ls ~/.cloudflared/
# → <TUNNEL_ID>.json （これがcredentials.json）
```

## 2. Tunnel IDの確認

```bash
cloudflared tunnel list
# NAME               ID                                   CREATED
# k3s-prod-tunnel    xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  2024-10-12
```

`<TUNNEL_ID>` をメモしておく。

## 3. config-prod.yaml の更新

```bash
# config-prod.yaml の <TUNNEL_ID> を実際のIDに置換
sed -i '' 's/<TUNNEL_ID>/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/' config-prod.yaml
```

## 4. Kubernetes Secretの作成

```bash
# k3s上で実行
kubectl create namespace app || true

kubectl create secret generic cloudflared-secret \
  --from-file=credentials.json=~/.cloudflared/<TUNNEL_ID>.json \
  --from-file=config.yaml=config-prod.yaml \
  -n app

# 確認
kubectl -n app get secret cloudflared-secret
```

## 5. DNSレコードの追加

Cloudflareダッシュボードで以下のCNAMEレコードを追加：

| Type  | Name | Content                                    | Proxy |
|-------|------|--------------------------------------------|-------|
| CNAME | api  | `<TUNNEL_ID>.cfargotunnel.com`             | ✅ On |

または CLI で：

```bash
cloudflared tunnel route dns k3s-prod-tunnel api.octomblog.com
```

## 6. Cloudflared Podのデプロイ

```bash
kubectl apply -f deployment-prod.yaml

# 確認
kubectl -n app get pods -l app=cloudflared
kubectl -n app logs -l app=cloudflared
```

## 7. 動作確認

```bash
# 外部からアクセス
curl https://api.octomblog.com/healthz
# → {"status":"healthy"}

curl https://api.octomblog.com/dbcheck
# → {"status":"ok","db":"connected"}
```

## トラブルシューティング

### Podが起動しない

```bash
kubectl -n app describe pod -l app=cloudflared
kubectl -n app logs -l app=cloudflared
```

### Tunnelが接続できない

```bash
# Tunnel の状態確認
cloudflared tunnel info k3s-prod-tunnel

# Cloudflareダッシュボードで確認
# Zero Trust > Access > Tunnels
```

### DNS解決できない

```bash
# CNAMEレコードの確認
dig api.octomblog.com

# Cloudflare経由か確認（プロキシON）
curl -I https://api.octomblog.com
# → server: cloudflare があればOK
```

## 参考

- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Deploy Tunnel in Kubernetes](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/tunnel-guide/kubernetes/)
