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

# --- 🛠️ 核心预制件注入  ---
FILES_DIR="/home/build/immortalwrt/files"
mkdir -p ${FILES_DIR}/etc/uci-defaults
mkdir -p ${FILES_DIR}/www/metacubexd

# 1. ⚡ 核心逻辑：强制开启 9090 端口
# 我们创建一个初始化脚本，它会直接修改 HomeProxy 生成配置的脚本文件
cat << 'EOF' > ${FILES_DIR}/etc/uci-defaults/99-homeproxy-api-fix
#!/bin/sh
# 找到 HomeProxy 生成 sing-box 配置的脚本
TARGET_FILE="/usr/share/homeproxy/sing-box.sh"
if [ -f "$TARGET_FILE" ]; then
    # 强制在 experimental 块中插入 clash_api 配置
    sed -i '/"experimental": {/a \        "clash_api": { "external_controller": "0.0.0.0:9090", "secret": "123456" },' "$TARGET_FILE"
fi
exit 0
EOF
chmod +x ${FILES_DIR}/etc/uci-defaults/99-homeproxy-api-fix

# 2. 预下载猫咪面板 (增加重试和解压优化)
echo "🔄 正在预下载猫咪面板..."
UI_URL="https://github.com/MetaCubeX/MetaCubeXD/releases/latest/download/compressed-dist.tgz"
wget -q -t 3 -O /tmp/ui.tgz $UI_URL && tar -zxf /tmp/ui.tgz -C ${FILES_DIR}/www/metacubexd

# 3. 准备其他系统配置
mkdir -p ${FILES_DIR}/etc/config
cat << EOF > ${FILES_DIR}/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

# ---  定义软件包列表 (保持轻量) ---
PACKAGES="$PACKAGES -dnsmasq -dnsmasq-dhcpv6 dnsmasq-full"
PACKAGES="$PACKAGES luci luci-i18n-base-zh-cn luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-app-homeproxy luci-i18n-homeproxy-zh-cn sing-box"
PACKAGES="$PACKAGES kmod-tun ip-full ipset iptables-mod-tproxy kmod-ipt-tproxy"
PACKAGES="$PACKAGES ca-bundle libustream-openssl coreutils-base64 curl"

# 处理不同机型的逻辑
if [ "$PROFILE" = "glinet_gl-axt1800" ] || [ "$PROFILE" = "glinet_gl-ax1800" ]; then
    PACKAGES="$PACKAGES -luci-i18n-diskman-zh-cn"
else
    PACKAGES="$PACKAGES $CUSTOM_PACKAGES"
fi

# AX6S 建议关掉 Docker，内存吃不消
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
fi

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image..."
make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="$FILES_DIR"
