#!/usr/bin/env bash
# 多IPv4专用 - 只输出 VLESS-Reality-Vision + Socks5
# 修正版：Reality 密钥路径改为 $HOME/agsbx/xrk/public_key 和 short_id（匹配原 argosbx.sh）
# 使用：bash 此脚本 "38.182.100.41 38.182.100.15"   或不带参数读取上次

set -e

HOME_DIR="$HOME/agsbx"
MULTI_IPS_FILE="$HOME_DIR/multi_ips.txt"
mkdir -p "$HOME_DIR"
mkdir -p "$HOME_DIR/xrk"  # 原脚本会创建此目录

# ====================== 处理IP列表 ======================
if [ $# -ge 1 ]; then
    input_ips=$(echo "$*" | tr -s '[:space:]' ' ')
    echo "$input_ips" > "$MULTI_IPS_FILE"
    echo "已保存多IP列表：$input_ips"
else
    if [ -f "$MULTI_IPS_FILE" ]; then
        input_ips=$(cat "$MULTI_IPS_FILE")
        echo "读取上次多IP：$input_ips"
    else
        echo "错误：首次运行请带参数指定IPv4，例如："
        echo "  bash $0 \"38.182.100.41 38.182.100.15\""
        exit 1
    fi
fi

IFS=' ' read -r -a server_ips <<< "$input_ips"

if [ ${#server_ips[@]} -eq 0 ]; then
    echo "没有有效的IPv4地址"
    exit 1
fi

echo "本次处理 ${#server_ips[@]} 个IP："
printf '  - %s\n' "${server_ips[@]}"
echo "---------------------------------------------------"

# ====================== 检查必要文件 ======================
required_files=(
    "$HOME_DIR/uuid"
    "$HOME_DIR/port_vl_re"
    "$HOME_DIR/xrk/public_key"     # 正确路径，无 _x
    "$HOME_DIR/xrk/short_id"       # 正确路径，无 _x
    "$HOME_DIR/port_so"            # 可选，但列出以便提示
)

missing=""
for f in "${required_files[@]}"; do
    [ ! -f "$f" ] && missing="$missing $f"
done

if [ -n "$missing" ]; then
    echo "缺少必要配置文件：$missing"
    echo ""
    echo "请确认目录内容："
    echo "  ls -l $HOME_DIR/xrk/   # 应看到 public_key  short_id  private_key"
    echo ""
    echo "如果 xrk/ 目录为空或文件缺失，说明 Reality 未正确启用。"
    echo "建议：重新运行原脚本安装（指定 vlpt= 和 sopt=）："
    echo "  vlpt=23040 sopt=34636 bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh)"
    echo ""
    echo "安装后再次运行此脚本即可。"
    exit 1
fi

uuid=$(cat "$HOME_DIR/uuid")
port_vl_re=$(cat "$HOME_DIR/port_vl_re")
public_key=$(cat "$HOME_DIR/xrk/public_key")
short_id=$(cat "$HOME_DIR/xrk/short_id")
port_so=$(cat "$HOME_DIR/port_so" 2>/dev/null || echo "")

# SNI：你上次安装用了 apple.com，优先读取保存的值
ym_vl_re=$(cat "$HOME_DIR/ym_vl_re" 2>/dev/null || echo "apple.com")

generate_for_ip() {
    local ip="$1"
    local file="$HOME_DIR/nodes-${ip}.txt"

    > "$file"

    echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$file"
    echo "服务器IP: $ip" >> "$file"
    echo "----------------------------------------" >> "$file"

    # VLESS-Reality-Vision
    vl_link="vless://${uuid}@${ip}:${port_vl_re}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${ym_vl_re}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#VLESS-Reality-Vision-${ip}"

    echo "【VLESS + TCP + Reality + Vision】" >> "$file"
    echo "$vl_link" >> "$file"
    echo "" >> "$file"
    echo "$vl_link"

    # Socks5
    if [ -n "$port_so" ]; then
        echo "" >> "$file"
        echo "【Socks5】（用户名/密码均为 uuid，适合内置代理）" >> "$file"
        echo "地址  : ${ip}" >> "$file"
        echo "端口  : ${port_so}" >> "$file"
        echo "用户名: ${uuid}" >> "$file"
        echo "密码  : ${uuid}" >> "$file"
        echo "备注  : 适用于 Clash/Shadowsocks 等软件的 socks5 代理设置" >> "$file"
        echo ""

        echo "【Socks5 - ${ip}】"
        echo "  地址  : ${ip}"
        echo "  端口  : ${port_so}"
        echo "  用户名: ${uuid}"
        echo "  密码  : ${uuid}"
        echo
    fi

    echo "----------------------------------------" >> "$file"
    echo "以上为 IP ${ip} 的配置" >> "$file"
    echo
}

for ip in "${server_ips[@]}"; do
    echo "正在生成 for ${ip} ..."
    generate_for_ip "$ip"
done

echo
echo "完成！节点文件保存在 $HOME_DIR/nodes-*.txt"
echo "合并命令示例：cat $HOME_DIR/nodes-*.txt > $HOME_DIR/all-nodes.txt"
echo
echo "改 SNI 示例：echo 'www.microsoft.com' > $HOME_DIR/ym_vl_re && agsbx res"
echo "改完后重新跑此脚本，链接会更新 sni= 值。"
