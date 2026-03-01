#!/bin/bash

# 加载其他模块
# 使用相对路径找到utils.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_FILE="${SCRIPT_DIR}/utils.sh"

if [ -f "$UTILS_FILE" ]; then
    source "$UTILS_FILE"
else
    echo "❌ 找不到工具模块: $UTILS_FILE"
    exit 1
fi

# 核心编译流程
common_compile() {
    local upload_firmware=$1
    local upload_plugins=$2
    
    local DL_THREADS=$(calc_dl_threads)
    local COMPILE_JOBS=$(calc_jobs)
    
    echo "使用编译线程: $COMPILE_JOBS, 下载线程: $DL_THREADS"
    
    # 更新和安装feeds
    dynamic_timer "更新 feeds" "./scripts/feeds update -a"
    dynamic_timer "安装 feeds" "./scripts/feeds install -a"
    dynamic_timer "安装 zuoxm包" "./scripts/feeds install -a -p zuoxm -f"
    
    # 交互式配置
    echo -e "\n${YELLOW}是否要调整配置? (${MENU_TIMEOUT}秒后自动跳过)${NC}"
    for (( i=MENU_TIMEOUT; i>0; i-- )); do
        printf "\r${CYAN}剩余时间: %2d秒 (按Y进入配置，其他键继续)${NC}" "$i"
        if read -t 1 -n 1 -r; then
           echo
           if [[ $REPLY =~ [Yy] ]]; then
                make menuconfig
                break
            else
                echo -e "${GREEN}跳过配置调整，继续编译...${NC}"
                break
            fi
        fi
    done
    
    # 下载源码
    dynamic_timer "下载源码" "make download -j${DL_THREADS}"
    
    # 开始编译
    log "开始编译 (使用 $COMPILE_JOBS 线程)"
    echo -e "\n${CYAN}▶ 开始编译 (使用 $COMPILE_JOBS 线程)...${NC}"
    
    local compile_start=$(date +%s)
    
    # 执行编译
    set +e
    make -j$COMPILE_JOBS V=s 2>&1 | tee -a "$BUILD_LOG"
    local make_status=${PIPESTATUS[0]}
    set -e
    
    local compile_elapsed=$(( $(date +%s) - compile_start ))
    
    if [ $make_status -ne 0 ]; then
        local elapsed=$(( $(date +%s) - compile_start ))
        log "编译失败! (总耗时: ${elapsed}秒)"
        echo -e "${RED}❌ 编译失败! (总耗时: ${elapsed}秒)${NC}"
        
        # 发送失败通知
        local last_errors=$(tail -n 5 "$BUILD_LOG" 2>/dev/null || echo "无法读取日志文件")
        send_error_notification "编译失败" "最后5行日志:\n${last_errors}" "$elapsed"
        
        return 1
    else
        local elapsed=$(( $(date +%s) - compile_start ))
        log "编译成功! (总耗时: ${elapsed}秒, 纯编译耗时: ${compile_elapsed}秒)"
        echo -e "${GREEN}✓ 编译成功! (总耗时: ${elapsed}秒, 纯编译耗时: ${compile_elapsed}秒)${NC}"
        
        # 重命名EFI固件文件
        rename_efi_image
        
        # 备份配置
	backup_config
        
        # 发送成功通知
        send_success_notification "$elapsed" "$compile_elapsed"
        
        # 调用上传函数
        if ! upload_artifacts $upload_firmware $upload_plugins; then
            echo -e "${YELLOW}⚠️ 上传过程中出现错误，但编译本身成功${NC}"
        fi
        
        return 0
    fi
}

# 完整编译
full_compile() {
    local upload_firmware=$1
    local upload_plugins=$2
    
    log "======== 开始完整编译流程 ========"
    echo -e "\n${CYAN}⚡ 执行完整编译 (含清理过程)...${NC}"
    
    check_git_updates
    
    echo -e "${YELLOW}♻️  执行深度清理...${NC}"
    set +e
    dynamic_timer "执行 make dirclean" "make dirclean"
    set -e
    
    common_compile $upload_firmware $upload_plugins
}

# 增量编译
quick_compile() {
    local upload_firmware=$1
    local upload_plugins=$2
    
    log "开始增量编译流程"
    echo -e "\n${YELLOW}⚡ 执行增量编译 (跳过清理)...${NC}"
    check_git_updates
    common_compile $upload_firmware $upload_plugins
}

# 命令行交互菜单
interactive_menu() {
    local default_compile=2
    local default_upload_firmware=1
    local default_upload_plugins=1

    echo -e "\n${BLUE}请选择编译模式 (${MENU_TIMEOUT}秒后自动选增量编译)${NC}"
    echo "1) 完整编译 (耗时较长)"
    echo "2) 增量编译 (推荐)"
    
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
    
    echo -e "\n${GREEN}✅ 编译设置完成${NC}"
    echo "编译模式: $([ $default_compile -eq 1 ] && echo "完整编译" || echo "增量编译")"
    echo "上传固件: $([ $default_upload_firmware -eq 1 ] && echo "是" || echo "否")"
    echo "上传插件: $([ $default_upload_plugins -eq 1 ] && echo "是" || echo "否")"
    echo ""
    
    case $default_compile in
        1) full_compile $default_upload_firmware $default_upload_plugins ;;
        2) quick_compile $default_upload_firmware $default_upload_plugins ;;
    esac
}
