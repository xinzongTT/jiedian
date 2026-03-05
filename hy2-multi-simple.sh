#!/usr/bin/env bash
# 简洁一次性 Hysteria2 多端口 + 出口IP解决提示脚本

set -e

HOME="/root/agsbx"
SB="$HOME/sb.json"
UUID=$(cat "$HOME/uuid" 2>/dev/null || { echo "uuid文件缺失"; exit 1; })
CERT="$HOME/cert.pem"
KEY="$HOME/private.key"
SNI="www.bing.com"

command -v jq >/dev/null || { apt update && apt install -y jq; }

# 自动获取所有公网 IPv4（global scope，非 lo/私有）
IPS=($(ip -o -4 addr show scope global | awk '{print $4}' | cut -d/ -f1 | grep -v '^10\.' | grep -v '^172\.1[6-9]\.' | grep -v '^172\.2[0-9]\.' | grep -v '^172\.3[0-1]\.' | grep -v '^192\.168\.'))

[ ${#IPS[@]} -eq 0 ] && { echo "未检测到公网 IPv4"; exit 1; }

echo "检测到公网 IP：${IPS[*]}"
echo "本次添加 2 个 Hysteria2 端口"

cp "$SB" "$SB.bak-$(date +%s)"

for i in 1 2; do
  port=$(shuf -i 30000-50000 -n 1)
  while jq -e ".inbounds[] | select(.listen_port==$port)" "$SB" >/dev/null; do port=$(shuf -i 30000-50000 -n 1); done

  tag="hy2-p$port"

  jq ".inbounds += [{
    type: \"hysteria2\",
    tag: \"$tag\",
    listen: \"::\",
    listen_port: $port,
    users: [{password: \"$UUID\"}],
    tls: {enabled: true, alpn: [\"h3\"], certificate_path: \"$CERT\", key_path: \"$KEY\"}
  }]" "$SB" > tmp && mv tmp "$SB"

  echo "添加端口 $port"
done

# 重启
systemctl restart sb 2>/dev/null || { pkill -f "sing-box run" || true; nohup sing-box run -c "$SB" >/dev/null 2>&1 &; }
echo "Sing-box 重启"

echo -e "\n=== 节点链接（直接复制） ===\n"

for ip in "${IPS[@]}"; do
  for port in $(jq -r '.inbounds[-2:] | .[] .listen_port' "$SB"); do
    link="hysteria2://${UUID}@${ip}:${port}?security=tls&alpn=h3&insecure=1&sni=${SNI}#hy2-${ip##*.}-${port}"
    echo "$link"
    echo ""
  done
done

echo -e "\n防火墙：ufw allow 30000:50000/udp   或   ufw allow <具体端口>/udp"

echo -e "\n=== 解决出口 IP 始终是主 IP 的问题（复制下面命令执行） ===\n"

# 自动生成 policy routing 命令
GW=$(ip route get 8.8.8.8 | grep -oP '(?<=via )\S+')
DEV=$(ip route get 8.8.8.8 | grep -oP '(?<=dev )\S+')

echo "# 1. 添加路由表（/etc/iproute2/rt_tables）"
for i in "${!IPS[@]}"; do
  table=$((100 + i*100))
  echo "$table main${IPS[i]##*.}" | tee -a /etc/iproute2/rt_tables 2>/dev/null || echo "已存在或权限问题，手动添加"
done

echo -e "\n# 2. 添加路由（替换 GW=$GW DEV=$DEV）"
for i in "${!IPS[@]}"; do
  table=$((100 + i*100))
  ip=" ${IPS[i]} "
  echo "ip route add default via $GW dev $DEV src $ip table $table"
  echo "ip route add ${ip%.*}.0/24 dev $DEV src $ip table $table   # 替换你的子网掩码/网段"
done

echo -e "\n# 3. 添加规则"
for i in "${!IPS[@]}"; do
  table=$((100 + i*100))
  ip=" ${IPS[i]} "
  echo "ip rule add from $ip table $table prio $((100 + i*100))"
done

echo -e "\n执行完以上命令后："
echo "ip rule show   # 检查规则"
echo "重启服务器或接口后永久生效"
echo "连不同 IP 的 hy2 端口，出口 IP 就会匹配入口 IP"
