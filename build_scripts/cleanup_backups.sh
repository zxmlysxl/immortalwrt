#!/bin/bash
# 配置备份清理脚本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/config_backup"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "备份目录不存在: $BACKUP_DIR"
    exit 0
fi

echo "清理配置备份目录: $BACKUP_DIR"
echo "当前备份文件:"
find "$BACKUP_DIR" -name ".config-*" -type f | sort

read -p "要保留最近几个备份文件？ (默认: 10) " keep_count
keep_count=${keep_count:-10}

total_files=$(find "$BACKUP_DIR" -name ".config-*" -type f | wc -l)

if [ "$total_files" -gt "$keep_count" ]; then
    echo "将删除 $(($total_files - $keep_count)) 个旧备份文件..."
    find "$BACKUP_DIR" -name ".config-*" -type f | sort | head -n $(($total_files - $keep_count)) | while read file; do
        echo "删除: $(basename "$file")"
        rm -f "$file"
    done
    echo "清理完成！"
else
    echo "备份文件数量 ($total_files) 未超过保留数量 ($keep_count)，无需清理。"
fi
