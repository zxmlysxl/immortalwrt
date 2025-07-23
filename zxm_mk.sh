#!/bin/bash

set -e

echo "Z-ImmortalWrt $(date +"%Y%m%d%H%M") by zuoxm | R$(date +%y.%m.%d)" > files/etc/compile_info


# 计算并发数
calc_jobs() {
  local mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  local mem_mb=$(( mem_kb / 1024 ))
  local jobs=$(( mem_mb / 1500 ))
  echo $(( jobs > 0 ? jobs : 1 ))  # 至少1个线程
}

#开始编译
#make clean
make dirclean
git pull
./scripts/feeds update -a && ./scripts/feeds install -a
make download -j8
make -j$(calc_jobs) V=s 2>&1 | tee build.log  #完整编译

