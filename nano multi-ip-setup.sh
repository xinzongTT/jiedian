#!/usr/bin/env bash
# 只添加 Hysteria2 多端口版 - 追加到原有 sb.json
# 用法: bash 此脚本.sh [端口数量，默认2]

set -e

HOME_DIR="/root/agsbx"
SB_JSON="$HOME_DIR/sb.json"
CERT_PEM="$HOME_DIR/cert.pem"
KEY_PEM="$HOME_DIR/private.key"
UUID_FILE="$HOME_DIR/uuid"

# 检查前提文件
for f in "$SB_JSON" "$CERT_PEM" "$KEY_PEM" "$UUID_FILE"; do
    if [ ! -f "$f" ]; then
        echo "缺少文件: $f"
        echo "请先运行原脚本启用 Hysteria2 或其他协议（hypt=443 bash argosbx.sh）"
        exit 1
    fi
done

uuid=$(cat "$UUID_FILE")
sni="www.bing.com"   # 可改成你喜欢的伪装域名

# 默认添加 2 个端口
num_ports=${1:-2}
if ! [[ "$num_ports" =~ ^[1-9][0-9]?$ ]]; then
    echo "参数应为 1-99 的整数（端口数量），默认 2"
    exit 1
fi

echo "本次将添加 $num_ports 个 Hysteria2 端口（监听 ::，所有 IP 可用）"

# 读取当前 sb.json（用 jq 处理）
if ! command -v jq >/dev/null; then
    apt update && apt install -y jq
fi

# 备份 sb.json
backup="$SB_JSON.bak-$(date +%Y%m%d-%H%M%S)"
cp "$SB_JSON" "$backup"
echo "备份 sb.json 到 $backup"

# 生成并追加 inbounds
new_inbounds=()

for ((i=1; i<=num_ports; i++)); do
    port=$(shuf -i 20000-65535 -n 1)
    # 避免极端冲突，再随机一次如果必要
    while grep -q "\"listen_port\": $port" "$SB_JSON"; do
        port=$(shuf -i 20000-65535 -n 1)
    done

    tag="hy2-multi-$i"

    inbound=$(cat <<EOF
{
  "type": "hysteria2",
  "tag": "$tag",
  "listen": "::",
  "listen_port": $port,
  "users": [
    {
      "password": "$uuid"
    }
  ],
  "ignore_client_bandwidth": false,
  "tls": {
    "enabled": true,
    "alpn": ["h3"],
    "certificate_path": "$CERT_PEM",
    "key_path": "$KEY_PEM"
  }
}
EOF
)

    new_inbounds+=("$inbound")
    echo "生成 Hysteria2 端口 $port (tag: $tag)"
done

# 用 jq 追加到 inbounds 数组（如果已有 hy2 也会保留）
current_inbounds=$(jq '.inbounds // []' "$SB_JSON")
updated_inbounds=$(jq -n --argjson current "$current_inbounds" --argjson new "$(printf '%s\n' "${new_inbounds[@]}" | jq -s '.')" '$current + $new')

jq ".inbounds = $updated_inbounds" "$SB_JSON" > "$SB_JSON.tmp" && mv "$SB_JSON.tmp" "$SB_JSON"

# 重启 Sing-box
if systemctl is-active sb >/dev/null 2>&1; then
    systemctl restart sb
    echo "已重启 Sing-box 服务 (systemctl)"
else
    pkill -f "sing-box run" || true
    nohup sing-box run -c "$SB_JSON" >/dev/null 2>&1 &
    echo "已通过 nohup 重启 Sing-box"
fi

echo ""
echo "======================================"
echo "     Hysteria2 多端口节点链接"
echo "======================================"

# 输出链接（假设服务器有多个 IP，你可以手动替换或用主 IP）
server_ips=("38.182.100.41" "38.182.100.15")  # ← 这里改成你的实际 IP 列表

for ((i=0; i<num_ports; i++)); do
    # 从 sb.json 提取实际端口（jq 方式）
    port=$(jq -r ".inbounds[] | select(.tag == \"hy2-multi-$((i+1))\") .listen_port" "$SB_JSON")

    for ip in "${server_ips[@]}"; do
        link="hysteria2://${uuid}@${ip}:${port}?security=tls&alpn=h3&insecure=1&sni=${sni}#hy2-multi-${ip}-port${port}"
        echo "【Hysteria2 多端口 $((i+1)) - ${ip}】"
        echo "$link"
        echo ""
    done
done

echo "======================================"
echo "防火墙放行示例（所有新端口）："
echo "ufw allow 20000:65535/udp   # 或针对具体端口"
echo "完成！请在 Hysteria2 支持的客户端（如 Nekobox、Sing-box、Clash Meta）测试。"
echo "节点也保存到 $SB_JSON 的 inbounds 中，可随时查看。"
