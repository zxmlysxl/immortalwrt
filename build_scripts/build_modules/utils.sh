#!/bin/bash

# 颜色定义
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

# 日志函数
log() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

# ========== 通知函数 ==========
send_notification() {
    local type=$1
    shift
    
    local python_service="${MODULES_DIR}/notification_service.py"
    
    if [ -f "$python_service" ]; then
        python3 "$python_service" "$type" "$@"
        return $?
    else
        echo -e "${YELLOW}⚠️  通知服务不可用，跳过通知${NC}"
        log "通知服务不存在: $python_service"
        return 1
    fi
}

send_start_notification() {
    echo -e "${CYAN}▶ 发送开始通知...${NC}"
    send_notification "start"
}

send_success_notification() {
    local total_time=$1
    local compile_time=${2:-0}
    
    echo -e "${GREEN}▶ 发送成功通知...${NC}"
    if [ "$compile_time" -gt 0 ]; then
        send_notification "success" "$total_time" "$compile_time"
    else
        send_notification "success" "$total_time"
    fi
}

send_error_notification() {
    local error_type=$1
    local message=$2
    local elapsed_time=${3:-0}
    
    echo -e "${RED}▶ 发送错误通知...${NC}"
    if [ "$elapsed_time" -gt 0 ]; then
        send_notification "error" "$error_type" "$message" "$elapsed_time"
    else
        send_notification "error" "$error_type" "$message"
    fi
}

send_upload_notification() {
    local upload_type=$1
    local status=$2
    
    echo -e "${CYAN}▶ 发送上传通知...${NC}"
    send_notification "upload" "$upload_type" "$status" "$(date +"%H:%M:%S")"
}

# ========== 上传函数 ==========
upload_artifacts() {
    local upload_firmware=$1
    local upload_plugins=$2
    
    log "开始上传任务: firmware=$upload_firmware, plugins=$upload_plugins"
    
    # 上传固件
    if [ "$upload_firmware" -eq 1 ]; then
        echo -e "\n${BLUE}⚡ 开始上传固件...${NC}"
        
        if [ -f "$UPLOAD_FIRMWARE_SCRIPT" ]; then
            if bash "$UPLOAD_FIRMWARE_SCRIPT"; then
                echo -e "${GREEN}✓ 固件上传完成！${NC}"
                log "固件上传成功"
                send_upload_notification "固件" "success"
            else
                echo -e "${RED}❌ 固件上传失败！${NC}"
                log "固件上传失败"
                send_upload_notification "固件" "failure"
                return 1
            fi
        else
            echo -e "${YELLOW}⚠️ 未找到固件上传脚本${NC}"
        fi
    fi
    
    # 上传插件
    if [ "$upload_plugins" -eq 1 ]; then
        echo -e "\n${BLUE}⚡ 开始上传插件...${NC}"
        
        if [ -f "$UPLOAD_PLUGINS_SCRIPT" ]; then
            if bash "$UPLOAD_PLUGINS_SCRIPT"; then
                echo -e "${GREEN}✓ 插件上传完成！${NC}"
                log "插件上传成功"
                send_upload_notification "插件" "success"
            else
                echo -e "${RED}❌ 插件上传失败！${NC}"
                log "插件上传失败"
                send_upload_notification "插件" "failure"
                return 1
            fi
        else
            echo -e "${YELLOW}⚠️ 未找到插件上传脚本${NC}"
        fi
    fi
    
    log "上传任务完成"
    return 0
}

# ========== 恢复文件函数 ==========
restore_files() {
    if [ -d "$BACKUP_SOURCE" ]; then
        echo -e "${CYAN}▶ 恢复files目录...${NC}"
        log "恢复文件: $BACKUP_SOURCE -> $PROJECT_DIR/files"
        
        mkdir -p "$PROJECT_DIR/files"
        
        if cp -r "$BACKUP_SOURCE" "$PROJECT_DIR/"; then
            echo -e "${GREEN}✓ files目录恢复完成${NC}"
            log "文件恢复成功"
        else
            echo -e "${RED}❌ files目录恢复失败！${NC}"
            log "文件恢复失败"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠️ 备份源不存在，跳过文件恢复${NC}"
        log "备份源不存在: $BACKUP_SOURCE"
    fi
}

# ========== 检测删除官方tailscale文件函数 ==========
modify_tailscale_makefile() {
    local makefile_path="${1:-feeds/packages/net/tailscale/Makefile}"
    
    if [ ! -f "$makefile_path" ]; then
        echo "⏭️  未找到 Tailscale Makefile，跳过修改"
        return 0
    fi
    
    echo "修改 Tailscale Makefile: $makefile_path"
    
    # 执行修改
    sed -i '/\/etc\/init\.d\/tailscale/d;/\/etc\/config\/tailscale/d;' "$makefile_path"
    
    # 验证修改
    if grep -q "/etc/init.d/tailscale" "$makefile_path" || grep -q "/etc/config/tailscale" "$makefile_path"; then
        echo "❌ 修改失败，恢复备份"
        return 1
    fi
    
    echo "✅ Tailscale Makefile 修改成功"
    
    return 0
}

# ========== 工具函数 ==========
calc_jobs() {
    local total_cores=$(nproc --all)
    local available_mem=$(free -g | awk '/Mem:/ {print $7}')
    
    if ! [[ "$available_mem" =~ ^[0-9]+$ ]]; then
        available_mem=$(free -g | awk '/Mem:/ {print $4}')
    fi
    
    if [ "$available_mem" -lt 6 ] 2>/dev/null; then
        echo 2
    else
        local jobs=$(( total_cores > 8 ? 8 : total_cores ))
        echo $jobs
    fi
}

calc_dl_threads() {
    local total_cores=$(nproc --all)
    local threads=$(( total_cores > 8 ? 8 : total_cores ))
    echo $threads
}

check_deps() {
    local missing=()
    for cmd in git make rsync wget curl; do
        if ! command -v $cmd &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}❌ 缺少依赖工具: ${missing[*]}${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 依赖检查通过${NC}"
    return 0
}

check_disk_space() {
    local free_space
    local min_space=${MIN_FREE_SPACE_GB:-5}
    
    echo -e "${CYAN}磁盘空间检查:${NC}"
    
    if command -v df >/dev/null 2>&1; then
        free_space=$(df -BG "$PROJECT_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G')
    else
        echo -e "${YELLOW}⚠️  无法检查磁盘空间${NC}"
        return 0
    fi
    
    if ! [[ "$free_space" =~ ^[0-9]+$ ]]; then
        echo -e "${YELLOW}⚠️  无法解析磁盘空间，跳过检查${NC}"
        return 0
    fi
    
    echo "项目目录: $PROJECT_DIR"
    echo "可用空间: ${free_space}GB"
    echo "最小要求: ${min_space}GB"
    
    if [ "$free_space" -lt "$min_space" ]; then
        echo -e "${RED}❌ 磁盘空间不足!${NC}"
        return 1
    else
        echo -e "${GREEN}✓ 磁盘空间充足${NC}"
        return 0
    fi
}

dynamic_timer() {
    local msg="$1"
    local cmd="$2"
    local log_file="${3:-$BUILD_LOG}"
    
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
    echo -ne "${CYAN}▶ ${msg}...${NC}"
    local start=$(date +%s)
    
    local status=0
    if eval "$cmd" 2>&1 | tee -a "$log_file"; then
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
        return 1
    fi
}

check_git_updates() {
    git remote update &>/dev/null
    local local_commit=$(git rev-parse @)
    local remote_commit=$(git rev-parse @{u})

    if [ "$local_commit" != "$remote_commit" ]; then
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
            fi
        else
            echo -e "\n${GREEN}▶ 自动执行更新...${NC}"
            dynamic_timer "拉取代码" "git pull"
        fi
    fi
}

# 修改前：
rename_efi_image() {
    log "开始重命名EFI固件文件"
    local build_date=$(date +"%Y%m%d")
    local target_dir="${PROJECT_DIR}/bin/targets/x86/64"
    local backup_dir="${target_dir}/old_firmwares"
    
    # 创建备份目录
    mkdir -p "${backup_dir}" 2>/dev/null || true
    
    # 清理旧的Z-ImmWrt固件文件，保留最新一个作为备份
    echo -e "${CYAN}▶ 整理固件文件...${NC}"
    
    # 查找所有旧的Z-ImmWrt固件
    local old_files=($(find "${target_dir}" -maxdepth 1 -type f -name "Z-ImmWrt-*.img.gz" -printf "%T@ %p\n" 2>/dev/null | sort -rn | cut -d' ' -f2-))
    
    if [ ${#old_files[@]} -gt 0 ]; then
        echo "找到 ${#old_files[@]} 个旧的Z-ImmWrt固件"
        
        # 如果有多个旧文件，保留最新的一个，移动其他到备份目录
        for ((i=1; i<${#old_files[@]}; i++)); do
            local old_file="${old_files[$i]}"
            local backup_name="old_$(basename "${old_file}")"
            echo "备份: $(basename "${old_file}") -> ${backup_dir}/${backup_name}"
            mv -f "${old_file}" "${backup_dir}/${backup_name}" 2>/dev/null || true
        done
        
        # 如果最新的旧文件不是今天日期的，也备份它
        local latest_old="${old_files[0]}"
        if [[ "$latest_old" != *"${build_date}"* ]]; then
            echo "备份非今日固件: $(basename "${latest_old}")"
            mv -f "${latest_old}" "${backup_dir}/old_$(basename "${latest_old}")" 2>/dev/null || true
        fi
        
        echo -e "${GREEN}✓ 旧固件整理完成${NC}"
        log "整理旧固件: ${#old_files[@]} 个文件"
    fi
    
    # 查找最新的EFI固件
    local efi_image=$(find "${target_dir}" -maxdepth 1 -type f -name "*-efi.img.gz" ! -name "Z-ImmWrt-*" | head -n 1)
    
    if [ -z "${efi_image}" ]; then
        # 如果没有找到非Z-ImmWrt的efi文件，尝试查找任何efi文件
        efi_image=$(find "${target_dir}" -maxdepth 1 -type f -name "*-efi.img.gz" | head -n 1)
    fi
    
    if [ -n "${efi_image}" ]; then
        local original_name=$(basename "${efi_image}")
        local new_name="Z-ImmWrt-${build_date}-zuoxm-x86_64-efi.img.gz"
        local new_path="${target_dir}/${new_name}"
        
        # 如果目标文件已存在，先删除
        if [ -f "${new_path}" ]; then
            echo -e "${YELLOW}⚠️  删除已存在的同名文件: ${new_name}${NC}"
            rm -f "${new_path}"
        fi
        
        echo -e "${CYAN}▶ 重命名固件: ${original_name} -> ${new_name}${NC}"
        
        # 直接重命名
        if mv -f "${efi_image}" "${new_path}"; then
            local final_size=$(stat -c%s "${new_path}" 2>/dev/null || echo "unknown")
            local size_display=""
            
            if [[ "$final_size" =~ ^[0-9]+$ ]]; then
                size_display=" (大小: $(numfmt --to=iec ${final_size} 2>/dev/null || echo "${final_size} bytes"))"
            fi
            
            echo -e "${GREEN}✓ 固件重命名完成: ${new_name}${size_display}${NC}"
            log "固件重命名成功: ${original_name} -> ${new_name}"
            
            # 显示最终目录内容
            echo -e "\n${CYAN}最终固件目录:${NC}"
            ls -lh "${target_dir}/"*.img.gz 2>/dev/null | grep -E "(Z-ImmWrt|efi)" || true
            
            return 0
        else
            echo -e "${RED}❌ 固件重命名失败${NC}"
            log_error "固件重命名失败: ${efi_image} -> ${new_path}"
            return 1
        fi
    else
        echo -e "${RED}❌ 未找到EFI固件文件${NC}"
        log_error "未找到EFI固件文件"
        
        # 列出目录内容，方便调试
        echo "固件目录内容:"
        ls -la "${target_dir}/" 2>/dev/null || true
        
        return 1
    fi
}

# 修改后：
rename_efi_image() {
    log "开始重命名EFI固件文件"
    local build_date=$(date +"%Y%m%d")
    local target_dir="${PROJECT_DIR}/bin/targets/x86/64"
    
    # 新的备份目录：z_mk.sh同级目录下的 old_firmwares 文件夹
    local backup_dir="${SCRIPT_DIR}/../old_firmwares"
    
    # 创建备份目录
    mkdir -p "${backup_dir}" 2>/dev/null || true
    echo -e "${CYAN}旧固件备份目录: ${backup_dir}${NC}"
    
    # 查找最新的EFI固件
    local efi_image=$(find "${target_dir}" -maxdepth 1 -type f -name "*-efi.img.gz" ! -name "Z-ImmWrt-*" | head -n 1)
    
    if [ -z "${efi_image}" ]; then
        # 如果没有找到非Z-ImmWrt的efi文件，尝试查找任何efi文件
        efi_image=$(find "${target_dir}" -maxdepth 1 -type f -name "*-efi.img.gz" | head -n 1)
    fi
    
    if [ -n "${efi_image}" ]; then
        local original_name=$(basename "${efi_image}")
        local new_name="Z-ImmWrt-${build_date}-zuoxm-x86_64-efi.img.gz"
        local new_path="${target_dir}/${new_name}"
        
        echo -e "${CYAN}▶ 处理新固件: ${original_name}${NC}"
        
        # 1. 先备份当前目录中的旧Z-ImmWrt固件
        echo -e "${CYAN}▶ 备份旧固件到备份目录...${NC}"
        
        # 查找当前目录中所有旧的Z-ImmWrt固件
        local old_z_files=($(find "${target_dir}" -maxdepth 1 -type f -name "Z-ImmWrt-*.img.gz" 2>/dev/null))
        
        if [ ${#old_z_files[@]} -gt 0 ]; then
            echo "找到 ${#old_z_files[@]} 个旧的Z-ImmWrt固件需要备份"
            
            for old_file in "${old_z_files[@]}"; do
                local old_filename=$(basename "${old_file}")
                local backup_path="${backup_dir}/${old_filename}"
                
                echo "备份: ${old_filename}"
                
                # 如果备份目录已存在同名文件，直接覆盖
                if [ -f "${backup_path}" ]; then
                    echo "  ⚠️  覆盖已存在的备份: ${old_filename}"
                fi
                
                # 移动文件到备份目录（覆盖同名文件）
                mv -f "${old_file}" "${backup_path}" 2>/dev/null || true
                
                if [ -f "${backup_path}" ]; then
                    log "备份成功: ${old_filename} -> ${backup_dir}"
                else
                    log "备份失败: ${old_filename}"
                fi
            done
        else
            echo "没有找到需要备份的旧固件"
        fi
        
        # 2. 清理备份目录，只保留最新的5个文件
        echo -e "${CYAN}▶ 清理备份目录（保留最新的5个文件）...${NC}"
        
        # 按修改时间排序，删除最旧的文件
        local backup_files_count=$(find "${backup_dir}" -maxdepth 1 -type f -name "*.img.gz" 2>/dev/null | wc -l)
        
        if [ "$backup_files_count" -gt 5 ]; then
            echo "备份目录有 ${backup_files_count} 个文件，清理多余的 $(($backup_files_count - 5)) 个"
            
            # 按修改时间排序，获取需要删除的最旧文件
            find "${backup_dir}" -maxdepth 1 -type f -name "*.img.gz" -printf "%T@ %p\n" 2>/dev/null | \
                sort -n | \
                head -n $(($backup_files_count - 5)) | \
                while read -r line; do
                    local old_backup_file=$(echo "$line" | cut -d' ' -f2-)
                    local old_backup_name=$(basename "${old_backup_file}")
                    echo "删除旧备份: ${old_backup_name}"
                    rm -f "${old_backup_file}"
                    log "删除旧备份文件: ${old_backup_name}"
                done
        else
            echo "备份目录有 ${backup_files_count} 个文件，无需清理"
        fi
        
        # 3. 重命名新固件
        echo -e "${CYAN}▶ 重命名新固件: ${original_name} -> ${new_name}${NC}"
        
        # 如果目标文件已存在（理论上不应该），先删除
        if [ -f "${new_path}" ]; then
            echo -e "${YELLOW}⚠️  删除已存在的同名文件: ${new_name}${NC}"
            rm -f "${new_path}"
        fi
        
        # 直接重命名
        if mv -f "${efi_image}" "${new_path}"; then
            local final_size=$(stat -c%s "${new_path}" 2>/dev/null || echo "unknown")
            local size_display=""
            
            if [[ "$final_size" =~ ^[0-9]+$ ]]; then
                size_display=" (大小: $(numfmt --to=iec ${final_size} 2>/dev/null || echo "${final_size} bytes"))"
            fi
            
            echo -e "${GREEN}✓ 固件重命名完成: ${new_name}${size_display}${NC}"
            log "固件重命名成功: ${original_name} -> ${new_name}"
            
            # 显示当前固件目录
            echo -e "\n${CYAN}当前固件目录内容:${NC}"
            ls -lh "${target_dir}/"*.img.gz 2>/dev/null | grep -v "No such file" || true
            
            # 显示备份目录信息
            echo -e "\n${CYAN}备份目录内容 (${backup_dir}):${NC}"
            local backup_files=($(find "${backup_dir}" -maxdepth 1 -type f -name "*.img.gz" 2>/dev/null))
            if [ ${#backup_files[@]} -gt 0 ]; then
                echo "备份了 ${#backup_files[@]} 个旧固件:"
                for backup_file in "${backup_files[@]}"; do
                    local backup_filename=$(basename "${backup_file}")
                    local backup_size=$(stat -c%s "${backup_file}" 2>/dev/null || echo "unknown")
                    local size_str=""
                    
                    if [[ "$backup_size" =~ ^[0-9]+$ ]]; then
                        size_str=" ($(numfmt --to=iec ${backup_size} 2>/dev/null))"
                    fi
                    
                    echo "  • ${backup_filename}${size_str}"
                done
            else
                echo "备份目录为空"
            fi
            
            return 0
        else
            echo -e "${RED}❌ 固件重命名失败${NC}"
            log "固件重命名失败: ${efi_image} -> ${new_path}"
            return 1
        fi
    else
        echo -e "${RED}❌ 未找到EFI固件文件${NC}"
        log "未找到EFI固件文件"
        
        # 列出目录内容，方便调试
        echo "固件目录内容:"
        ls -la "${target_dir}/" 2>/dev/null || true
        
        return 1
    fi
}

backup_config() {
    # 备份目录为主脚本同级的 config_backup 文件夹
    local backup_dir="${SCRIPT_DIR}/../config_backup"
    local timestamp=$(date +"%Y%m%d-%H%M%S")
    
    # 简化的备份文件名，只包含时间戳
    local backup_file="${backup_dir}/.config-${timestamp}"
    
    mkdir -p "$backup_dir"
    
    if [ ! -f .config ]; then
        echo -e "${YELLOW}⚠️ 未找到.config文件，跳过备份${NC}"
        log "未找到.config文件"
        return 1
    fi
    
    # 计算.config文件MD5，避免重复备份
    local config_md5=$(md5sum .config 2>/dev/null | cut -d' ' -f1)
    local last_md5=""
    
    if [ -n "$config_md5" ]; then
        # 检查最近一个备份的MD5
        local last_backup=$(find "$backup_dir" -name ".config-*" -type f | sort -r | head -1)
        if [ -f "$last_backup" ]; then
            last_md5=$(md5sum "$last_backup" 2>/dev/null | cut -d' ' -f1)
        fi
        
        # 如果配置没有变化，跳过备份
        if [ "$config_md5" = "$last_md5" ] && [ -n "$last_md5" ]; then
            echo -e "${YELLOW}⚠️ 配置未更改，跳过备份${NC}"
            log "配置未更改，跳过备份"
            return 0
        fi
    fi
    
    # 备份配置文件
    if cp .config "$backup_file"; then
        echo -e "${GREEN}✓ 配置已备份: $(basename "$backup_file")${NC}"
        echo -e "   备份位置: $backup_dir/"
        log "配置备份成功: $backup_file"
        
        # 更新最新配置软链接
        local latest_link="${backup_dir}/.config-latest"
        rm -f "$latest_link" 2>/dev/null
        ln -sf "$(basename "$backup_file")" "$latest_link"
        echo -e "${GREEN}✓ 创建最新配置软链接${NC}"
        
        # 清理旧的备份文件（保留最近10个）
        local backup_count=$(find "$backup_dir" -name ".config-*" -type f | wc -l)
        if [ "$backup_count" -gt 10 ]; then
            echo -e "${CYAN}♻️  清理旧备份文件...${NC}"
            find "$backup_dir" -name ".config-*" -type f | sort | head -n $(($backup_count - 10)) | while read old_file; do
                rm -f "$old_file"
                echo "   删除: $(basename "$old_file")"
            done
        fi
        
        # 显示备份信息
        local file_size=$(du -h "$backup_file" | cut -f1)
        local file_count=$(find "$backup_dir" -name ".config-*" -type f | wc -l)
        echo -e "${GREEN}✓ 备份大小: $file_size${NC}"
        echo -e "${GREEN}✓ 当前备份数量: $file_count/10${NC}"
        
        return 0
    else
        echo -e "${RED}❌ 配置备份失败${NC}"
        log "配置备份失败"
        return 1
    fi
}

format_duration() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(( (seconds % 3600) / 60 ))
    local secs=$((seconds % 60))
    
    if [ $hours -gt 0 ]; then
        echo "${hours}小时${minutes}分${secs}秒"
    elif [ $minutes -gt 0 ]; then
        echo "${minutes}分${secs}秒"
    else
        echo "${secs}秒"
    fi
}
