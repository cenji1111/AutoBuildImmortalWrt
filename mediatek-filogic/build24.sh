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

# --- 🛠️ 核心预制件注入（最终加强版） ---
FILES_DIR="/home/build/immortalwrt/files"
mkdir -p ${FILES_DIR}/etc/uci-defaults
mkdir -p ${FILES_DIR}/www/metacubexd

# 1. 加强版 uci-defaults：强制 redirect + 强行注入 clash_api
cat << 'EOF' > ${FILES_DIR}/etc/uci-defaults/99-homeproxy-api-fix
#!/bin/sh
echo "=== 开始设置 HomeProxy API ==="

# 强制使用 redirect 模式
uci set homeproxy.config.proxy_mode='redirect'

# 设置 Clash API
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

# 关键：强制修改 sing-box 生成脚本，注入 experimental.clash_api
TARGET="/usr/share/homeproxy/sing-box.sh"
if [ -f "$TARGET" ]; then
    echo "找到 sing-box.sh，正在注入 clash_api..."
    # 备份原文件
    cp "$TARGET" "$TARGET.bak" 2>/dev/null || true
    
    # 强制添加 experimental.clash_api（如果不存在）
    if ! grep -q "clash_api" "$TARGET"; then
        sed -i '/"experimental": {/a \    "clash_api": {\n      "external_controller": "0.0.0.0:9090",\n      "secret": "123456"\n    },' "$TARGET" 2>/dev/null || true
    fi
fi

/etc/init.d/homeproxy restart >/dev/null 2>&1 || true
echo "HomeProxy 9090 API 已强制注入" > /tmp/homeproxy-api.log
echo "设置完成！"
exit 0
EOF
chmod +x ${FILES_DIR}/etc/uci-defaults/99-homeproxy-api-fix

# 2. 猫咪面板下载
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

echo "✅ 编译成功！固件已生成。"

# 检查
echo "========================================"
echo "猫咪面板文件数量： $(ls -l ${FILES_DIR}/www/metacubexd/ | wc -l)"
echo "uci-defaults 脚本已生成"
echo "========================================"
