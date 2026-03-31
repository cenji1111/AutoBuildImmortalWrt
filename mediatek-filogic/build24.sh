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

# pppoe 设置
echo "Create pppoe-settings"
mkdir -p /home/build/immortalwrt/files/etc/config
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

# HomeProxy 核心配置（开箱即用）
FILES_DIR="/home/build/immortalwrt/files"
mkdir -p ${FILES_DIR}/etc/uci-defaults

cat << 'EOF' > ${FILES_DIR}/etc/uci-defaults/99-homeproxy-fix
#!/bin/sh
uci set homeproxy.config.proxy_mode='redirect'
uci set homeproxy.config.clash_api_port='9090'
uci set homeproxy.config.clash_api_secret='123456'

# 创建默认 instance
uci -q delete homeproxy.@instance[0]
uci add homeproxy instance
uci set homeproxy.@instance[-1].name='default'
uci set homeproxy.@instance[-1].type='sing-box'
uci set homeproxy.@instance[-1].enabled='1'

uci commit homeproxy

# 清理 TUN 残留
ip link delete singtun0 2>/dev/null || true
ip link delete tun0 2>/dev/null || true

echo "HomeProxy 配置完成（redirect + 9090 API）" > /tmp/homeproxy.log
exit 0
EOF

chmod +x ${FILES_DIR}/etc/uci-defaults/99-homeproxy-fix

# --- 软件包列表（精简无重复） ---
PACKAGES="$PACKAGES -dnsmasq -dnsmasq-dhcpv6 dnsmasq-full"
PACKAGES="$PACKAGES luci luci-i18n-base-zh-cn luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-app-homeproxy luci-i18n-homeproxy-zh-cn sing-box"
PACKAGES="$PACKAGES kmod-tun ip-full ipset iptables-mod-tproxy kmod-ipt-tproxy"
PACKAGES="$PACKAGES ca-bundle curl"

# 合并自定义包
if [ -n "$CUSTOM_PACKAGES" ]; then
    PACKAGES="$PACKAGES $CUSTOM_PACKAGES"
fi

# Docker 支持（如果需要）
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - 正在为 $PROFILE 生成镜像..."
echo "Packages: $PACKAGES"

make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="$FILES_DIR"

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
