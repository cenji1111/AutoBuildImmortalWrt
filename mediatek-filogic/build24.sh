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

# 1. ⚡ 基因手术：强制开启 9090 端口 (uci-defaults 模式)
cat << 'EOF' > ${FILES_DIR}/etc/uci-defaults/99-homeproxy-api-fix
#!/bin/sh
# 强制开启控制端口配置
uci set homeproxy.config.clash_api_port='9090'
uci set homeproxy.config.clash_api_secret='123456'
uci commit homeproxy

# 修改 HomeProxy 生成逻辑，确保 experimental 块包含 API 接口
TARGET="/usr/share/homeproxy/sing-box.sh"
if [ -f "$TARGET" ]; then
    # 强制在 experimental 块注入控制台配置
    sed -i '/"experimental": {/a \        "clash_api": { "external_controller": "0.0.0.0:9090", "secret": "123456" },' "$TARGET"
fi
exit 0
EOF
chmod +x ${FILES_DIR}/etc/uci-defaults/99-homeproxy-api-fix

# 2. 预下载猫咪面板 (修正版 wget，)
echo "🔄 正在下载猫咪面板..."
UI_URL="https://github.com/MetaCubeX/MetaCubeXD/releases/latest/download/compressed-dist.tgz"
# 使用标准参数，适配所有环境
wget -O /tmp/ui.tgz "$UI_URL" && tar -zxf /tmp/ui.tgz -C ${FILES_DIR}/www/metacubexd

# ---  软件包列表  ---
PACKAGES="$PACKAGES -dnsmasq -dnsmasq-dhcpv6 dnsmasq-full"
PACKAGES="$PACKAGES luci-app-homeproxy luci-i18n-homeproxy-zh-cn sing-box"
PACKAGES="$PACKAGES kmod-tun ip-full ipset iptables-mod-tproxy kmod-ipt-tproxy ca-bundle curl"

# 针对 AX6S 的机型构建
echo "$(date '+%Y-%m-%d %H:%M:%S') - 正在为 AX6S 生成镜像..."
make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="$FILES_DIR"

if [ $? -ne 0 ]; then
    echo "❌ 编译失败，请检查网络或脚本逻辑。"
    exit 1
fi
echo "✅ 编译成功！固件已生成。"
