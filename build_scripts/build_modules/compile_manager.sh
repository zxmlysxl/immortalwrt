#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载配置 - 使用相对路径
CONFIG_FILE="${SCRIPT_DIR}/config/build_config.sh"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "❌ 找不到配置文件: $CONFIG_FILE"
    exit 1
fi

# 使用配置文件中的路径
LOCK_FILE="/tmp/immortalwrt_compile.lock"

# 日志目录使用主脚本目录下的log
LOG_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}/..")" && pwd)/log"
mkdir -p "$LOG_BASE_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "${LOG_BASE_DIR}/compile_manager.log"
}

check_compile_running() {
    # 检查是否有编译进程在运行
    if ps aux | grep -E "make.*V=s" | grep -v grep | grep -v "compile_manager" > /dev/null; then
        return 0
    fi
    
    # 检查编译日志是否在更新
    if [ -f "$BUILD_LOG" ]; then
        local log_mtime=$(stat -c %Y "$BUILD_LOG" 2>/dev/null || echo 0)
        local current_time=$(date +%s)
        if [ $((current_time - log_mtime)) -lt 300 ]; then
            return 0
        fi
    fi
    
    return 1
}

acquire_lock() {
    # 尝试获取锁
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [ -n "$lock_pid" ] && ps -p "$lock_pid" > /dev/null 2>&1; then
            echo -e "${YELLOW}编译锁已被进程 $lock_pid 持有${NC}"
            return 1
        fi
        rm -f "$LOCK_FILE"
    fi
    
    echo $$ > "$LOCK_FILE"
    echo -e "${GREEN}获取编译锁成功${NC}"
    log "获取编译锁成功，进程ID: $$"
    return 0
}

release_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        
        if [ "$lock_pid" = "$$" ] || [ -z "$lock_pid" ] || ! ps -p "$lock_pid" > /dev/null 2>&1; then
            rm -f "$LOCK_FILE"
            echo -e "${GREEN}释放编译锁${NC}"
            log "释放编译锁"
        fi
    fi
}

stop_compile() {
    echo -e "${YELLOW}停止所有编译进程...${NC}"
    log "停止编译进程"
    
    # 终止编译进程
    pkill -9 -f "z_mk.sh" 2>/dev/null || true
    pkill -9 -f "make.*V=s" 2>/dev/null || true
    pkill -9 -f "remote_compile.sh" 2>/dev/null || true
    
    # 清理锁文件
    rm -f "$LOCK_FILE"
    
    sleep 2
    
    if check_compile_running; then
        echo -e "${RED}❌ 仍有编译进程在运行${NC}"
        log "停止编译失败"
        return 1
    else
        echo -e "${GREEN}✅ 所有编译进程已停止${NC}"
        log "停止编译成功"
        return 0
    fi
}

show_status() {
    echo -e "${YELLOW}=== 编译状态检查 ===${NC}"
    
    # 检查编译进程
    if check_compile_running; then
        echo -e "${RED}⚠️  有编译正在运行${NC}"
        echo -e "相关进程:"
        ps aux | grep -E "make.*V=s|z_mk.sh" | grep -v grep | head -5
    else
        echo -e "${GREEN}✅ 没有编译进程在运行${NC}"
    fi
}

case "$1" in
    "start")
        if check_compile_running; then
            echo -e "${RED}❌ 已有编译在运行${NC}"
            log "启动编译失败：已有编译在运行"
            exit 1
        fi
        
        if ! acquire_lock; then
            echo -e "${RED}❌ 无法获取编译锁${NC}"
            log "启动编译失败：无法获取编译锁"
            exit 1
        fi
        
        trap release_lock EXIT
        
        log "编译启动成功，进程ID: $$"
        echo -e "${GREEN}✅ 编译锁获取成功，可以开始编译...${NC}"
        ;;
        
    "stop")
        stop_compile
        ;;
        
    "status")
        show_status
        ;;
        
    "clean")
        echo -e "${YELLOW}清理编译环境...${NC}"
        log "开始清理编译环境"
        
        stop_compile
        
        if [ -f "$BUILD_LOG" ]; then
            rm -f "$BUILD_LOG"
            echo -e "${GREEN}清理编译日志${NC}"
        fi
        
        if [ -d "$LOG_DIR" ]; then
            find "$LOG_DIR" -name "z-*.log" -mtime +3 -delete 2>/dev/null || true
            echo -e "${GREEN}清理3天前的每日日志${NC}"
        fi
        
        echo -e "${GREEN}✅ 清理完成${NC}"
        log "清理编译环境完成"
        ;;
        
    *)
        echo "用法: $0 {start|stop|status|clean}"
        echo "  start       - 检查并获取编译锁"
        echo "  stop        - 停止所有编译进程"
        echo "  status      - 显示编译状态"
        echo "  clean       - 停止编译并清理"
        echo ""
        echo "配置文件: ${SCRIPT_DIR}/config/build_config.sh"
        exit 1
        ;;
esac
