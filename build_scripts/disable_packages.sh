#!/bin/bash
# 禁用特定插件的脚本
# 在 feeds install 后运行，屏蔽不需要的包

set -e

echo "🔧 开始禁用不需要的插件..."

# 禁用 plugins 相关包
if grep -q "CONFIG_PACKAGE_luci-app-plugins=y" .config 2>/dev/null; then
    sed -i 's/CONFIG_PACKAGE_luci-app-plugins=y/# CONFIG_PACKAGE_luci-app-plugins is not set/' .config
    echo "✅ 已禁用 luci-app-plugins"
fi

# 禁用 usage 相关包  
if grep -q "CONFIG_PACKAGE_luci-app-usage=y" .config 2>/dev/null; then
    sed -i 's/CONFIG_PACKAGE_luci-app-usage=y/# CONFIG_PACKAGE_luci-app-usage is not set/' .config
    echo "✅ 已禁用 luci-app-usage"
fi

# 同时禁用 cpusage (如果启用的话)
if grep -q "CONFIG_PACKAGE_cpusage=y" .config 2>/dev/null; then
    sed -i 's/CONFIG_PACKAGE_cpusage=y/# CONFIG_PACKAGE_cpusage is not set/' .config
    echo "✅ 已禁用 cpusage"
fi

echo "✨ 插件禁用完成"
