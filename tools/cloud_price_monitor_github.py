#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
云服务器价格 & 活动监控 v2.0 - 真实数据版
- 价格：每个厂家独立爬虫（API / Playwright / HTTP fallback）
- 活动：智能去重（基于内容指纹，不是页面 hash）
- 通知：Telegram 推送价格对比 + 新活动

兼容 GitHub Actions 运行
"""

import os
import sys
import json
import hashlib
from datetime import datetime
from pathlib import Path

# 加载 .env 文件
ENV_FILE = Path(__file__).parent / ".env"
if ENV_FILE.exists():
    with ENV_FILE.open("r") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, value = line.partition("=")
                os.environ.setdefault(key.strip(), value.strip())

# 加入 lib 路径
SCRIPT_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPT_DIR))

from lib.scrapers import fetch_all_prices, HAS_PLAYWRIGHT
from lib.activities import check_all_activities, _activity_signature
from lib.notify import send_telegram, format_price_report, format_activity_report

# === 配置 ===
DATA_DIR = SCRIPT_DIR.parent / "cloud_prices"
DATA_DIR.mkdir(exist_ok=True)
PRICE_FILE = DATA_DIR / "prices.json"
ACTIVITY_FILE = DATA_DIR / "activities.json"
HISTORY_FILE = DATA_DIR / "history.json"


def load_json(path: Path, default=None):
    if default is None:
        default = {}
    if path.exists():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception as e:
            print(f"[WARN] 读取 {path} 失败: {e}")
    return default


def save_json(path: Path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def compare_prices(old: list, new: list) -> list:
    """比较价格变化"""
    changes = []
    old_dict = {(p.get("provider"), p.get("config")): p for p in old}
    
    for n in new:
        key = (n.get("provider"), n.get("config"))
        o = old_dict.get(key)
        if o is None:
            changes.append({"type": "new", "provider": n.get("provider_name"),
                          "config": n.get("config"), "new_price": n.get("price_monthly")})
        elif o.get("price_monthly") != n.get("price_monthly"):
            diff = n.get("price_monthly") - o.get("price_monthly")
            changes.append({
                "type": "up" if diff > 0 else "down",
                "provider": n.get("provider_name"),
                "config": n.get("config"),
                "old_price": o.get("price_monthly"),
                "new_price": n.get("price_monthly"),
                "diff": abs(diff),
            })
    return changes


def main():
    print(f"=" * 60)
    print(f"[{datetime.now()}] 云价格 & 活动监控 v2.0 启动")
    print(f"=" * 60)
    print(f"Playwright 可用: {HAS_PLAYWRIGHT}")
    print()
    
    # ==================== 价格监控 ====================
    print(f"--- 价格监控 ---")
    old_price_data = load_json(PRICE_FILE)
    old_prices = old_price_data.get("prices", [])
    
    new_prices = fetch_all_prices()
    
    price_changes = compare_prices(old_prices, new_prices)
    
    # 计算数据指纹
    new_hash = hashlib.md5(json.dumps(new_prices, sort_keys=True).encode()).hexdigest()
    
    # 保存
    save_json(PRICE_FILE, {
        "prices": new_prices,
        "hash": new_hash,
        "updated": datetime.now().isoformat(),
        "scraper_version": "2.0",
    })
    
    print(f"\n价格变化: {len(price_changes)} 条")
    for c in price_changes:
        if c["type"] == "new":
            print(f"  🆕 {c['provider']} {c['config']}: ¥{c['new_price']}/月")
        elif c["type"] == "down":
            print(f"  📉 {c['provider']} {c['config']}: ¥{c['old_price']} → ¥{c['new_price']}")
        else:
            print(f"  📈 {c['provider']} {c['config']}: ¥{c['old_price']} → ¥{c['new_price']}")
    
    # ==================== 活动监控 ====================
    print(f"\n--- 活动监控 ---")
    old_activity_data = load_json(ACTIVITY_FILE, {"by_provider": {}})
    
    activity_result = check_all_activities(old_activity_data)
    
    # 保存
    save_json(ACTIVITY_FILE, {
        "by_provider": activity_result["by_provider"],
        "last_check": activity_result["timestamp"],
        "all_count": len(activity_result["all_activities"]),
        "new_count": len(activity_result["new_activities"]),
    })
    
    print(f"\n活动统计:")
    for prov, data in activity_result["by_provider"].items():
        flag = "🆕" if data.get("new_count", 0) > 0 else "✓"
        print(f"  {flag} {data['name']}: {data.get('count', 0)} 个活动（{data.get('new_count', 0)} 新）")
    
    # ==================== 历史记录 ====================
    history = load_json(HISTORY_FILE, {"records": []})
    history["records"].append({
        "timestamp": datetime.now().isoformat(),
        "prices_hash": new_hash,
        "price_changes_count": len(price_changes),
        "price_changes": price_changes,
        "activities_count": len(activity_result["all_activities"]),
        "new_activities_count": len(activity_result["new_activities"]),
    })
    history["records"] = history["records"][-100:]  # 保留最近100条
    save_json(HISTORY_FILE, history)
    
    # ==================== 通知 ====================
    send_telegram = bool(os.getenv("TELEGRAM_BOT_TOKEN")) and bool(os.getenv("TELEGRAM_CHAT_ID"))
    
    has_price_change = bool(price_changes)
    has_new_activity = bool(activity_result["new_activities"])
    
    if send_telegram:
        if has_price_change or has_new_activity:
            # 有变化，发详细通知
            msgs = []
            
            if has_price_change:
                msgs.append("🚨 **价格变动提醒**\n")
                for c in price_changes[:15]:
                    if c["type"] == "new":
                        msgs.append(f"🆕 {c['provider']} {c['config']}: ¥{c['new_price']}/月")
                    elif c["type"] == "down":
                        msgs.append(f"📉 {c['provider']} {c['config']}: ¥{c['old_price']} → ¥{c['new_price']} (↓¥{c['diff']})")
                    else:
                        msgs.append(f"📈 {c['provider']} {c['config']}: ¥{c['old_price']} → ¥{c['new_price']} (↑¥{c['diff']})")
            
            if has_new_activity:
                msgs.append(f"\n🆕 **发现 {len(activity_result['new_activities'])} 个新活动！**")
                for act in activity_result["new_activities"][:10]:
                    title = act.get("title", "")[:80]
                    url = act.get("url", "")
                    if url and url.startswith("http"):
                        msgs.append(f"  • [{title}]({url})")
                    else:
                        msgs.append(f"  • {title}")
            
            # 价格表（精简版，只显示关键变化）
            msgs.append("\n" + format_price_report(new_prices, price_changes))
            
            full_msg = "\n".join(msgs)
            
            # Telegram 4096 字符限制
            if len(full_msg) > 4000:
                full_msg = full_msg[:4000] + "\n...(过长已截断)"
            
            send_telegram(full_msg)
        else:
            # 无变化，发简报
            summary = f"""📊 **定时检查报告**
{datetime.now().strftime('%Y-%m-%d %H:%M')}

价格变动: 0 条
活动: {len(activity_result['all_activities'])} 条（无新增）

✅ 系统运行正常"""
            send_telegram(summary)
    
    print(f"\n{'=' * 60}")
    print(f"[{datetime.now()}] 监控完成")
    print(f"价格: {len(new_prices)} 条 | 变化: {len(price_changes)}")
    print(f"活动: {len(activity_result['all_activities'])} 条 | 新增: {len(activity_result['new_activities'])}")
    print(f"{'=' * 60}")
    
    return 0 if (has_price_change or has_new_activity or not send_telegram) else 0


if __name__ == "__main__":
    sys.exit(main() or 0)