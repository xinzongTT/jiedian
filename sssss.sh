bash <(cat <<'SCRIPT'
#!/usr/bin/env bash
# 极简 Hysteria2 多端口 + 出口IP解决脚本

HOME=/root/agsbx
SB=$HOME/sb.json
UUID=$(cat $HOME/uuid 2>/dev/null || exit 1)
CERT=$HOME/cert.pem
KEY=$HOME/private.key

[ ! -f $SB ] && { echo sb.json 不存在; exit 1; }

command -v jq >/dev/null || apt update && apt install -y jq

IPS=($(ip -o -4 addr show scope global | awk '{print $4}' | cut -d/ -f1 | grep -v '^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.|^192\.168\.'))

echo "检测到 IP：${IPS[*]}"

cp $SB $SB.bak-$(date +%s) 2>/dev/null

for i in 1 2; do
  port=$(shuf -i 30000-50000 -n 1)
  while jq -e ".inbounds[]? | select(.listen_port==$port)" $SB >/dev/null; do
    port=$(shuf -i 30000-50000 -n 1)
  done

  jq ".inbounds += [{
    type:\"hysteria2\",
    tag:\"hy2-$port\",
    listen:\"::\",
    listen_port:$port,
    users:[{password:\"$UUID\"}],
    tls:{enabled:true,alpn:[\"h3\"],certificate_path:\"$CERT\",key_path:\"$KEY\"}
  }]" $SB > /tmp/sb.tmp && mv /tmp/sb.tmp $SB

  echo "添加端口 $port"
done

systemctl restart sb 2>/dev/null || { pkill -f "sing-box run" || true; nohup sing-box run -c $SB >/dev/null 2>&1 &; }

echo -e "\n=== 节点链接 ===\n"

for ip in "${IPS[@]}"; do
  for port in $(jq -r '.inbounds[-2:][] | .listen_port' $SB); do
    echo "hysteria2://$UUID@$ip:$port?security=tls&alpn=h3&insecure=1&sni=www.bing.com#hy2-$ip-$port"
    echo
  done
done

echo -e "\n防火墙建议：ufw allow 30000:50000/udp\n"

GW=$(ip route get 8.8.8.8 | awk '/via/{print $3}' | head -1)
DEV=$(ip route get 8.8.8.8 | awk '/dev/{print $5}' | head -1)

echo "=== 解决出口IP问题（复制以下命令逐行执行） ==="

echo "# 1. 添加路由表（只需执行一次）"
for i in "${!IPS[@]}"; do
  tbl=$((100 + i*100))
  echo "echo '$tbl rt${IPS[i]##*.}' >> /etc/iproute2/rt_tables"
done

echo -e "\n# 2. 添加路由（GW=$GW  DEV=$DEV）"
for i in "${!IPS[@]}"; do
  tbl=$((100 + i*100))
  ip="${IPS[i]}"
  echo "ip route add default via $GW dev $DEV src $ip table $tbl"
  echo "ip route add ${ip%.*}.0/24 dev $DEV src $ip table $tbl"
done

echo -e "\n# 3. 添加规则"
for i in "${!IPS[@]}"; do
  tbl=$((100 + i*100))
  echo "ip rule add from ${IPS[i]} table $tbl prio $tbl"
done

echo -e "\n执行完成后验证：ip rule show\n连不同IP的节点，出口IP应匹配"
SCRIPT
)
