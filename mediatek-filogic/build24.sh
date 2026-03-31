#!/bin/bash
source shell/custom-packages.sh
source shell/switch_repository.sh

# 🔄 同步第三方仓库
echo "🔄 正在同步第三方软件仓库..."
git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo
mkdir -p /home/build/immortalwrt/extra-packages
cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/
sh shell/prepare-packages.sh

# 添加架构优先级
sed -i '1i\arch aarch64_generic 10\narch aarch64_cortex-a53 15' repositories.conf

# --- 🛠️ 核心预制件注入（加强版：强制 redirect + clash_api） ---
FILES_DIR="/home/build/immortalwrt/files"
mkdir -p ${FILES_DIR}/etc/uci-defaults
mkdir -p ${FILES_DIR}/www/metacubexd

# 1. 加强版 uci-defaults：强制 redirect + 清理 TUN + 注入 API
cat << 'EOF' > ${FILES_DIR}/etc/uci-defaults/99-homeproxy-api-fix
#!/bin/sh
# 强制设置 redirect 模式（避免 TUN file exists 错误）
uci set homeproxy.config.proxy_mode='redirect'

# 强制开启 Clash API
uci set homeproxy.config.clash_api_port='9090'
uci set homeproxy.config.clash_api_secret='123456'

# 清理可能存在的 TUN inbound
uci -q delete homeproxy.@instance[0].inbound

# 创建简单 default instance（如果不存在）
uci -q delete homeproxy.@instance[0]
uci add homeproxy instance
uci set homeproxy.@instance[-1].name='default'
uci set homeproxy.@instance[-1].type='sing-box'
uci set homeproxy.@instance[-1].enabled='1'

uci commit homeproxy

# 清理残留 TUN 网卡
ip link delete singtun0 2>/dev/null || true
ip link delete tun0 2>/dev/null || true

/etc/init.d/homeproxy restart >/dev/null 2>&1 || true
echo "HomeProxy 已强制 redirect + 9090 API" > /tmp/homeproxy-api.log
exit 0
EOF
chmod +x ${FILES_DIR}/etc/uci-defaults/99-homeproxy-api-fix

# 2. 猫咪面板下载（保持不变）
echo "🔄 正在下载猫咪面板..."
UI_URL="https://github.com/MetaCubeX/MetaCubeXD/releases/latest/download/compressed-dist.tgz"

if ! wget -q --no-check-certificate -O /tmp/ui.tgz "$UI_URL"; then
    echo "❌ 下载失败"
    exit 1
fi

mkdir -p /tmp/metacubexd_temp
tar -zxf /tmp/ui.tgz -C /tmp/metacubexd_temp
cp -r /tmp/metacubexd_temp/* ${FILES_DIR}/www/metacubexd/ 2>/dev/null || true
rm -rf /tmp/metacubexd_temp /tmp/ui.tgz

echo "✅ 猫咪面板完成"

# --- 软件包 ---
PACKAGES="$PACKAGES -dnsmasq -dnsmasq-dhcpv6 dnsmasq-full"
PACKAGES="$PACKAGES luci-app-homeproxy luci-i18n-homeproxy-zh-cn sing-box"
PACKAGES="$PACKAGES kmod-tun ip-full ipset iptables-mod-tproxy kmod-ipt-tproxy ca-bundle curl"

echo "$(date '+%Y-%m-%d %H:%M:%S') - 正在为 AX6S 生成镜像..."
make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="$FILES_DIR"

if [ $? -ne 0 ]; then
    echo "❌ 编译失败"
    exit 1
fi

echo "✅ 编译成功！"

# 检查输出
echo "========================================"
echo "猫咪面板文件数量："
ls -l ${FILES_DIR}/www/metacubexd/ | wc -l
echo "uci-defaults 脚本内容："
cat ${FILES_DIR}/etc/uci-defaults/99-homeproxy-api-fix
echo "========================================"
