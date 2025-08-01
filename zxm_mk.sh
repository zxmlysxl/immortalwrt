#!/bin/bash

set -e

echo "Z-ImmortalWrt $(date +"%Y%m%d%H%M") by zuoxm | R$(date +%y.%m.%d)" > files/etc/compile_info

# 配置
LOG_FILE="build.log"          # 编译日志路径
DL_THREADS=8                  # 下载线程数
MIN_FREE_SPACE_GB=20          # 最小剩余磁盘空间（GB）
AUTO_PULL_TIMEOUT=3           # git pull 自动确认倒计时(秒)

# 颜色定义
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

# 动态计时函数 (需安装pv)
dynamic_timer() {
    local msg="$1"
    local cmd="$2"
    
    # 时间格式化函数（内部使用）
    format_time() {
        local total_seconds=$1
        local minutes=$((total_seconds / 60))
        local seconds=$((total_seconds % 60))
        
        if (( minutes > 0 )); then
            printf "%d分%02d秒" "$minutes" "$seconds"
        else
            printf "%d秒" "$seconds"
        fi
    }

    echo -ne "${CYAN}▶ ${msg}...0秒${NC}"
    local start=$(date +%s)
    
    # 执行命令（后台运行）
    (eval "$cmd" &>> "$LOG_FILE") &
    local pid=$!
    
    # 动态计时循环
    while kill -0 "$pid" 2>/dev/null; do
        local elapsed=$(( $(date +%s) - start ))
        echo -ne "\r${CYAN}▶ ${msg}...$(format_time $elapsed)${NC}"
        sleep 1
    done
    
    wait "$pid"  # 等待命令完成
    local elapsed=$(( $(date +%s) - start ))
    echo -e "\r${GREEN}✓ ${msg}完成 ($(format_time $elapsed))${NC} "
}

# 检查git更新（带倒计时自动确认）
check_git_updates() {
    git remote update &>/dev/null
    local local_commit=$(git rev-parse @)
    local remote_commit=$(git rev-parse @{u})

    if [ "$local_commit" != "$remote_commit" ]; then
        echo -e "${YELLOW}⚠️  发现远程仓库更新${NC}"
        
        # 倒计时自动确认
        for (( i=AUTO_PULL_TIMEOUT; i>0; i-- )); do
            printf "\r${CYAN}将在 %d 秒后自动更新 (按任意键取消)...${NC}" "$i"
            read -t 1 -n 1 -r && break
        done
        
        if [ $? -eq 0 ]; then
            echo
            read -p "确认更新? [Y/n] " -n 1 -r
            echo
            [[ ! $REPLY =~ ^[Nn]$ ]] && dynamic_timer "拉取代码" "git pull"
        else
            echo -e "\n${GREEN}▶ 自动执行更新...${NC}"
            dynamic_timer "拉取代码" "git pull"
        fi
    fi
}

# 公共编译流程
common_compile() {
    dynamic_timer "更新 feeds" "./scripts/feeds update -a"
    dynamic_timer "安装 feeds" "./scripts/feeds install -a"
    dynamic_timer "下载源码" "make download -j$DL_THREADS"
    
    local jobs=$(calc_jobs)
    echo -e "${CYAN}▶ 开始编译 (使用 $jobs 线程)...${NC}"
    echo -e "📝 日志实时输出到: ${YELLOW}$LOG_FILE${NC}"
    
    local compile_start=$(date +%s)
    if ! make -j$jobs V=s 2>&1 | tee -a "$LOG_FILE"; then
        echo -e "${RED}❌ 编译失败! (总耗时: $(($(date +%s)-compile_start))秒)${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ 编译成功! (总耗时: $(($(date +%s)-compile_start))秒)${NC}"
}

# 完整编译
full_compile() {
    echo -e "\n${YELLOW}⚡ 执行完整编译...${NC}"
    check_git_updates
    
    echo -e "${YELLOW}♻️ 清理旧编译文件...${NC}"
    dynamic_timer "make clean" "make clean"
    dynamic_timer "make dirclean" "make dirclean"
    
    common_compile
    echo -e "\n${GREEN}✅ 完整编译成功!${NC}"
}

# 快速编译
quick_compile() {
    echo -e "\n${YELLOW}⚡ 执行快速编译...${NC}"
    check_git_updates
    common_compile
    echo -e "\n${GREEN}✅ 快速编译成功!${NC}"
}

# 其他函数保持不变（calc_jobs/check_deps/check_disk_space/show_menu等）
# [...] (保留之前的函数定义)

# 初始化
check_deps
check_disk_space
show_menu
