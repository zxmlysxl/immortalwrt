#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Telegram 通知模块"""

import os
import requests
from datetime import datetime


def send_telegram(message: str, parse_mode: str = "Markdown") -> bool:
    """
    发送 Telegram 消息
    通过 Bot API 直接调用，不依赖 openclaw 命令
    """
    token = os.getenv("TELEGRAM_BOT_TOKEN", "")
    chat_id = os.getenv("TELEGRAM_CHAT_ID", "")
    
    if not token or not chat_id:
        print(f"[{datetime.now()}] 未配置 TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID，跳过通知")
        return False
    
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    
    # Telegram 单条消息限制 4096 字符
    chunks = []
    if len(message) <= 4000:
        chunks = [message]
    else:
        # 按段落切分
        for i in range(0, len(message), 4000):
            chunks.append(message[i:i+4000])
    
    success = True
    for chunk in chunks:
        try:
            resp = requests.post(url, data={
                "chat_id": chat_id,
                "text": chunk,
                "parse_mode": parse_mode,
                "disable_web_page_preview": "true",
            }, timeout=30)
            
            if resp.status_code == 200:
                print(f"[{datetime.now()}] Telegram 消息已发送 ({len(chunk)} 字符)")
            else:
                print(f"[{datetime.now()}] Telegram 发送失败: {resp.status_code} {resp.text[:200]}")
                success = False
        except Exception as e:
            print(f"[{datetime.now()}] Telegram 异常: {e}")
            success = False
    
    return success


def format_price_report(prices: list, changes: list = None) -> str:
    """生成价格对比报告"""
    lines = [
        "🌐 **云服务器价格对比（香港地区）**",
        f"_更新：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}_",
        ""
    ]
    
    # 按内存分组
    configs = {}
    for p in prices:
        mem = p.get("memory", "?")
        configs.setdefault(mem, []).append(p)
    
    for mem in sorted(configs.keys()):
        lines.append(f"### 💾 {mem} 内存")
        lines.append("")
        lines.append("| 厂商 | 配置 | 带宽 | 流量 | 月付 | 年付 | 来源 |")
        lines.append("|------|------|------|------|------|------|------|")
        
        # 按月付排序
        sorted_configs = sorted(configs[mem], key=lambda x: x.get("price_monthly", 999999))
        for p in sorted_configs:
            source = p.get("source", "manual")
            source_emoji = {"api": "🔌", "scraper": "🤖", "manual": "✍️", "fallback": "⚠️"}.get(source, "❓")
            lines.append(
                f"| {p.get('provider_name', '?')} "
                f"| {p.get('config', '?')} "
                f"| {p.get('bandwidth', '?')} "
                f"| {p.get('traffic', '?')} "
                f"| ¥{p.get('price_monthly', '?')} "
                f"| ¥{p.get('price_yearly', '?')} "
                f"| {source_emoji} {source} |"
            )
        lines.append("")
    
    # 价格变动
    if changes:
        lines.append("### 🚨 价格变动")
        lines.append("")
        for c in changes:
            if c["type"] == "new":
                lines.append(f"🆕 {c['provider']} {c['config']}: ¥{c['new_price']}/月 (新增)")
            elif c["type"] == "down":
                lines.append(f"📉 {c['provider']} {c['config']}: ¥{c['old_price']} → ¥{c['new_price']} (↓¥{c['diff']})")
            elif c["type"] == "up":
                lines.append(f"📈 {c['provider']} {c['config']}: ¥{c['old_price']} → ¥{c['new_price']} (↑¥{c['diff']})")
            elif c["type"] == "stale":
                lines.append(f"⚠️ {c['provider']} {c['config']}: 价格长时间未更新（{c['days']}天）")
        lines.append("")
    
    # 来源说明
    lines.append("---")
    lines.append("图例：🔌 API | 🤖 爬虫 | ✍️ 手动 | ⚠️ 兜底")
    
    return "\n".join(lines)


def format_activity_report(activities: list, new_activities: list = None) -> str:
    """生成活动监控报告"""
    lines = [
        "🎉 **云厂商最新活动**",
        f"_更新：{datetime.now().strftime('%Y-%m-%d %H:%M')}_",
        ""
    ]
    
    if not activities:
        lines.append("_当前未检测到公开活动_")
        return "\n".join(lines)
    
    # 按厂家分组
    by_provider = {}
    for a in activities:
        by_provider.setdefault(a["provider_name"], []).append(a)
    
    new_set = set()
    if new_activities:
        for a in new_activities:
            new_set.add(a.get("title", ""))
    
    for provider_name, acts in by_provider.items():
        lines.append(f"**{provider_name}**")
        for a in acts:
            emoji = "🆕 " if a.get("title") in new_set else "• "
            title = a.get("title", "")
            url = a.get("url", "")
            if url and url.startswith("http"):
                lines.append(f"  {emoji}[{title}]({url})")
            else:
                lines.append(f"  {emoji}{title}")
        lines.append("")
    
    return "\n".join(lines)