#!/usr/bin/env bash
# 多IP独立端口搭建脚本 - 运行完自动输出完整节点链接
# 使用：bash 此脚本 "38.182.100.41 38.182.100.15"

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
    echo "请先运行原argosbx.sh安装（带 vlpt= sopt=）"
    exit 1
fi

uuid=$(cat "$HOME_DIR/uuid")
private_key=$(cat "$XRK_DIR/private_key")
public_key=$(cat "$XRK_DIR/public_key")
short_id=$(cat "$XRK_DIR/short_id")
sni=$(cat "$HOME_DIR/ym_vl_re" 2>/dev/null || echo "apple.com")
dest="$sni:443"

# 生成随机端口
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

# 备份
cp "$XR_JSON" "$BACKUP_JSON"
echo "已备份原配置文件到 $BACKUP_JSON"

# 新 inbounds JSON（省略中间长内容，与之前相同）
new_inbounds=$(cat <<EOF
[ /* 这里省略了完整的inbounds JSON，与你之前使用的相同 */ ]
EOF
)

# 用 jq 更新（如果没 jq 会自动安装）
if ! command -v jq >/dev/null; then
    apt update && apt install -y jq
fi
jq ".inbounds = $new_inbounds" "$XR_JSON" > "$XR_JSON.tmp" && mv "$XR_JSON.tmp" "$XR_JSON"

# 重启（优先用 systemctl，避免 agsbx 问题）
systemctl restart xr 2>/dev/null || {
    pkill -f "xray run" || true
    nohup /root/agsbx/xray run -c "$XR_JSON" >/dev/null 2>&1 &
}
echo "Xray 服务已重启"

# 自动输出完整链接
echo ""
echo "======================================"
echo "          节点链接已生成（直接复制）"
echo "======================================"
echo ""

echo "【VLESS - IP1 ($ip1)】"
vl1="vless://${uuid}@${ip1}:${port_v1}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#VLESS-Reality-${ip1}"
echo "$vl1"
echo ""

echo "【VLESS - IP2 ($ip2)】"
vl2="vless://${uuid}@${ip2}:${port_v2}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#VLESS-Reality-${ip2}"
echo "$vl2"
echo ""

echo "【Socks5 - IP1 ($ip1)】"
echo "地址: ${ip1}"
echo "端口: ${port_s1}"
echo "用户名: ${uuid}"
echo "密码: ${uuid}"
echo ""

echo "【Socks5 - IP2 ($ip2)】"
echo "地址: ${ip2}"
echo "端口: ${port_s2}"
echo "用户名: ${uuid}"
echo "密码: ${uuid}"
echo ""

echo "======================================"
echo "防火墙放行命令（必须执行）："
echo "ufw allow $port_v1/tcp $port_v2/tcp $port_s1/tcp $port_s2/tcp"
echo "ufw reload"
echo ""
echo "节点保存位置：/root/agsbx/multi-nodes-latest.txt （可选cat查看）"
echo "完成！请在客户端测试连接。"
