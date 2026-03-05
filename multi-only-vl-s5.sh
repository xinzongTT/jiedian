#!/usr/bin/env bash
# 多IPv4专用 - 只输出 VLESS-Reality-Vision + Socks5
# 使用方式: bash 此脚本.sh "1.1.1.1 2.2.2.2 3.3.3.3"
# 或不带参数时读取上次保存的IP列表

set -e

HOME_DIR="$HOME/agsbx"
MULTI_IPS_FILE="$HOME_DIR/multi_ips.txt"
mkdir -p "$HOME_DIR"

# ====================== 处理IP列表 ======================
if [ $# -ge 1 ]; then
    # 用传进来的参数作为IP列表
    input_ips=$(echo "$*" | tr -s '[:space:]' ' ')
    echo "$input_ips" > "$MULTI_IPS_FILE"
    echo "已保存多IP列表：$input_ips"
else
    if [ -f "$MULTI_IPS_FILE" ]; then
        input_ips=$(cat "$MULTI_IPS_FILE")
        echo "读取上次多IP：$input_ips"
    else
        echo "错误：首次运行请带参数指定IPv4，例如："
        echo "  bash $0 \"1.1.1.8 45.67.89.10 104.21.3.1\""
        exit 1
    fi
fi

# 转成数组
IFS=' ' read -r -a server_ips <<< "$input_ips"

if [ ${#server_ips[@]} -eq 0 ]; then
    echo "没有有效的IPv4地址"
    exit 1
fi

echo "本次处理 ${#server_ips[@]} 个IP："
printf '  - %s\n' "${server_ips[@]}"
echo "---------------------------------------------------"

# ====================== 检查必要文件是否存在 ======================
required_files=(
    "$HOME_DIR/uuid"
    "$HOME_DIR/port_vl_re"
    "$HOME_DIR/public_key_x"
    "$HOME_DIR/short_id_x"
    "$HOME_DIR/port_so"   # socks5端口，如果存在
)

missing=""
for f in "${required_files[@]}"; do
    if [ ! -f "$f" ]; then
        missing="$missing $f"
    fi
done

if [ -n "$missing" ]; then
    echo "缺少必要配置文件：$missing"
    echo "请先运行一次原脚本（至少带 vless reality + socks5 参数）来生成配置，例如："
    echo "  vlpt=443 sopt=1080 bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh)"
    echo "之后再用此脚本生成多IP节点。"
    exit 1
fi

uuid=$(cat "$HOME_DIR/uuid")
port_vl_re=$(cat "$HOME_DIR/port_vl_re")
public_key=$(cat "$HOME_DIR/public_key_x")
short_id=$(cat "$HOME_DIR/short_id_x")
port_so=$(cat "$HOME_DIR/port_so" 2>/dev/null || echo "")

# 尝试读 sni，如果没有默认用 www.microsoft.com 或你之前设的
ym_vl_re=$(cat "$HOME_DIR/ym_vl_re" 2>/dev/null || echo "www.microsoft.com")

generate_for_ip() {
    local ip="$1"
    local file="$HOME_DIR/nodes-${ip}.txt"

    > "$file"

    echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$file"
    echo "服务器IP: $ip" >> "$file"
    echo "----------------------------------------" >> "$file"

    # 1. VLESS + Reality + Vision
    vl_link="vless://${uuid}@${ip}:${port_vl_re}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${ym_vl_re}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#VLESS-Reality-Vision-${ip}"

    echo "【VLESS + TCP + Reality + Vision】" >> "$file"
    echo "$vl_link" >> "$file"
    echo "" >> "$file"
    echo "$vl_link"   # 也输出到终端

    # 2. Socks5（如果端口存在）
    if [ -n "$port_so" ]; then
        echo "" >> "$file"
        echo "【Socks5】（用户名/密码均为 uuid，用于应用内置代理）" >> "$file"
        echo "地址: ${ip}" >> "$file"
        echo "端口: ${port_so}" >> "$file"
        echo "用户名: ${uuid}" >> "$file"
        echo "密码: ${uuid}" >> "$file"
        echo "备注: 勿直接当节点用，适合配合其他软件的 socks5 代理功能" >> "$file"
        echo "" >> "$file"

        # 终端也显示
        echo "【Socks5 - ${ip}】"
        echo "  地址: ${ip}"
        echo "  端口: ${port_so}"
        echo "  用户: ${uuid}"
        echo "  密码: ${uuid}"
        echo
    fi

    echo "----------------------------------------" >> "$file"
    echo "以上为 IP ${ip} 的节点配置" >> "$file"
    echo
}

# 主循环：每个IP生成一次
for ip in "${server_ips[@]}"; do
    echo "正在生成节点 for ${ip} ..."
    generate_for_ip "$ip"
done

echo
echo "全部完成！"
echo "每个IP的节点详情保存在：$HOME_DIR/nodes-*.txt"
echo "示例合并所有到一个文件："
echo "  cat $HOME_DIR/nodes-*.txt > $HOME_DIR/all-nodes.txt"
echo
echo "如需修改SNI域名等，编辑 $HOME_DIR/ym_vl_re 文件后重新运行即可。"
