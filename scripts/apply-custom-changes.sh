#!/bin/bash
#
# ImmortalWrt 自定义修改自动应用脚本
# 用途：在同步上游代码后自动应用所有自定义配置
#

set -e

echo "========================================"
echo "🔧 ImmortalWrt 自定义修改自动应用"
echo "========================================"
echo ""

# 配置变量
DEFAULT_IP="192.168.32.10"
DEFAULT_HOSTNAME="ImmortalWrt"
DEFAULT_PASSWORD="passwd"
DEFAULT_THEME="luci-theme-kucat"

# 检查是否在正确的目录
if [ ! -d "package/base-files" ]; then
    echo "❌ 错误：请在 ImmortalWrt 根目录运行此脚本"
    exit 1
fi

echo "✅ 检测到 ImmortalWrt 根目录"
echo ""

# ========================================
# 1. 修改默认 IP 和主机名
# ========================================
echo "📡 1. 修改默认 IP 和主机名..."
CONFIG_FILE="package/base-files/files/bin/config_generate"

if [ -f "$CONFIG_FILE" ]; then
    # 备份原文件
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    
    # 修改 IP 地址
    if grep -q "192\.168\.1\.1" "$CONFIG_FILE"; then
        sed -i "s/192\.168\.1\.1/$DEFAULT_IP/g" "$CONFIG_FILE"
        echo "   ✅ IP 地址已修改：$DEFAULT_IP"
    else
        echo "   ⚠️  未找到默认 IP 192.168.1.1，可能已修改"
    fi
    
    # 修改主机名（如果需要）
    if grep -q "OpenWrt" "$CONFIG_FILE"; then
        sed -i "s/OpenWrt/$DEFAULT_HOSTNAME/g" "$CONFIG_FILE"
        echo "   ✅ 主机名已修改：$DEFAULT_HOSTNAME"
    fi
else
    echo "   ❌ 未找到配置文件：$CONFIG_FILE"
fi

echo ""

# ========================================
# 2. 替换 Profile 文件
# ========================================
echo "📝 2. 检查 Profile 文件..."
PROFILE_FILE="package/base-files/files/etc/profile"

if [ -f "$PROFILE_FILE" ]; then
    echo "   ✅ Profile 文件存在"
    # 这里可以添加自定义的 profile 内容
    # 如果有自定义 profile 文件，可以复制过来
    if [ -f "files/etc/profile" ]; then
        cp "files/etc/profile" "$PROFILE_FILE"
        echo "   ✅ 已应用自定义 profile"
    fi
else
    echo "   ⚠️  Profile 文件不存在"
fi

echo ""

# ========================================
# 3. 替换 TTYD Banner
# ========================================
echo "🎨 3. 检查 TTYD Banner..."
BANNER_FILE="package/base-files/files/etc/banner"

if [ -f "$BANNER_FILE" ]; then
    echo "   ✅ Banner 文件存在"
    # 如果有自定义 banner 文件，可以复制过来
    if [ -f "files/etc/banner" ]; then
        cp "files/etc/banner" "$BANNER_FILE"
        echo "   ✅ 已应用自定义 banner"
    fi
else
    echo "   ⚠️  Banner 文件不存在"
fi

echo ""

# ========================================
# 4. 自定义固件版本显示
# ========================================
echo "📌 4. 检查固件版本显示配置..."
VERSION_FILE="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"

if [ -f "$VERSION_FILE" ]; then
    echo "   ✅ 版本文件存在"
    # 这里可以添加自定义版本信息的修改逻辑
    # 例如：sed -i 's/原内容/新内容/g' "$VERSION_FILE"
    echo "   ℹ️  如需修改版本显示，请手动编辑此文件"
else
    echo "   ⚠️  版本文件不存在，可能需要先更新 feeds"
fi

echo ""

# ========================================
# 5. 设置默认主题为 luci-theme-kucat
# ========================================
echo "🎭 5. 设置默认主题..."

# 5A. 注释掉其他主题的 mediaurlbase 设置
THEME_DIRS=$(find feeds -type d -name "luci-theme-*" 2>/dev/null)
for theme_dir in $THEME_DIRS; do
    uci_file=$(find "$theme_dir/root/etc/uci-defaults" -name "30-luci-*" 2>/dev/null | head -1)
    if [ -n "$uci_file" ] && [ -f "$uci_file" ]; then
        if grep -q "set luci.main.mediaurlbase" "$uci_file"; then
            sed -i 's/^set luci.main.mediaurlbase/# set luci.main.mediaurlbase/' "$uci_file"
            echo "   ✅ 已注释：$uci_file"
        fi
    fi
done

# 5B. 修改 luci Makefile 的主题依赖
LUCI_MAKEFILE="feeds/luci/collections/luci/Makefile"
if [ -f "$LUCI_MAKEFILE" ]; then
    if grep -q "LUCI_DEPENDS.*luci-theme" "$LUCI_MAKEFILE"; then
        # 备份
        cp "$LUCI_MAKEFILE" "${LUCI_MAKEFILE}.bak"
        # 修改为主题 kucat
        sed -i 's/LUCI_DEPENDS:=.*luci-theme-[a-zA-Z0-9_-]*/LUCI_DEPENDS:=luci-theme-kucat/' "$LUCI_MAKEFILE"
        echo "   ✅ 已修改 Makefile 主题依赖：$DEFAULT_THEME"
    else
        echo "   ⚠️  未在 Makefile 中找到主题依赖配置"
    fi
else
    echo "   ⚠️  未找到 LUCI Makefile"
fi

echo ""

# ========================================
# 6. 修改默认密码
# ========================================
echo "🔐 6. 修改默认密码..."
SHADOW_FILE="package/base-files/files/etc/shadow"

if [ -f "$SHADOW_FILE" ]; then
    # 备份原文件
    cp "$SHADOW_FILE" "${SHADOW_FILE}.bak"
    
    # 修改 root 用户密码（将第一个字段后的加密密码替换为空密码或使用 passwd 生成）
    # 这里使用空密码（不安全但方便），或者可以生成加密密码
    if grep -q "^root:" "$SHADOW_FILE"; then
        # 生成 passwd 的加密密码（使用 MD5）
        ENCRYPTED_PASS=$(openssl passwd -1 "passwd" 2>/dev/null || echo "*")
        if [ "$ENCRYPTED_PASS" != "*" ]; then
            sed -i "s/^root:[^:]*:/root:$ENCRYPTED_PASS:/" "$SHADOW_FILE"
            echo "   ✅ 已修改 root 密码为：passwd"
        else
            echo "   ⚠️  无法生成加密密码，保持原样"
        fi
    fi
else
    echo "   ❌ 未找到 shadow 文件：$SHADOW_FILE"
fi

echo ""

# ========================================
# 完成
# ========================================
echo "========================================"
echo "✅ 所有自定义修改已应用完成！"
echo "========================================"
echo ""
echo "📋 修改摘要:"
echo "   默认 IP:        $DEFAULT_IP"
echo "   主机名：$DEFAULT_HOSTNAME"
echo "   默认主题：$DEFAULT_THEME"
echo "   默认密码：passwd"
echo ""
echo "💡 下一步:"
echo "   1. 检查修改是否正确应用"
echo "   2. 运行 'make defconfig' 或 'make menuconfig'"
echo "   3. 开始编译固件"
echo ""
