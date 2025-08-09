#!/bin/bash

set -e

# 日志文件设置
LOG_FILE="z-$(date +"%Y%m%d").log"
# 配置参数
BACKUP_SOURCE="/home/zuoxm/backup/immortalwrt/files"
TARGET_DIR="files"

# 日志记录函数
log() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

# 备份.config
backup_config() {
    local backup_dir="/home/zuoxm/backup/immortalwrt"
    local timestamp=$(date +"%Y%m%d")
    local backup_file="${backup_dir}/.config-${timestamp}成功"
    
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

# 检查并恢复files目录
restore_files() {
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

}

# 脚本起始处立即执行备份
log "========== 开始本次编译 =========="
echo "========== 开始本次编译 =========="
log "清空build.log"
echo "清空build.log"
rm -f build.log
#恢复文件
restore_files

# 确保目录存在并写入编译信息
mkdir -p files/etc/ && \
echo "Z-ImmortalWrt $(date +"%Y%m%d%H%M") by zuoxm | R$(date +%y.%m.%d)" > files/etc/compile_info

# 配置
BUILD_LOG="build.log"          # 编译日志路径
MIN_FREE_SPACE_GB=10          # 降低磁盘空间要求
AUTO_PULL_TIMEOUT=3           # git pull 自动确认倒计时(秒)
MENU_TIMEOUT=15               # 新增：菜单选择超时时间(秒)

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
    
    if ! [[ "$available_mem" =~ ^[0-9]+$ ]]; then
        available_mem=$(free -g | awk '/Mem:/ {print $4}')
    fi
    
    if [ "$available_mem" -lt 6 ] 2>/dev/null; then
        log "内存不足，使用2线程"
        echo 2
    else
        local jobs=$(( total_cores > 8 ? 8 : total_cores ))
        log "计算得出使用 $jobs 线程"
        echo $jobs
    fi
    log "计算编译线程数完成"
}

# 下载线程计算
calc_dl_threads() {
    log "开始计算下载线程数"
    local total_cores=$(nproc --all)
    local threads=$(( total_cores > 8 ? 8 : total_cores ))
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

# 动态计时函数
dynamic_timer() {
    local msg="$1"
    local cmd="$2"
    
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
    
    # 修复：使用临时文件捕获输出
    local temp_log=$(mktemp)
    { eval "$cmd" 2>&1; echo $? > /tmp/exit_status; } | tee -a "$BUILD_LOG" > "$temp_log"
    local status=$(</tmp/exit_status)
    rm -f /tmp/exit_status
    
    local elapsed=$(( $(date +%s) - start ))
    
    if [ $status -eq 0 ]; then
        log "$msg 完成 (耗时: $(format_time $elapsed))"
        echo -e "\r${GREEN}✓ ${msg}完成 ($(format_time $elapsed))${NC} "
    else
        log "$msg 失败 (耗时: $(format_time $elapsed))"
        echo -e "\r${RED}✗ ${msg}失败 ($(format_time $elapsed))${NC} "
        # 显示最后5行错误日志
        tail -n 5 "$temp_log" | sed 's/^/    /'
        rm -f "$temp_log"
        exit 1
    fi
    rm -f "$temp_log"
}

# 检查git更新
check_git_updates() {
    log "开始检查Git更新"
    git remote update &>/dev/null
    local local_commit=$(git rev-parse @)
    local remote_commit=$(git rev-parse @{u})

    if [ "$local_commit" != "$remote_commit" ]; then
        log "发现远程仓库更新"
        echo -e "${YELLOW}⚠️  发现远程仓库更新${NC}"
        
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

# 核心编译流程
common_compile() {
    local DL_THREADS=$(calc_dl_threads)
    local COMPILE_JOBS=$(calc_jobs)
    
    dynamic_timer "更新 feeds" "./scripts/feeds update -a"
    dynamic_timer "安装 feeds" "./scripts/feeds install -a"
    dynamic_timer "安装 zuoxm包" "./scripts/feeds install -a -p zuoxm -f"
    
    # 带超时的menuconfig提示（新增）
    echo -e "\n${YELLOW}是否要调整配置? (${MENU_TIMEOUT}秒后自动跳过)${NC}"
    for (( i=MENU_TIMEOUT; i>0; i-- )); do
        printf "\r${CYAN}剩余时间: %2d秒 (按Y进入配置)${NC}" "$i"
        if read -t 1 -n 1 -r && [[ $REPLY =~ [Yy] ]]; then
            echo
            make menuconfig
            break
        fi
    done
    
    # 修复：使用独立进程检查make返回值
    dynamic_timer "下载源码" "make download -j${DL_THREADS}"
    
    log "开始编译 (使用 $COMPILE_JOBS 线程)"
    echo -e "\n${CYAN}▶ 开始编译 (使用 $COMPILE_JOBS 线程)...${NC}"
    echo -e "📝 日志实时输出到: ${YELLOW}$BUILD_LOG${NC}"
    
    local compile_start=$(date +%s)
    set +e  # 临时禁用set -e以捕获make错误
    make -j$COMPILE_JOBS V=s 2>&1 | tee -a "$BUILD_LOG"
    local make_status=${PIPESTATUS[0]}
    set -e
    
    if [ $make_status -ne 0 ]; then
        log "编译失败! (总耗时: $(($(date +%s)-compile_start))秒)"
        echo -e "${RED}❌ 编译失败! (总耗时: $(($(date +%s)-compile_start))秒)${NC}"
        echo -e "${YELLOW}最后5行错误日志:${NC}"
        tail -n 5 "$BUILD_LOG" | sed 's/^/    /'
        exit 1
    else
        log "编译成功! (总耗时: $(($(date +%s)-compile_start))秒)"
        echo -e "${GREEN}✓ 编译成功! (总耗时: $(($(date +%s)-compile_start))秒)${NC}"
        backup_config
        
        # ▼▼▼ 新增：编译成功后自动上传 ▼▼▼
        echo -e "\n${BLUE}⚡ 编译成功，开始上传固件...${NC}"
        if [ -f "/home/zuoxm/backup/immortalwrt/auto_upload.sh" ]; then
            /home/zuoxm/backup/immortalwrt/auto_upload.sh && {
                echo -e "${GREEN}✓ 固件上传完成！${NC}"
                log "固件上传成功"
            } || {
                echo -e "${RED}❌ 固件上传失败！${NC}"
                log "固件上传失败"
                exit 1  # 上传失败时终止脚本
            }
        else
            echo -e "${YELLOW}⚠️ 未找到上传脚本，跳过上传${NC}"
            log "警告：上传脚本不存在"
        fi
        # ▲▲▲ 新增代码结束 ▲▲▲
    fi
}

# 完整编译
full_compile() {
    log "开始完整编译流程"
    echo -e "\n${YELLOW}⚡ 执行内存安全完整编译...${NC}"
    check_git_updates
    echo -e "${YELLOW}♻️ 轻量级清理...${NC}"
    dynamic_timer "make clean" "make clean"
    common_compile
    echo -e "\n${GREEN}✅ 完整编译完成!${NC}"
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

# 超时自动选择菜单
timeout_menu() {
    echo -e "\n${BLUE}请选择编译模式 (${MENU_TIMEOUT}秒后自动选增量编译)${NC}"
    echo "1) 完整编译 (耗时较长)"
    echo "2) 增量编译 (推荐)"
    
    for (( i=MENU_TIMEOUT; i>0; i-- )); do
        printf "\r${YELLOW}剩余时间: %2d秒 (默认2)${NC}" "$i"
        if read -t 1 -n 1 -r choice; then
            echo
            case $choice in
                1) full_compile; break ;;
                2) quick_compile; break ;;
                *) echo -e "${RED}无效输入!${NC}"; continue ;;
            esac
        fi
    done
    
    # 超时默认选择
    if [ $i -eq 0 ]; then
        echo -e "\n${GREEN}▶ 超时未选择，默认执行增量编译${NC}"
        quick_compile
    fi
}

# 主流程
check_deps
check_disk_space
timeout_menu
log "======== 编译脚本执行完成 ========"
