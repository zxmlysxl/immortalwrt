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

#重命名固件
rename_efi_image() {
    log "开始重命名EFI固件文件"
    local build_date=$(date +"%Y%m%d")
    local efi_image=$(find bin/targets -name "*-efi.img.gz" | head -n 1)
    
    if [ -n "$efi_image" ]; then
        local dir_name=$(dirname "$efi_image")
        local base_name=$(basename "$efi_image" .img.gz)
        local new_name="Z-ImmWrt-${build_date}-zuoxm-x86_64-efi"
        
        # 创建临时目录
        local temp_dir=$(mktemp -d)
        
        # 解压.gz文件
        if gunzip -c "$efi_image" > "${temp_dir}/${base_name}.img"; then
            log "解压EFI固件成功"
            
            # 检查是否需要重命名（如果名称不同）
            if [ "${base_name}.img" != "${new_name}.img" ]; then
                # 重命名.img文件
                if mv "${temp_dir}/${base_name}.img" "${temp_dir}/${new_name}.img"; then
                    log "内部.img文件重命名成功"
                else
                    log "内部.img文件重命名失败"
                    echo -e "${RED}❌ 内部.img文件重命名失败${NC}"
                    rm -rf "$temp_dir"
                    return 1
                fi
            else
                log "内部.img文件无需重命名"
            fi
            
            # 重新压缩为.gz文件
            if gzip -c "${temp_dir}/${new_name}.img" > "${dir_name}/${new_name}.img.gz"; then
                log "固件重压缩成功"
                rm "$efi_image"  # 删除原文件
                log "固件重命名成功: ${new_name}.img.gz"
                echo -e "${GREEN}✓ 固件已重命名为: ${new_name}.img.gz${NC}"
            else
                log "固件重压缩失败"
                echo -e "${RED}❌ 固件重压缩失败${NC}"
            fi
        else
            log "解压EFI固件失败"
            echo -e "${RED}❌ 解压EFI固件失败${NC}"
        fi
        
        # 清理临时目录
        rm -rf "$temp_dir"
    else
        log "未找到EFI固件文件"
        echo -e "${YELLOW}⚠️ 未找到EFI固件文件${NC}"
    fi
    log "重命名EFI固件文件完成"
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

# 上传固件和插件
upload_artifacts() {
    local upload_firmware=$1
    local upload_plugins=$2
    
    if [ "$upload_firmware" -eq 1 ]; then
        echo -e "\n${BLUE}⚡ 开始上传固件...${NC}"
        if [ -f "/home/zuoxm/backup/immortalwrt/auto_upload.sh" ]; then
            /home/zuoxm/backup/immortalwrt/auto_upload.sh && {
                echo -e "${GREEN}✓ 固件上传完成！${NC}"
                log "固件上传成功"
            } || {
                echo -e "${RED}❌ 固件上传失败！${NC}"
                log "固件上传失败"
                return 1
            }
        else
            echo -e "${YELLOW}⚠️ 未找到固件上传脚本，跳过上传${NC}"
            log "警告：固件上传脚本不存在"
        fi
    fi
    
    if [ "$upload_plugins" -eq 1 ]; then
        echo -e "\n${BLUE}⚡ 开始上传插件...${NC}"
        if [ -f "/home/zuoxm/backup/immortalwrt/upload_plugins.sh" ]; then
            /home/zuoxm/backup/immortalwrt/upload_plugins.sh && {
                echo -e "${GREEN}✓ 插件上传完成！${NC}"
                log "插件上传成功"
            } || {
                echo -e "${RED}❌ 插件上传失败！${NC}"
                log "插件上传失败"
                return 1
            }
        else
            echo -e "${YELLOW}⚠️ 未找到插件上传脚本，跳过上传${NC}"
            log "警告：插件上传脚本不存在"
        fi
    fi
    
    return 0
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
MENU_TIMEOUT=15               # 菜单选择超时时间(秒)
UPLOAD_TIMEOUT=5              # 上传选择超时时间(秒)

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
    
    # 直接执行命令并捕获状态
    local status=0
    if eval "$cmd" 2>&1 | tee -a "$BUILD_LOG"; then
        status=${PIPESTATUS[0]}
    else
        status=${PIPESTATUS[0]}
    fi
    
    local elapsed=$(( $(date +%s) - start ))
    
    if [ $status -eq 0 ]; then
        log "$msg 完成 (耗时: $(format_time $elapsed))"
        echo -e "\r${GREEN}✓ ${msg}完成 ($(format_time $elapsed))${NC} "
    else
        log "$msg 失败 (耗时: $(format_time $elapsed))"
        echo -e "\r${RED}✗ ${msg}失败 ($(format_time $elapsed))${NC} "
        # 显示最后5行错误日志
        tail -n 5 "$BUILD_LOG" | sed 's/^/    /'
        exit 1
    fi
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
    local upload_firmware=$1  # 接收上传固件参数
    local upload_plugins=$2   # 接收上传插件参数
    local DL_THREADS=$(calc_dl_threads)
    local COMPILE_JOBS=$(calc_jobs)
    
    dynamic_timer "更新 feeds" "./scripts/feeds update -a"
    dynamic_timer "安装 feeds" "./scripts/feeds install -a"
    dynamic_timer "安装 zuoxm包" "./scripts/feeds install -a -p zuoxm -f"
    
    # 带超时的menuconfig提示
    echo -e "\n${YELLOW}是否要调整配置? (${MENU_TIMEOUT}秒后自动跳过)${NC}"
    for (( i=MENU_TIMEOUT; i>0; i-- )); do
        printf "\r${CYAN}剩余时间: %2d秒 (按Y进入配置，其他键继续)${NC}" "$i"
        if read -t 1 -n 1 -r; then
           echo  # 换行
           if [[ $REPLY =~ [Yy] ]]; then
                # 进入menuconfig，退出后会继续后续编译
                make menuconfig
                break
            else
                # 按其他键立即继续
                echo -e "${GREEN}跳过配置调整，继续编译...${NC}"
                break
            fi
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
        
        # 重命名EFI固件文件
        rename_efi_image
        
        backup_config
        
        # 上传固件和插件
        upload_artifacts $upload_firmware $upload_plugins
    fi
}

# 完整编译
full_compile() {
    local upload_firmware=$1  # 接收上传固件参数
    local upload_plugins=$2   # 接收上传插件参数
    log "开始完整编译流程"
    echo -e "\n${YELLOW}⚡ 执行内存安全完整编译...${NC}"
    check_git_updates
    echo -e "${YELLOW}♻️ 保留配置清理...${NC}"
    dynamic_timer "执行make dirclean" "make dirclean"
    common_compile $upload_firmware $upload_plugins
    echo -e "\n${GREEN}✅ 完整编译完成!${NC}"
    log "完整编译流程完成"
}

# 增量编译
quick_compile() {
    local upload_firmware=$1  # 接收上传固件参数
    local upload_plugins=$2   # 接收上传插件参数
    log "开始增量编译流程"
    echo -e "\n${YELLOW}⚡ 执行增量编译 (跳过清理)...${NC}"
    check_git_updates
    common_compile $upload_firmware $upload_plugins
    echo -e "\n${GREEN}✅ 增量编译完成!${NC}"
    log "增量编译流程完成"
}

# 超时自动选择菜单
timeout_menu() {
    # 默认选项
    local default_compile=2      # 1=完整编译, 2=增量编译
    local default_upload_firmware=1  # 0=不上传固件, 1=上传固件
    local default_upload_plugins=1   # 0=不上传插件, 1=上传插件

    echo -e "\n${BLUE}请选择编译模式 (${MENU_TIMEOUT}秒后自动选增量编译)${NC}"
    echo "1) 完整编译 (耗时较长)"
    echo "2) 增量编译 (推荐)"
    
    # 编译模式选择
    for (( i=MENU_TIMEOUT; i>0; i-- )); do
        printf "\r${YELLOW}剩余时间: %2d秒 (默认2)${NC}" "$i"
        if read -t 1 -n 1 -r choice; then
            echo
            case $choice in
                1) default_compile=1; break ;;
                2) default_compile=2; break ;;
                *) echo -e "${RED}无效输入!${NC}"; ((i++)); continue ;;
            esac
        fi
    done
    
    # 上传固件选择
    echo -e "\n${BLUE}是否上传固件? (${UPLOAD_TIMEOUT}秒后默认上传)${NC}"
    echo "y) 上传固件 (推荐)"
    echo "n) 不上传"
    
    for (( i=UPLOAD_TIMEOUT; i>0; i-- )); do
        printf "\r${YELLOW}剩余时间: %2d秒 (默认y)${NC}" "$i"
        if read -t 1 -n 1 -r upload; then
            echo
            case $upload in
                [Yy]) default_upload_firmware=1; break ;;
                [Nn]) default_upload_firmware=0; break ;;
                *) echo -e "${RED}无效输入!${NC}"; ((i++)); continue ;;
            esac
        fi
    done
    
    # 上传插件选择
    echo -e "\n${BLUE}是否上传插件? (${UPLOAD_TIMEOUT}秒后默认上传)${NC}"
    echo "y) 上传插件 (推荐)"
    echo "n) 不上传"
    
    for (( i=UPLOAD_TIMEOUT; i>0; i-- )); do
        printf "\r${YELLOW}剩余时间: %2d秒 (默认y)${NC}" "$i"
        if read -t 1 -n 1 -r upload; then
            echo
            case $upload in
                [Yy]) default_upload_plugins=1; break ;;
                [Nn]) default_upload_plugins=0; break ;;
                *) echo -e "${RED}无效输入!${NC}"; ((i++)); continue ;;
            esac
        fi
    done
    
    # 执行选择
    case $default_compile in
        1) full_compile $default_upload_firmware $default_upload_plugins ;;
        2) quick_compile $default_upload_firmware $default_upload_plugins ;;
    esac
}

# 主流程
check_deps
check_disk_space
timeout_menu
log "======== 编译脚本执行完成 ========"
