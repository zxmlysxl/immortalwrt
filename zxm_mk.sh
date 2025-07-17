#!/bin/bash

set -e

# ========== 版本控制增强版 ==========
generate_version() {
    local week_map=("星期天" "星期一" "星期二" "星期三" "星期四" "星期五" "星期六")
    local week_str=${week_map[$(date +%w)]}
    echo "Z-ImmortalWrt $(date +"%Y%m%d%H%M%S") by 上网的蜗牛 ${week_str} | R$(date +%y.%m.%d)"
}

# 转义函数
escape_sed() {
    echo "$1" | sed -e 's/[\/&]/\\&/g'
}

# 生成并转义版本
CUSTOM_VER=$(generate_version)
ESCAPED_VER=$(escape_sed "$CUSTOM_VER")

# ========== 修改 Luci ==========
LUCI_JS="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"

# 使用 # 作为分隔符避免冲突
sed -i "s#_('Firmware Version'),.*#_('Firmware Version'), '$ESCAPED_VER'#" "$LUCI_JS"

# 计算并发数
calc_jobs() {
  local mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  local mem_mb=$(( mem_kb / 1024 ))
  local jobs=$(( mem_mb / 1500 ))
  echo $(( jobs > 0 ? jobs : 1 ))  # 至少1个线程
}

#开始编译
#make clean
make dirclean
git pull
./scripts/feeds update -a && ./scripts/feeds install -a
make download -j8
#make -j$(calc_jobs) V=s 2>&1 | tee build.log  #增量编译
make world -j$(calc_jobs) V=s 2>&1 | tee build.log  #完整编译

