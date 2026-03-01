#!/bin/bash

# 远程编译专用脚本
set -e

# 设置环境变量
export HOME="/home/zuoxm"
export USER="zuoxm"
export LOGNAME="zuoxm"
export SHELL="/bin/bash"
export TERM="xterm-256color"

export FORCE_UNSAFE_CONFIGURE=1
export SUBMAKE=1
export MAKE_JOBS=2
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games"

# 参数
MODE=$1
UPLOAD_FIRMWARE=$2
UPLOAD_PLUGINS=$3
CHAT_ID=$4

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 从配置文件中获取项目目录
CONFIG_FILE="${SCRIPT_DIR}/../config/build_config.sh"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# 如果PROJECT_DIR是相对路径，转换为绝对路径
if [[ ! "$PROJECT_DIR" = /* ]]; then
    PROJECT_DIR="${SCRIPT_DIR}/../${PROJECT_DIR}"
fi

# 切换到项目目录
cd "$PROJECT_DIR" || { echo "❌ 无法切换到项目目录: $PROJECT_DIR"; exit 1; }

# 清理旧的日志
if [ -f "build.log" ]; then
    rm -f "build.log"
fi

# 设置ulimit
ulimit -n 8192
ulimit -s unlimited

echo "开始远程编译..."
echo "模式: $MODE"
echo "上传固件: $UPLOAD_FIRMWARE"
echo "上传插件: $UPLOAD_PLUGINS"
echo "Chat ID: $CHAT_ID"
echo "当前目录: $(pwd)"
echo "用户: $(whoami)"
echo "环境:"
env | grep -E "PATH|HOME|USER|MAKE"

# 执行编译
ZM_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/z_mk.sh"
timeout 10800 bash "$ZM_SCRIPT" \
    --remote-build \
    "$MODE" \
    "$UPLOAD_FIRMWARE" \
    "$UPLOAD_PLUGINS" \
    "$CHAT_ID"

RETURN_CODE=$?

if [ $RETURN_CODE -eq 0 ]; then
    echo "✅ 编译成功完成"
    exit 0
elif [ $RETURN_CODE -eq 124 ]; then
    echo "❌ 编译超时（3小时）"
    exit 124
else
    echo "❌ 编译失败，返回码: $RETURN_CODE"
    exit $RETURN_CODE
fi
