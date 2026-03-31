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

# --- 🛠️ 核心预制件注入 (纯净上网版) ---
FILES_DIR="/home/build/immortalwrt/files"
mkdir -p ${FILES_DIR}/etc/uci-defaults
mkdir -p ${FILES_DIR}/www/metacubexd

# 1. ⚡ 强制开启 9090 端口（官方 UCI 方式）
cat << 'EOF' > ${FILES_DIR}/etc/uci-defaults/99-homeproxy-api-fix
#!/bin/sh
uci set homeproxy.config.clash_api_port='9090'
uci set homeproxy.config.clash_api_secret='123456'
uci commit homeproxy
/etc/init.d/homeproxy restart >/dev/null 2>&1 || true
echo "HomeProxy Clash API 已强制开启 9090 端口（secret: 123456）" > /tmp/homeproxy-api.log
exit 0
EOF
chmod +x ${FILES_DIR}/etc/uci-defaults/99-homeproxy-api-fix

# 2. 🔄 预下载猫咪面板（**最新最稳健版**）
echo "🔄 正在下载猫咪面板 (MetaCubeXD)..."
UI_URL="https://github.com/MetaCubeX/MetaCubeXD/releases/latest/download/compressed-dist.tgz"

if ! wget -q --no-check-certificate -O /tmp/ui.tgz "$UI_URL"; then
    echo "❌ 下载失败！"
    exit 1
fi

# 关键修复：先解压到临时目录，再复制展平（解决子目录问题）
mkdir -p /tmp/metacubexd_temp
if ! tar -zxf /tmp/ui.tgz -C /tmp/metacubexd_temp; then
    echo "❌ 解压失败！"
    rm -f /tmp/ui.tgz
    exit 1
fi

# 展平复制（自动处理可能存在的顶层目录）
cp -r /tmp/metacubexd_temp/* ${FILES_DIR}/www/metacubexd/ 2>/dev/null || true
rm -rf /tmp/metacubexd_temp /tmp/ui.tgz

echo "✅ 猫咪面板解压完成！"

# --- 🚀 软件包列表 ---
PACKAGES="$PACKAGES -dnsmasq -dnsmasq-dhcpv6 dnsmasq-full"
PACKAGES="$PACKAGES luci-app-homeproxy luci-i18n-homeproxy-zh-cn sing-box"
PACKAGES="$PACKAGES kmod-tun ip-full ipset iptables-mod-tproxy kmod-ipt-tproxy ca-bundle curl"

# 针对 AX6S 构建
echo "$(date '+%Y-%m-%d %H:%M:%S') - 正在为 AX6S 生成镜像..."
make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="$FILES_DIR"

if [ $? -ne 0 ]; then
    echo "❌ 编译失败"
    exit 1
fi

echo "✅ 编译成功！"

# =============================================
# === GitHub Actions 自动检查（务必看这段）===
# =============================================
echo "========================================"
echo "=== 阶段1 检查（猫咪面板是否正常）==="
echo "========================================"
echo "猫咪面板文件数量（正常应 ≥ 80）："
ls -l ${FILES_DIR}/www/metacubexd/ | wc -l
echo "前 15 个文件："
ls -l ${FILES_DIR}/www/metacubexd/ | head -n 15
echo "uci-defaults 脚本："
cat ${FILES_DIR}/etc/uci-defaults/99-homeproxy-api-fix
echo "========================================"
