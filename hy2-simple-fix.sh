#!/usr/bin/env bash
# 极简修复版：添加2个Hysteria2端口 + 输出链接 + 出口IP配置提示

HOME=/root/agsbx
SB=$HOME/sb.json
UUID=$(cat $HOME/uuid 2>/dev/null || { echo "uuid缺失"; exit 1; })
CERT=$HOME/cert.pem
KEY=$HOME/private.key

[ ! -f "$SB" ] && { echo "sb.json不存在"; exit 1; }

command -v jq >/dev/null || { apt update && apt install -y jq; }

# 获取公网IP
IPS=($(ip -o -4 addr show scope global | awk '{print $4}' | cut -d/ -f1 | grep -v '^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.|^192\.168\.'))

echo "检测到IP：${IPS[*]}"

cp "$SB" "$SB.bak-$(date +%s)" 2>/dev/null

# 添加2个端口
for i in 1 2; do
  port=$(shuf -i 30000-50000 -n 1)
  while jq -e ".inbounds[]? | select(.listen_port==$port)" "$SB" >/dev/null 2>&1; do
    port=$(shuf -i 30000-50000 -n 1)
  done

  # 最安全jq追加方式
  jq ".inbounds += [{\"type\":\"hysteria2\",\"tag\":\"hy2-$port\",\"listen\":\"::\",\"listen_port\":$port,\"users\":[{\"password\":\"$UUID\"}],\"tls\":{\"enabled\":true,\"alpn\":[\"h3\"],\"certificate_path\":\"$CERT\",\"key_path\":\"$KEY\"}}]" "$SB" > /tmp/sb.tmp && mv /tmp/sb.tmp "$SB"

  echo "添加端口 $port"
done

# 重启Sing-box（分开写，避免语法坑）
if systemctl is-active sb >/dev/null 2>&1; then
  systemctl restart sb
  echo "已用systemctl重启sb"
else
  pkill -f "sing-box run" 2>/dev/null || true
  nohup sing-box run -c "$SB" >/dev/null 2>&1 &
  echo "已用nohup重启sing-box"
fi

echo -e "\n=== 节点链接（直接复制） ===\n"

for ip in "${IPS[@]}"; do
  # 只取最后两个端口
  for port in $(jq -r '.inbounds | .[-2:][] | .listen_port' "$SB"); do
    echo "hysteria2://$UUID@$ip:$port?security=tls&alpn=h3&insecure=1&sni=www.bing.com#hy2-$ip-$port"
    echo ""
  done
done

echo -e "\n防火墙：ufw allow 30000:50000/udp   或针对具体端口\n"

# 出口IP配置提示
GW=$(ip route get 8.8.8.8 | awk '/via/{print $3}' | head -1)
DEV=$(ip route get 8.8.8.8 | awk '/dev/{print $5}' | head -1)

echo "=== 让入口IP=出口IP（复制下面命令逐行执行） ===\n"

echo "# 步骤1：添加路由表（只需一次）"
for ip in "${IPS[@]}"; do
  tbl=$((100 + ${#IPS[@]} - ${#IPS[@]} + ${#IPS[@]}))  # 简单递增
  echo "echo '$tbl rt${ip##*.}' >> /etc/iproute2/rt_tables"
done

echo -e "\n# 步骤2：添加路由"
for ip in "${IPS[@]}"; do
  tbl=$((100 + ${#IPS[@]} - ${#IPS[@]} + ${#IPS[@]}))  # 简化
  echo "ip route add default via $GW dev $DEV src $ip table $tbl"
  echo "ip route add ${ip%.*}.0/24 dev $DEV src $ip table $tbl   # 如不是/24需改"
done

echo -e "\n# 步骤3：添加规则"
for ip in "${IPS[@]}"; do
  tbl=$((100 + ${#IPS[@]} - ${#IPS[@]} + ${#IPS[@]}))
  echo "ip rule add from $ip table $tbl prio $tbl"
done

echo -e "\n执行后验证：ip rule show\n重启网络或服务器生效"
echo "连不同IP节点 → 出口IP应匹配"
