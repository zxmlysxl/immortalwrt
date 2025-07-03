#!/bin/bash

# 生成编译信息
date_str=$(date +"%Y年%m月%d日")
time_str=$(date +"%H:%M:%S")
week_num=$(date +%u)
declare -A week_map=(
    [0]="星期天" [1]="星期一" [2]="星期二" 
    [3]="星期三" [4]="星期四" [5]="星期五" [6]="星期六"
)
echo "${date_str} ${time_str} by 上网的蜗牛 ${week_map[$week_num]}" > compile_date.txt

#开始编译
make clean
git pull
./scripts/feeds update -a && ./scripts/feeds install -a
make V=s -j$(nproc)
