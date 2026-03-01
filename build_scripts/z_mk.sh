#!/bin/bash

set -e

# ========== 核心配置 ==========
# 获取脚本绝对路径，确保在任何位置都能正确执行
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# 基础日志目录 - 始终在脚本目录下的log文件夹
LOG_BASE_DIR="${SCRIPT_DIR}/log"
mkdir -p "$LOG_BASE_DIR"

# ========== 提前清理旧的 build.log（核心修改：确保脚本启动即删除旧编译日志） ==========
BUILD_LOG="${LOG_BASE_DIR}/build.log"
if [ -f "$BUILD_LOG" ]; then
    echo "🔧 删除旧的编译日志 build.log..."
    rm -f "$BUILD_LOG"
fi

# ========== 加载配置 ==========
CONFIG_FILE="${SCRIPT_DIR}/config/build_config.sh"
if [ -f "${CONFIG_FILE}" ]; then
    source "${CONFIG_FILE}"
    echo "✓ 加载配置文件: ${CONFIG_FILE}"
else
    echo "❌ 找不到配置文件: ${CONFIG_FILE}"
    exit 1
fi

# ========== 处理路径配置 ==========
# 将配置中的相对路径转换为绝对路径
echo "处理路径配置..."

# 创建配置备份目录
CONFIG_BACKUP_DIR="${SCRIPT_DIR}/config_backup"
mkdir -p "$CONFIG_BACKUP_DIR"
echo "配置备份目录: $CONFIG_BACKUP_DIR"

# 项目目录
if [[ ! "$PROJECT_DIR" = /* ]]; then
    PROJECT_DIR="${SCRIPT_DIR}/${PROJECT_DIR}"
fi
echo "项目目录: $PROJECT_DIR"

# 自定义文件源目录
if [[ ! "$CUSTOM_FILES_SOURCE" = /* ]]; then
    CUSTOM_FILES_SOURCE="${SCRIPT_DIR}/${CUSTOM_FILES_SOURCE}"
fi
echo "自定义文件源: $CUSTOM_FILES_SOURCE"

# 备份源目录（兼容旧配置）
if [[ ! "$BACKUP_SOURCE" = /* ]]; then
    # 优先使用CUSTOM_FILES_SOURCE，如果不存在则尝试使用BACKUP_SOURCE的相对路径
    if [ -d "$CUSTOM_FILES_SOURCE" ]; then
        BACKUP_SOURCE="$CUSTOM_FILES_SOURCE"
    else
        BACKUP_SOURCE="${SCRIPT_DIR}/${BACKUP_SOURCE}"
    fi
fi
echo "备份源: $BACKUP_SOURCE"

# 检查备份源是否存在
if [ ! -d "$BACKUP_SOURCE" ]; then
    echo -e "${YELLOW}⚠️  警告：备份源目录不存在: $BACKUP_SOURCE${NC}"
    echo -e "${CYAN}创建自定义文件目录结构...${NC}"
    
    # 创建基本目录结构
    mkdir -p "$BACKUP_SOURCE/etc/config"
    mkdir -p "$BACKUP_SOURCE/etc/uci-defaults"
    mkdir -p "$BACKUP_SOURCE/usr/bin"
    
    # 创建说明文件
    cat > "$BACKUP_SOURCE/README.md" << EOF
# ImmortalWrt 自定义文件目录

将需要复制到固件中的自定义文件放在这里。

## 目录结构说明：
- etc/config/     - 配置文件 (如 network, firewall, etc)
- etc/uci-defaults/ - 开机初始化脚本
- usr/bin/        - 自定义脚本
- 其他目录        - 根据需要创建

## 示例：
- etc/config/network       - 网络配置
- etc/uci-defaults/99-custom - 自定义初始化脚本
- usr/bin/my_script.sh     - 自定义脚本
EOF
    
    echo -e "${GREEN}✓ 已创建自定义文件目录结构${NC}"
fi

# 模块目录
if [[ ! "$MODULES_DIR" = /* ]]; then
    MODULES_DIR="${SCRIPT_DIR}/${MODULES_DIR}"
fi
echo "模块目录: $MODULES_DIR"

# 配置目录
if [[ ! "$CONFIG_DIR" = /* ]]; then
    CONFIG_DIR="${SCRIPT_DIR}/${CONFIG_DIR}"
fi
echo "配置目录: $CONFIG_DIR"

# 上传脚本路径
if [[ ! "$UPLOAD_FIRMWARE_SCRIPT" = /* ]]; then
    UPLOAD_FIRMWARE_SCRIPT="${SCRIPT_DIR}/${UPLOAD_FIRMWARE_SCRIPT}"
fi
echo "固件上传脚本: $UPLOAD_FIRMWARE_SCRIPT"

if [[ ! "$UPLOAD_PLUGINS_SCRIPT" = /* ]]; then
    UPLOAD_PLUGINS_SCRIPT="${SCRIPT_DIR}/${UPLOAD_PLUGINS_SCRIPT}"
fi
echo "插件上传脚本: $UPLOAD_PLUGINS_SCRIPT"

# 设置日志文件路径（此处BUILD_LOG已提前定义，此处仅补全每日日志路径）
LOG_FILE="${LOG_BASE_DIR}/${DAILY_LOG_PREFIX}$(date +"%Y%m%d").log"

echo "日志文件: $LOG_FILE"
echo "编译日志: $BUILD_LOG"

# ========== 清理旧的日志文件（保留原有其他旧日志清理逻辑） ==========
echo "清理旧日志文件..."

if [ -d "$LOG_BASE_DIR" ]; then
    find "$LOG_BASE_DIR" -name "${DAILY_LOG_PREFIX}*.log" -mtime +1 -delete 2>/dev/null || true
    find "$LOG_BASE_DIR" -name "*.log" ! -name "telegram_bot.log" ! -name "notification.log" -mtime +7 -delete 2>/dev/null || true
fi

# ========== 加载模块 ==========
UTILS_MODULE="${MODULES_DIR}/utils.sh"
COMPILE_MODULE="${MODULES_DIR}/compile_functions.sh"

if [ -f "${UTILS_MODULE}" ]; then
    source "${UTILS_MODULE}"
    echo "✓ 加载工具模块: ${UTILS_MODULE}"
else
    echo "❌ 找不到工具模块: ${UTILS_MODULE}"
    exit 1
fi

if [ -f "${COMPILE_MODULE}" ]; then
    source "${COMPILE_MODULE}"
    echo "✓ 加载编译函数模块: ${COMPILE_MODULE}"
else
    echo "❌ 找不到编译函数模块: ${COMPILE_MODULE}"
    exit 1
fi

# ========== 创建/初始化当天的日志文件 ==========
touch "$LOG_FILE"
echo "========== $(date '+%Y-%m-%d %H:%M:%S') 脚本开始执行 ==========" >> "$LOG_FILE"
echo "脚本所在目录: $SCRIPT_DIR" >> "$LOG_FILE"
echo "日志文件: $LOG_FILE" >> "$LOG_FILE"
echo "编译日志: $BUILD_LOG" >> "$LOG_FILE"
echo "日志基础目录: $LOG_BASE_DIR" >> "$LOG_FILE"
echo "项目目录: $PROJECT_DIR" >> "$LOG_FILE"
echo "备份源目录: $BACKUP_SOURCE" >> "$LOG_FILE"

# ========== 切换到项目目录并验证 ==========
echo -e "\n${CYAN}切换到项目目录...${NC}"

cd "$PROJECT_DIR" || { 
    echo "❌ 无法切换到项目目录: $PROJECT_DIR" 
    exit 1 
}

if [ ! -f "Makefile" ]; then
    echo "❌ 错误：当前目录不是ImmortalWrt项目根目录！"
    exit 1
fi

echo -e "${GREEN}✓ 已切换到项目目录: $(pwd)${NC}"

# ========== 检查参数 ==========
if [ $# -gt 0 ]; then
    case "$1" in
        "--tg-bot")
            echo "启动 Telegram 机器人模式..."
            
            local python_bot="${MODULES_DIR}/telegram_bot_service.py"
            if [ -f "$python_bot" ]; then
                python3 "$python_bot"
            else
                echo "❌ 找不到Telegram机器人脚本"
                exit 1
            fi
            exit 0
            ;;
            
        "--remote-build")
            if [ $# -lt 5 ]; then
                echo "❌ 参数不足！用法: --remote-build <mode> <upload_firmware> <upload_plugins> <chat_id>"
                exit 1
            fi
            
            mode="$2"
            upload_firmware="$3"
            upload_plugins="$4"
            chat_id="$5"
            
            echo "========== 开始远程编译 =========="
            log "========== 开始远程编译 =========="
            
            compile_start_time=$(date +%s)
            send_start_notification
            
            # 恢复文件
            echo "恢复文件: $BACKUP_SOURCE -> $PROJECT_DIR/files"
            restore_files
            
            # 修改 Tailscale Makefile
            modify_tailscale_makefile

            # 写入编译信息
            mkdir -p files/etc/ && \
            echo "Z-ImmortalWrt $(date +"%Y%m%d%H%M") by zuoxm | R$(date +%y.%m.%d)" > files/etc/compile_info
            
            case $mode in
                "full") 
                    echo "执行完整编译..."
                    full_compile $upload_firmware $upload_plugins 
                    ;;
                "quick") 
                    echo "执行增量编译..."
                    quick_compile $upload_firmware $upload_plugins 
                    ;;
                *) 
                    echo "未知的编译模式: $mode"
                    exit 1 
                    ;;
            esac
            
            exit 0
            ;;
            
        "--check-progress")
            echo "检查编译进度..."
            get_compile_progress
            exit 0
            ;;
            
        "--clean")
            echo "清理编译环境..."
            make clean
            echo "✅ 清理完成"
            exit 0
            ;;
            
        "--help"|"-h")
            echo "ImmortalWrt 编译脚本 - 用法:"
            echo "  ./$SCRIPT_NAME                         : 交互式编译"
            echo "  ./$SCRIPT_NAME --tg-bot               : 启动Telegram机器人"
            echo "  ./$SCRIPT_NAME --remote-build <mode> <upload_firmware> <upload_plugins> <chat_id> : 远程编译"
            echo "  ./$SCRIPT_NAME --check-progress       : 检查编译进度"
            echo "  ./$SCRIPT_NAME --clean                : 清理编译环境"
            echo "  ./$SCRIPT_NAME --help                 : 显示此帮助"
            echo ""
            echo "编译模式:"
            echo "  full  : 完整编译（清理后重新编译）"
            echo "  quick : 增量编译（推荐）"
            echo ""
            echo "上传选项:"
            echo "  0 : 不上传"
            echo "  1 : 上传"
            exit 0
            ;;
            
        *)
            echo "未知参数: $1"
            echo "使用 ./$SCRIPT_NAME --help 查看帮助"
            exit 1
            ;;
    esac
fi

# ========== 正常的交互模式 ==========
echo "======================================="
echo "    ImmortalWrt 编译脚本 v2.0"
echo "======================================="

# 显示系统信息
echo -e "${CYAN}系统信息:${NC}"
echo "主机名: $(hostname)"
echo "用户: $(whoami)"
echo "时间: $(date)"
echo "CPU核心: $(nproc --all)"
echo "内存: $(free -h | awk '/Mem:/ {print $2}') 可用"
echo "磁盘空间: $(df -h . | awk 'NR==2 {print $4}') 可用"
echo "项目目录: $PROJECT_DIR"
echo "日志目录: $LOG_BASE_DIR"
echo "脚本目录: $SCRIPT_DIR"
echo ""

# 初始化日志
log "========== 开始本次编译 =========="
echo "========== 开始本次编译 ==========" >> "$BUILD_LOG"

# 记录编译开始时间
compile_start_time=$(date +%s)

# 发送开始通知
send_start_notification

# 恢复文件
echo -e "\n${CYAN}▶ 恢复自定义文件...${NC}"
restore_files

# 写入编译信息
mkdir -p files/etc/ && \
echo "Z-ImmortalWrt $(date +"%Y%m%d%H%M") by zuoxm | R$(date +%y.%m.%d)" > files/etc/compile_info

# 检查依赖和磁盘空间
echo -e "\n${CYAN}▶ 检查系统依赖...${NC}"
check_deps

echo -e "\n${CYAN}▶ 检查磁盘空间...${NC}"
check_disk_space

# 显示当前Git状态
echo -e "\n${CYAN}▶ 检查代码状态...${NC}"
git remote update &>/dev/null
local_commit=$(git rev-parse @)
remote_commit=$(git rev-parse @{u})
if [ "$local_commit" != "$remote_commit" ]; then
    echo -e "${YELLOW}⚠️  本地代码有更新可用${NC}"
else
    echo -e "${GREEN}✓ 代码已是最新${NC}"
fi

# 主流程
echo -e "\n${BLUE}=======================================${NC}"
echo -e "${BLUE}          开始编译流程                ${NC}"
echo -e "${BLUE}=======================================${NC}"

interactive_menu

log "======== 编译脚本执行完成 ========"

# 脚本结束时发送总耗时通知
if [ -n "$compile_start_time" ]; then
    total_elapsed=$(( $(date +%s) - compile_start_time ))
    log "总计耗时: ${total_elapsed}秒"
    
    # 只有在interactive_menu没有发送成功通知时才发送完成通知
    # (因为interactive_menu中的编译函数会自己发送通知)
fi

# 显示最终信息
echo -e "\n${GREEN}=======================================${NC}"
echo -e "${GREEN}           编译流程完成               ${NC}"
echo -e "${GREEN}=======================================${NC}"
echo -e "每日日志: ${YELLOW}$LOG_FILE${NC}"
echo -e "编译日志: ${YELLOW}$BUILD_LOG${NC}"
echo "脚本目录: ${YELLOW}$SCRIPT_DIR${NC}"
echo ""

echo -e "\n${GREEN}✅ 编译脚本执行完成！${NC}"
exit 0

