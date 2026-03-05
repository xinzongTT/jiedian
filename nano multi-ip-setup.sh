#!/usr/bin/env bash
# 多IP独立端口搭建脚本 - VLESS-Reality-Vision + Socks5
# 针对两个IP，每个协议随机端口 + 绑定IP
# 使用：bash 此脚本 "IP1 IP2"

set -e

HOME_DIR="/root/agsbx"
XR_JSON="$HOME_DIR/xr.json"
BACKUP_JSON="$HOME_DIR/xr.json.bak-$(date +%Y%m%d-%H%M%S)"
XRK_DIR="$HOME_DIR/xrk"

# 检查参数
if [ $# -ne 1 ] || [ $(echo "$1" | wc -w) -ne 2 ]; then
    echo "使用示例：bash $0 \"38.182.100.41 38.182.100.15\""
    exit 1
fi

IFS=' ' read -r ip1 ip2 <<< "$1"
echo "IP1: $ip1"
echo "IP2: $ip2"

# 检查必要文件
required_files=("$HOME_DIR/uuid" "$XR_JSON" "$XRK_DIR/private_key" "$XRK_DIR/public_key" "$XRK_DIR/short_id" "$HOME_DIR/ym_vl_re")
missing=""
for f in "${required_files[@]}"; do
    [ ! -f "$f" ] && missing="$missing $f"
done
if [ -n "$missing" ]; then
    echo "缺少文件：$missing"
    echo "请先运行原argosbx.sh安装（vlpt= sopt=）"
    exit 1
fi

uuid=$(cat "$HOME_DIR/uuid")
private_key=$(cat "$XRK_DIR/private_key")
public_key=$(cat "$XRK_DIR/public_key")  # 用于客户端链接
short_id=$(cat "$XRK_DIR/short_id")
sni=$(cat "$HOME_DIR/ym_vl_re" 2>/dev/null || echo "apple.com")
dest="$sni:443"  # 用于reality dest

# 生成随机端口（避免冲突）
port_v1=$(shuf -i 20000-40000 -n 1)
port_v2=$(shuf -i 20000-40000 -n 1)
while [ $port_v2 -eq $port_v1 ]; do port_v2=$(shuf -i 20000-40000 -n 1); done

port_s1=$(shuf -i 10000-19999 -n 1)
port_s2=$(shuf -i 10000-19999 -n 1)
while [ $port_s2 -eq $port_s1 ]; do port_s2=$(shuf -i 10000-19999 -n 1); done

echo "生成的端口："
echo "  VLESS IP1 ($ip1): $port_v1"
echo "  VLESS IP2 ($ip2): $port_v2"
echo "  Socks5 IP1 ($ip1): $port_s1"
echo "  Socks5 IP2 ($ip2): $port_s2"

# 备份原xr.json
cp "$XR_JSON" "$BACKUP_JSON"
echo "已备份原配置文件到 $BACKUP_JSON"

# 生成新的inbounds JSON片段
new_inbounds=$(cat <<EOF
[
  {
    "tag": "vless-ip1",
    "listen": "$ip1",
    "port": $port_v1,
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "$uuid", "flow": "xtls-rprx-vision"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "fingerprint": "chrome",
        "dest": "$dest",
        "serverNames": ["$sni"],
        "privateKey": "$private_key",
        "shortIds": ["$short_id"]
      }
    },
    "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
  },
  {
    "tag": "vless-ip2",
    "listen": "$ip2",
    "port": $port_v2,
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "$uuid", "flow": "xtls-rprx-vision"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "fingerprint": "chrome",
        "dest": "$dest",
        "serverNames": ["$sni"],
        "privateKey": "$private_key",
        "shortIds": ["$short_id"]
      }
    },
    "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
  },
  {
    "tag": "socks5-ip1",
    "listen": "$ip1",
    "port": $port_s1,
    "protocol": "socks",
    "settings": {
      "auth": "password",
      "accounts": [{"user": "$uuid", "pass": "$uuid"}],
      "udp": true
    },
    "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
  },
  {
    "tag": "socks5-ip2",
    "listen": "$ip2",
    "port": $port_s2,
    "protocol": "socks",
    "settings": {
      "auth": "password",
      "accounts": [{"user": "$uuid", "pass": "$uuid"}],
      "udp": true
    },
    "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
  }
]
EOF
)

# 用 jq 更新 xr.json 的 inbounds（假设原文件是标准JSON，需要 jq 工具）
if ! command -v jq >/dev/null; then
    apt update && apt install -y jq
fi
jq ".inbounds = $new_inbounds" "$XR_JSON" > "$XR_JSON.tmp"
mv "$XR_JSON.tmp" "$XR_JSON"

# 重启服务
agsbx res
echo "Xray 服务已重启"

# 生成节点链接并保存
output_file="$HOME_DIR/multi-nodes.txt"
> "$output_file"

echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$output_file"
echo "----------------------------------------" >> "$output_file"

# VLESS IP1
vl1_link="vless://${uuid}@${ip1}:${port_v1}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#VLESS-${ip1}"
echo "【VLESS IP1】 $vl1_link" >> "$output_file"
echo "$vl1_link"

# VLESS IP2
vl2_link="vless://${uuid}@${ip2}:${port_v2}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#VLESS-${ip2}"
echo "【VLESS IP2】 $vl2_link" >> "$output_file"
echo "$vl2_link"

# Socks5 IP1
echo "【Socks5 IP1】" >> "$output_file"
echo "  地址: ${ip1}" >> "$output_file"
echo "  端口: ${port_s1}" >> "$output_file"
echo "  用户: ${uuid}" >> "$output_file"
echo "  密码: ${uuid}" >> "$output_file"

# Socks5 IP2
echo "【Socks5 IP2】" >> "$output_file"
echo "  地址: ${ip2}" >> "$output_file"
echo "  端口: ${port_s2}" >> "$output_file"
echo "  用户: ${uuid}" >> "$output_file"
echo "  密码: ${uuid}" >> "$output_file"

echo "----------------------------------------" >> "$output_file"

echo
echo "节点已保存到 $output_file"
echo "请手动放行新端口（ufw 或 iptables）："
echo "  ufw allow $port_v1/tcp $port_v2/tcp $port_s1/tcp $port_s2/tcp"
echo "完成！测试连通性后使用。"
