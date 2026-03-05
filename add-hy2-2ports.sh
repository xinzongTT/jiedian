#!/usr/bin/env bash
# 简洁版：一次性添加 2 个 Hysteria2 端口（监听所有接口）

set -e

HOME="/root/agsbx"
SB="$HOME/sb.json"
UUID=$(cat "$HOME/uuid" 2>/dev/null || echo "error-uuid-missing")
CERT="$HOME/cert.pem"
KEY="$HOME/private.key"
SNI="www.bing.com"
IPS=("38.182.100.41" "38.182.100.15")  # 你的两个 IP

[ ! -f "$SB" ] && { echo "sb.json 不存在，先运行原脚本 hypt=443"; exit 1; }
[ ! -f "$CERT" ] && { echo "cert.pem 缺失"; exit 1; }

command -v jq >/dev/null || { apt update && apt install -y jq; }

cp "$SB" "$SB.bak-$(date +%s)"

for i in 1 2; do
  port=$(shuf -i 30000-50000 -n 1)
  while jq -e ".inbounds[] | select(.listen_port==$port)" "$SB" >/dev/null; do
    port=$(shuf -i 30000-50000 -n 1)
  done

  tag="hy2-port${port}"

  new=$(jq -n \
    --arg tag "$tag" \
    --argjson port "$port" \
    --arg uuid "$UUID" \
    --arg cert "$CERT" \
    --arg key "$KEY" \
    '{
      type: "hysteria2",
      tag: $tag,
      listen: "::",
      listen_port: $port,
      users: [{password: $uuid}],
      tls: {enabled: true, alpn: ["h3"], certificate_path: $cert, key_path: $key}
    }')

  jq ".inbounds += [$new]" "$SB" > tmp && mv tmp "$SB"

  echo "添加 Hysteria2 端口: $port"
done

# 重启
systemctl restart sb 2>/dev/null || {
  pkill -f "sing-box run" || true
  nohup sing-box run -c "$SB" >/dev/null 2>&1 &
}
echo "Sing-box 重启完成"

echo -e "\n=== 节点链接（直接复制） ===\n"

for ip in "${IPS[@]}"; do
  for port in $(jq -r '.inbounds[] | select(.type=="hysteria2") .listen_port' "$SB" | tail -2); do
    link="hysteria2://${UUID}@${ip}:${port}?security=tls&alpn=h3&insecure=1&sni=${SNI}#hy2-${ip##*.}-${port}"
    echo "$link"
    echo ""
  done
done

echo -e "\n防火墙示例：ufw allow 30000:50000/udp   或针对具体端口"
echo "完成！测试连通性。"
