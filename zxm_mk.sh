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

# 计算并发数
calc_jobs() {
  local mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  local mem_mb=$(( mem_kb / 1024 ))
  local jobs=$(( mem_mb / 1500 ))
  echo $(( jobs > 0 ? jobs : 1 ))  # 至少1个线程
}

#开始编译
#make clean
#make dirclean
git pull
./scripts/feeds update -a && ./scripts/feeds install -a
make download -j8
make -j$(calc_jobs) V=s 2>&1 | tee build.log  #增量编译
#make world -j$(calc_jobs) V=s 2>&1 | tee build.log  #完整编译

