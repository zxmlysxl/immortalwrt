#!/bin/bash
set -e

# ========== 版本控制增强版 ==========
generate_version() {
    local week_map=("星期天" "星期一" "星期二" "星期三" "星期四" "星期五" "星期六")
    local week_str=${week_map[$(date +%w)]}
    echo "Z-ImmortalWrt $(date +"%Y%m%d%H%M%S") by 上网的蜗牛 ${week_str} | R$(date +%y.%m.%d)"
}

# 生成统一版本号
CUSTOM_VER=$(generate_version)

# 核心版本文件（三保险）
mkdir -p files/etc
echo "OPENWRT_RELEASE='$CUSTOM_VER'" > files/etc/os-release
echo "DISTRIB_DESCRIPTION='$CUSTOM_VER'" > files/etc/openwrt_release
echo "$CUSTOM_VER" > files/etc/compile_info

# 修改Luci显示源（直接硬编码）
LUCI_JS="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/10_system.js"
sed -i "s|_('Firmware Version'),.*|_('Firmware Version'), '$CUSTOM_VER'|" "$LUCI_JS"

# ========== 智能编译优化 ==========
calc_jobs() {
    local mem_gb=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024))
    local cpu_cores=$(nproc)
    echo $(( cpu_cores < mem_gb ? (cpu_cores < 8 ? cpu_cores : 8) : (mem_gb < 8 ? mem_gb : 8) ))
}

# 增量编译支持
if [ "$1" = "incremental" ]; then
    echo "增量编译模式"
    CLEAN_CMD=""
else
    echo "全新编译模式"
    CLEAN_CMD="make dirclean"
    
    # 保留dl目录
    [ -d "dl" ] && mv dl /tmp/openwrt_dl_backup
fi

# 执行编译
$CLEAN_CMD
./scripts/feeds update -a
./scripts/feeds install -a --skip-installed
make -j$(calc_jobs) V=s 2>&1 | tee build.log

# 恢复dl目录
[ -d "/tmp/openwrt_dl_backup" ] && mv /tmp/openwrt_dl_backup dl

# 结果检查
if grep -q "ERROR:" build.log; then
    echo "编译失败！关键错误："
    grep -m 3 -A 5 -B 5 "ERROR:" build.log
    exit 1
fi

# 版本验证
echo "================ 固件信息 ================"
echo "自定义版本：$CUSTOM_VER"
echo "文件验证："
tar -Oxf bin/targets/*/*/openwrt-*-rootfs.tar.gz etc/os-release | grep OPENWRT_RELEASE
echo "编译耗时：$(($SECONDS / 60))分$(($SECONDS % 60))秒"
