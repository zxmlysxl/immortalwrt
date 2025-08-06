#!/bin/bash

set -e

# 日志文件设置（放在当前文件夹下）
LOG_FILE="z-$(date +"%Y%m%d").log"

# 日志记录函数
log() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

# 初始备份（脚本启动立即执行）
backup_config() {
    local backup_dir="/home/zuoxm/backup/immortalwrt"
    local timestamp=$(date +"%Y%m%d")
    local backup_file="${backup_dir}/.config-${timestamp}"
    
    mkdir -p "$backup_dir"
    
    log "开始备份配置"
    if [ -f .config ]; then
        if cp .config "$backup_file"; then
            log "配置备份成功: ${backup_file}"
            echo -e "${GREEN}✓ 配置已备份: ${backup_file}${NC}"
        else
            log "备份失败！请检查目录权限"
            echo -e "${RED}❌ 备份失败！请检查目录权限${NC}"
            exit 1
        fi
    else
        log "未找到.config文件，跳过备份"
        echo -e "${YELLOW}⚠️ 未找到.config文件，跳过备份${NC}"
    fi
    log "备份配置完成"
}

# 脚本起始处立即执行备份
log "========== 开始本次编译 =========="

# 配置参数
BACKUP_SOURCE="/home/zuoxm/backup/immortalwrt/files"
TARGET_DIR="files"

# 检查并恢复files目录
restore_files() {
    if [ ! -d "$TARGET_DIR" ]; then
        if [ -d "$BACKUP_SOURCE" ]; then
            echo -e "${CYAN}▶ 恢复files目录...${NC}"
            if cp -r "$BACKUP_SOURCE" .; then
                echo -e "${GREEN}✓ files目录恢复完成${NC}"
            else
                echo -e "${RED}❌ files目录恢复失败！${NC}"
                exit 1
            fi
        else
            echo -e "${YELLOW}⚠️ 备份源不存在: $BACKUP_SOURCE ${NC}"
        fi
    else
        echo -e "${BLUE}ℹ️ files目录已存在，跳过恢复${NC}"
    fi
}

# 确保目录存在并写入编译信息
mkdir -p files/etc/ && \
echo "Z-ImmortalWrt $(date +"%Y%m%d%H%M") by zuoxm | R$(date +%y.%m.%d)" > files/etc/compile_info

# 配置
BUILD_LOG="build.log"          # 编译日志路径
MIN_FREE_SPACE_GB=10          # 降低磁盘空间要求
AUTO_PULL_TIMEOUT=3           # git pull 自动确认倒计时(秒)

# 颜色定义
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

# 优化的线程计算
calc_jobs() {
    log "开始计算编译线程数"
    local total_cores=$(nproc --all)
    local available_mem=$(free -g | awk '/Mem:/ {print $7}')
    
    # 确保available_mem是数字
    if ! [[ "$available_mem" =~ ^[0-9]+$ ]]; then
        available_mem=$(free -g | awk '/Mem:/ {print $4}')  # 尝试获取不同的列
    fi
    
    # 内存限制规则：
    if [ "$available_mem" -lt 6 ] 2>/dev/null; then
        log "内存不足，使用2线程"
        echo 2   # 内存不足时强制2线程
    else
        # 不超过总核心数且至少保留1GB内存
        local jobs=$(( total_cores > 8 ? 8 : total_cores ))  # 最大不超过8线程
        log "计算得出使用 $jobs 线程"
        echo $jobs
    fi
    log "计算编译线程数完成"
}

# 下载线程计算（独立于编译线程）
calc_dl_threads() {
    log "开始计算下载线程数"
    local total_cores=$(nproc --all)
    local threads=$(( total_cores > 8 ? 8 : total_cores ))  # 下载最大8线程
    log "计算得出使用 $threads 下载线程"
    echo $threads
}

# 检查依赖工具
check_deps() {
    log "开始检查依赖工具"
    local missing=()
    for cmd in git make rsync wget; do
        if ! command -v $cmd &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log "缺少依赖工具: ${missing[*]}"
        echo -e "${RED}❌ 缺少依赖工具: ${missing[*]}${NC}"
        exit 1
    fi
    log "依赖工具检查完成"
}

# 检查磁盘空间
check_disk_space() {
    log "开始检查磁盘空间"
    local free_space=$(df -BG . | awk 'NR==2 {print $4}' | tr -d 'G')
    if [ "$free_space" -lt "$MIN_FREE_SPACE_GB" ]; then
        log "磁盘空间不足! 需要至少 ${MIN_FREE_SPACE_GB}G，当前剩余 ${free_space}G"
        echo -e "${RED}❌ 磁盘空间不足! 需要至少 ${MIN_FREE_SPACE_GB}G，当前剩余 ${free_space}G${NC}"
        exit 1
    fi
    log "磁盘空间检查完成，剩余 ${free_space}G"
}

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

    log "开始执行: $msg"
    echo -ne "${CYAN}▶ ${msg}...0秒${NC}"
    local start=$(date +%s)
    
    # 执行命令（后台运行）
    (eval "$cmd" &>> "$BUILD_LOG") &
    local pid=$!
    
    # 动态计时循环
    while kill -0 "$pid" 2>/dev/null; do
        local elapsed=$(( $(date +%s) - start ))
        echo -ne "\r${CYAN}▶ ${msg}...$(format_time $elapsed)${NC}"
        sleep 1
    done
    
    wait "$pid"  # 等待命令完成
    local status=$?
    local elapsed=$(( $(date +%s) - start ))
    
    if [ $status -eq 0 ]; then
        log "$msg 完成 (耗时: $(format_time $elapsed))"
        echo -e "\r${GREEN}✓ ${msg}完成 ($(format_time $elapsed))${NC} "
    else
        log "$msg 失败 (耗时: $(format_time $elapsed))"
        echo -e "\r${RED}✗ ${msg}失败 ($(format_time $elapsed))${NC} "
        exit 1
    fi
}

# 检查git更新（带倒计时自动确认）
check_git_updates() {
    log "开始检查Git更新"
    git remote update &>/dev/null
    local local_commit=$(git rev-parse @)
    local remote_commit=$(git rev-parse @{u})

    if [ "$local_commit" != "$remote_commit" ]; then
        log "发现远程仓库更新"
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
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                dynamic_timer "拉取代码" "git pull"
            else
                log "用户取消更新"
            fi
        else
            echo -e "\n${GREEN}▶ 自动执行更新...${NC}"
            dynamic_timer "拉取代码" "git pull"
        fi
    else
        log "没有发现Git更新"
    fi
    log "Git更新检查完成"
}

common_compile() {
    local DL_THREADS=$(calc_dl_threads)
    local COMPILE_JOBS=$(calc_jobs)
    
    dynamic_timer "更新 feeds" "./scripts/feeds update -a"
    dynamic_timer "安装 feeds" "./scripts/feeds install -a"
    
    # 添加带15秒倒计时的menuconfig提示
    echo -e "\n${YELLOW}════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  是否要现在调整配置选项？（15秒后自动继续）${NC}"
    echo -e "${CYAN}  输入 ${GREEN}Y${CYAN} 进入menuconfig界面修改配置${NC}"
    echo -e "${CYAN}  输入 ${GREEN}N${CYAN} 或直接回车继续编译流程${NC}"
    echo -e "${YELLOW}════════════════════════════════════════${NC}"
    
    # 15秒倒计时逻辑
    for (( i=15; i>0; i-- )); do
        printf "\r${BLUE}剩余时间: %2d 秒 (自动选择N)${NC} " "$i"
        if read -t 1 -n 1 -r answer; then
            echo  # 用户输入后换行
            REPLY="$answer"
            break
        fi
    done
    
    # 用户未输入时自动继续
    if [ -z "$REPLY" ]; then
        echo -e "\n${BLUE}ℹ️ 超时未选择，自动继续编译...${NC}"
        REPLY="n"
    fi
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "用户选择修改menuconfig"
        echo -e "\n${GREEN}▶ 启动menuconfig配置界面...${NC}"
        echo -e "${CYAN}修改完成后，退出界面将自动继续编译${NC}"
        make menuconfig
        echo -e "\n${GREEN}✓ menuconfig配置已完成${NC}"
    else
        log "用户跳过menuconfig修改"
        echo -e "\n${BLUE}ℹ️ 使用现有配置继续编译...${NC}"
    fi
    
    # 备份.config
    backup_config
    
    # 使用更多线程下载
    echo -e "\n${CYAN}▶ 使用 ${DL_THREADS} 线程下载源码...${NC}"
    dynamic_timer "下载源码" "make download -j${DL_THREADS}"
    
    log "开始编译 (使用 $COMPILE_JOBS 线程)"
    echo -e "\n${CYAN}▶ 开始编译 (使用 $COMPILE_JOBS 线程)...${NC}"
    echo -e "📝 日志实时输出到: ${YELLOW}$BUILD_LOG${NC}"
    
    local compile_start=$(date +%s)
    if ! make -j$COMPILE_JOBS V=s 2>&1 | tee -a "$BUILD_LOG"; then
        log "编译失败! (总耗时: $(($(date +%s)-compile_start))秒)"
        echo -e "${RED}❌ 编译失败! (总耗时: $(($(date +%s)-compile_start))秒)${NC}"
        exit 1
    fi
    log "编译成功! (总耗时: $(($(date +%s)-compile_start))秒)"
    echo -e "${GREEN}✓ 编译成功! (总耗时: $(($(date +%s)-compile_start))秒)${NC}"
}

# 完整编译（内存优化版）
full_compile() {
    log "开始完整编译流程"
    echo -e "\n${YELLOW}⚡ 执行内存安全完整编译...${NC}"
    check_git_updates
    
    echo -e "${YELLOW}♻️ 轻量级清理...${NC}"
    dynamic_timer "make clean" "make clean"  # 不执行dirclean节省内存
    
    common_compile
    echo -e "\n${GREEN}✅ 完整编译完成!${NC}"
    echo -e "${BLUE}ℹ️ 内存使用报告:${NC}"
    free -h | tee -a "$LOG_FILE"
    log "完整编译流程完成"
}

# 增量编译
quick_compile() {
    log "开始增量编译流程"
    echo -e "\n${YELLOW}⚡ 执行增量编译 (跳过清理)...${NC}"
    check_git_updates
    common_compile
    echo -e "\n${GREEN}✅ 增量编译完成!${NC}"
    log "增量编译流程完成"
}

# 交互式菜单
show_menu() {
    log "显示交互菜单"
    echo -e "\n${BLUE}OpenWrt编译助手 (多核优化版)${NC}"
    echo "1) 完整编译"
    echo "2) 增量编译"
    echo "3) 退出"
    
    while true; do
        read -p "请选择: " choice
        case $choice in
            1) full_compile; break ;;
            2) quick_compile; break ;;
            3) log "用户选择退出"; exit 0 ;;
            *) 
                log "无效选项: $choice"
                echo -e "${RED}无效选项!${NC}" 
            ;;
        esac
    done
    log "菜单选择完成"
}

# 初始化
log "开始初始化检查"
check_deps
check_disk_space
show_menu
log "===== 编译脚本执行完成 ====="
