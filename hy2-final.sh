#!/usr/bin/env bash
# 最终极简版：添加2个Hysteria2端口 + 输出链接 + 自动解决出口IP问题
# 保存为 hy2-final.sh 后运行

set -e

HOME=/root/agsbx
SB=$HOME/sb.json
UUID=$(cat $HOME/uuid)
CERT=$HOME/cert.pem
KEY=$HOME/private.key
IP1=38.182.100.41
IP2=38.182.100.15

echo "=== 添加2个Hysteria2端口 ==="
command -v jq >/dev/null || apt install -y jq

cp $SB $SB.bak-$(date +%s) 2>/dev/null || true

for i in 1 2; do
  port=$(shuf -i 30000-50000 -n 1)
  while jq -e ".inbounds[]? | select(.listen_port==$port)" $SB >/dev/null 2>&1; do
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

# 重启
systemctl restart sb 2>/dev/null || { pkill -f "sing-box run" || true; nohup sing-box run -c $SB >/dev/null 2>&1 &; }
echo "Sing-box 已重启"

echo -e "\n=== 节点链接（直接复制到客户端） ===\n"

for ip in $IP1 $IP2; do
  for port in $(jq -r '.inbounds[-2:][] | .listen_port' $SB); do
    echo "hysteria2://$UUID@$ip:$port?security=tls&alpn=h3&insecure=1&sni=www.bing.com#hy2-$ip-$port"
    echo ""
  done
done

# 自动配置出口IP（入口IP=出口IP）
echo -e "\n=== 正在自动配置出口IP匹配（policy routing）===\n"

GW=$(ip route get 8.8.8.8 | awk '/via/{print $3}' | head -1)
DEV=$(ip route get 8.8.8.8 | awk '/dev/{print $5}' | head -1)

# 添加路由表
echo "100 main41" >> /etc/iproute2/rt_tables 2>/dev/null || true
echo "200 main15" >> /etc/iproute2/rt_tables 2>/dev/null || true

# 添加路由
ip route add default via $GW dev $DEV src $IP1 table 100 2>/dev/null || true
ip route add default via $GW dev $DEV src $IP2 table 200 2>/dev/null || true
ip route add ${IP1%.*}.0/24 dev $DEV src $IP1 table 100 2>/dev/null || true
ip route add ${IP2%.*}.0/24 dev $DEV src $IP2 table 200 2>/dev/null || true

# 添加规则
ip rule add from $IP1 table 100 prio 100 2>/dev/null || true
ip rule add from $IP2 table 200 prio 200 2>/dev/null || true

echo "出口IP配置已自动完成！"
echo -e "\n防火墙建议：ufw allow 30000:50000/udp"

echo -e "\n=== 测试方法 ==="
echo "1. 用上面两个IP的链接分别导入客户端"
echo "2. 连接后访问 https://ip.sb 查看出口IP"
echo "   应该与你连接的入口IP一致"
echo ""
echo "如需重置路由：ip rule del from $IP1 && ip rule del from $IP2"
echo "完成！"
