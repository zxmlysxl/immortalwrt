#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
云服务器价格监控 - 香港地区
监控厂商：腾讯云、阿里云、华为云、AWS
配置：4G/8G 内存
功能：价格监控 + 活动页面监控
"""

import json
import hashlib
import subprocess
from datetime import datetime
from pathlib import Path
import re
import requests
from bs4 import BeautifulSoup

# 配置
DATA_DIR = Path("/root/.openclaw/workspace/cloud_prices")
DATA_DIR.mkdir(exist_ok=True)
PRICE_FILE = DATA_DIR / "prices.json"
HISTORY_FILE = DATA_DIR / "history.json"
ACTIVITY_FILE = DATA_DIR / "activities.json"
TELEGRAM_CHAT_ID = "1088831643"

# 云厂商配置
PROVIDERS = {
    "tencent": {
        "name": "腾讯云轻量",
        "url": "https://cloud.tencent.com/product/lighthouse",
        "activity_url": "https://cloud.tencent.com/act",
        "region": "香港",
    },
    "aliyun": {
        "name": "阿里云轻量",
        "url": "https://www.aliyun.com/product/swas",
        "activity_url": "https://www.aliyun.com/activity",
        "region": "香港",
    },
    "huawei": {
        "name": "华为云 HECS",
        "url": "https://www.huaweicloud.com/product/hecs.html",
        "activity_url": "https://activity.huaweicloud.com",
        "region": "香港",
    },
    "aws": {
        "name": "AWS Lightsail",
        "url": "https://aws.amazon.com/lightsail/pricing/",
        "activity_url": "https://aws.amazon.com/cn/free/",
        "region": "Asia Pacific (Hong Kong)",
    },
}

# 目标配置
TARGET_CONFIGS = ["4G", "8G"]


def load_prices():
    """加载当前价格数据"""
    if PRICE_FILE.exists():
        with open(PRICE_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}


def load_history():
    """加载历史记录"""
    if HISTORY_FILE.exists():
        with open(HISTORY_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    return {"records": []}


def load_activities():
    """加载活动数据"""
    if ACTIVITY_FILE.exists():
        with open(ACTIVITY_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    return {"activities": {}, "last_check": None}


def save_activities(activities):
    """保存活动数据"""
    with open(ACTIVITY_FILE, "w", encoding="utf-8") as f:
        json.dump(activities, f, ensure_ascii=False, indent=2)


def save_prices(prices):
    """保存价格数据"""
    with open(PRICE_FILE, "w", encoding="utf-8") as f:
        json.dump(prices, f, ensure_ascii=False, indent=2)


def save_history(history):
    """保存历史记录"""
    with open(HISTORY_FILE, "w", encoding="utf-8") as f:
        json.dump(history, f, ensure_ascii=False, indent=2)


def get_data_hash(data):
    """生成数据哈希用于检测变化"""
    return hashlib.md5(json.dumps(data, sort_keys=True).encode()).hexdigest()


def fetch_tencent_prices():
    """
    腾讯云轻量应用服务器价格
    由于需要登录和动态加载，使用预设价格（需定期更新）
    """
    # 这些是常见配置的价格（月付，人民币）
    # 实际价格需要从官网获取或手动更新
    return [
        {
            "provider": "tencent",
            "provider_name": "腾讯云轻量",
            "config": "2 核 2G",
            "cpu": 2,
            "memory": "2G",
            "storage": "50GB SSD",
            "bandwidth": "30Mbps",
            "traffic": "2000GB/月",
            "price_monthly": 48,
            "price_yearly": 480,
            "currency": "CNY",
            "region": "香港",
            "url": "https://cloud.tencent.com/product/lighthouse",
        },
        {
            "provider": "tencent",
            "provider_name": "腾讯云轻量",
            "config": "2 核 4G",
            "cpu": 2,
            "memory": "4G",
            "storage": "80GB SSD",
            "bandwidth": "30Mbps",
            "traffic": "3000GB/月",
            "price_monthly": 72,
            "price_yearly": 720,
            "currency": "CNY",
            "region": "香港",
            "url": "https://cloud.tencent.com/product/lighthouse",
        },
        {
            "provider": "tencent",
            "provider_name": "腾讯云轻量",
            "config": "4 核 8G",
            "cpu": 4,
            "memory": "8G",
            "storage": "100GB SSD",
            "bandwidth": "30Mbps",
            "traffic": "4000GB/月",
            "price_monthly": 144,
            "price_yearly": 1440,
            "currency": "CNY",
            "region": "香港",
            "url": "https://cloud.tencent.com/product/lighthouse",
        },
    ]


def fetch_aliyun_prices():
    """
    阿里云轻量应用服务器价格
    """
    return [
        {
            "provider": "aliyun",
            "provider_name": "阿里云轻量",
            "config": "2 核 2G",
            "cpu": 2,
            "memory": "2G",
            "storage": "60GB SSD",
            "bandwidth": "5Mbps",
            "traffic": "1500GB/月",
            "price_monthly": 59,
            "price_yearly": 590,
            "currency": "CNY",
            "region": "香港",
            "url": "https://www.aliyun.com/product/swas",
        },
        {
            "provider": "aliyun",
            "provider_name": "阿里云轻量",
            "config": "2 核 4G",
            "cpu": 2,
            "memory": "4G",
            "storage": "80GB SSD",
            "bandwidth": "6Mbps",
            "traffic": "2000GB/月",
            "price_monthly": 89,
            "price_yearly": 890,
            "currency": "CNY",
            "region": "香港",
            "url": "https://www.aliyun.com/product/swas",
        },
        {
            "provider": "aliyun",
            "provider_name": "阿里云轻量",
            "config": "4 核 8G",
            "cpu": 4,
            "memory": "8G",
            "storage": "120GB SSD",
            "bandwidth": "8Mbps",
            "traffic": "3000GB/月",
            "price_monthly": 178,
            "price_yearly": 1780,
            "currency": "CNY",
            "region": "香港",
            "url": "https://www.aliyun.com/product/swas",
        },
    ]


def fetch_huawei_prices():
    """
    华为云 HECS 价格
    """
    return [
        {
            "provider": "huawei",
            "provider_name": "华为云 HECS",
            "config": "2 核 2G",
            "cpu": 2,
            "memory": "2G",
            "storage": "40GB SSD",
            "bandwidth": "1Mbps",
            "traffic": "按量",
            "price_monthly": 52,
            "price_yearly": 520,
            "currency": "CNY",
            "region": "香港",
            "url": "https://www.huaweicloud.com/product/hecs.html",
        },
        {
            "provider": "huawei",
            "provider_name": "华为云 HECS",
            "config": "2 核 4G",
            "cpu": 2,
            "memory": "4G",
            "storage": "60GB SSD",
            "bandwidth": "2Mbps",
            "traffic": "按量",
            "price_monthly": 82,
            "price_yearly": 820,
            "currency": "CNY",
            "region": "香港",
            "url": "https://www.huaweicloud.com/product/hecs.html",
        },
        {
            "provider": "huawei",
            "provider_name": "华为云 HECS",
            "config": "4 核 8G",
            "cpu": 4,
            "memory": "8G",
            "storage": "100GB SSD",
            "bandwidth": "3Mbps",
            "traffic": "按量",
            "price_monthly": 165,
            "price_yearly": 1650,
            "currency": "CNY",
            "region": "香港",
            "url": "https://www.huaweicloud.com/product/hecs.html",
        },
    ]


def fetch_aws_prices():
    """
    AWS Lightsail 价格（美元）
    """
    # AWS 价格通常是美元，需要转换
    usd_to_cny = 7.2  # 汇率，可更新
    return [
        {
            "provider": "aws",
            "provider_name": "AWS Lightsail",
            "config": "1 核 2G",
            "cpu": 1,
            "memory": "2G",
            "storage": "60GB SSD",
            "bandwidth": "2Mbps",
            "traffic": "2000GB/月",
            "price_monthly": int(12 * usd_to_cny),
            "price_yearly": int(12 * usd_to_cny * 12),
            "currency": "CNY",
            "region": "Asia Pacific (Hong Kong)",
            "url": "https://aws.amazon.com/lightsail/pricing/",
        },
        {
            "provider": "aws",
            "provider_name": "AWS Lightsail",
            "config": "2 核 4G",
            "cpu": 2,
            "memory": "4G",
            "storage": "80GB SSD",
            "bandwidth": "3Mbps",
            "traffic": "3000GB/月",
            "price_monthly": int(24 * usd_to_cny),
            "price_yearly": int(24 * usd_to_cny * 12),
            "currency": "CNY",
            "region": "Asia Pacific (Hong Kong)",
            "url": "https://aws.amazon.com/lightsail/pricing/",
        },
        {
            "provider": "aws",
            "provider_name": "AWS Lightsail",
            "config": "4 核 8G",
            "cpu": 4,
            "memory": "8G",
            "storage": "160GB SSD",
            "bandwidth": "5Mbps",
            "traffic": "5000GB/月",
            "price_monthly": int(48 * usd_to_cny),
            "price_yearly": int(48 * usd_to_cny * 12),
            "currency": "CNY",
            "region": "Asia Pacific (Hong Kong)",
            "url": "https://aws.amazon.com/lightsail/pricing/",
        },
    ]


def fetch_all_prices():
    """获取所有厂商价格"""
    all_prices = []
    all_prices.extend(fetch_tencent_prices())
    all_prices.extend(fetch_aliyun_prices())
    all_prices.extend(fetch_huawei_prices())
    all_prices.extend(fetch_aws_prices())
    return all_prices


def compare_prices(old_prices, new_prices):
    """比较价格变化"""
    changes = []
    old_dict = {(p["provider"], p["config"]): p for p in old_prices}
    
    for new in new_prices:
        key = (new["provider"], new["config"])
        old = old_dict.get(key)
        
        if old is None:
            changes.append({
                "type": "new",
                "provider": new["provider_name"],
                "config": new["config"],
                "new_price": new["price_monthly"],
            })
        elif old["price_monthly"] != new["price_monthly"]:
            diff = new["price_monthly"] - old["price_monthly"]
            change_type = "up" if diff > 0 else "down"
            changes.append({
                "type": change_type,
                "provider": new["provider_name"],
                "config": new["config"],
                "old_price": old["price_monthly"],
                "new_price": new["price_monthly"],
                "diff": abs(diff),
            })
    
    return changes


def generate_price_table(prices):
    """生成价格对比表（Markdown 格式）"""
    # 按配置分组
    configs = {}
    for p in prices:
        mem = p["memory"]
        if mem not in configs:
            configs[mem] = []
        configs[mem].append(p)
    
    lines = []
    lines.append("## 🌐 云服务器价格对比（香港地区）")
    lines.append(f"_更新时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}_\n")
    
    for mem in sorted(configs.keys()):
        lines.append(f"### 💾 {mem} 内存配置\n")
        lines.append("| 厂商 | 配置 | CPU | 存储 | 带宽 | 流量 | 月付 | 年付 |")
        lines.append("|------|------|-----|------|------|------|------|------|")
        
        for p in sorted(configs[mem], key=lambda x: x["price_monthly"]):
            lines.append(
                f"| {p['provider_name']} | {p['config']} | {p['cpu']}核 | "
                f"{p['storage']} | {p['bandwidth']} | {p['traffic']} | "
                f"¥{p['price_monthly']} | ¥{p['price_yearly']} |"
            )
        lines.append("")
    
    # 最便宜推荐
    lines.append("### 💰 性价比推荐\n")
    for mem in sorted(configs.keys()):
        cheapest = min(configs[mem], key=lambda x: x["price_monthly"])
        lines.append(
            f"- **{mem}**: {cheapest['provider_name']} {cheapest['config']} "
            f"¥{cheapest['price_monthly']}/月"
        )
    
    return "\n".join(lines)


def generate_change_message(changes):
    """生成价格变动通知"""
    if not changes:
        return "📊 价格监控报告\n\n本次检查无价格变动。"
    
    lines = ["🚨 **价格变动提醒**\n"]
    
    for c in changes:
        if c["type"] == "new":
            lines.append(
                f"🆕 {c['provider']} {c['config']}: ¥{c['new_price']}/月 (新上架)"
            )
        elif c["type"] == "down":
            lines.append(
                f"📉 {c['provider']} {c['config']}: "
                f"¥{c['old_price']} → ¥{c['new_price']} (↓¥{c['diff']})"
            )
        else:  # up
            lines.append(
                f"📈 {c['provider']} {c['config']}: "
                f"¥{c['old_price']} → ¥{c['new_price']} (↑¥{c['diff']})"
            )
    
    return "\n".join(lines)


def fetch_activity_page(url):
    """抓取活动页面内容"""
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        }
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        return response.text
    except Exception as e:
        print(f"抓取活动页面失败 {url}: {e}")
        return None


def extract_activity_info(html, provider):
    """从 HTML 中提取活动信息"""
    if not html:
        return []
    
    activities = []
    
    try:
        soup = BeautifulSoup(html, "html.parser")
        
        # 移除脚本和样式
        for script in soup(["script", "style", "nav", "footer"]):
            script.decompose()
        
        # 查找所有包含活动关键词的文本
        keywords = ["优惠", "特惠", "促销", "活动", "HOT", "折扣", "免费", "体验", "领券", "秒杀"]
        
        # 查找链接中的活动
        links = soup.find_all("a", href=True)
        for link in links[:50]:  # 最多检查 50 个链接
            text = link.get_text(strip=True)
            if any(kw in text for kw in keywords) and len(text) < 100:
                # 去重
                if not any(a["title"] == text for a in activities):
                    activities.append({
                        "title": text,
                        "provider": provider,
                        "url": link.get("href", ""),
                    })
        
        # 如果没找到，尝试查找标题
        if not activities:
            titles = soup.find_all(["h1", "h2", "h3", "h4", "h5"])
            for title in titles[:20]:
                text = title.get_text(strip=True)
                if any(kw in text for kw in keywords) and len(text) < 100:
                    if not any(a["title"] == text for a in activities):
                        activities.append({
                            "title": text,
                            "provider": provider,
                        })
    
    except Exception as e:
        print(f"解析活动页面失败 {provider}: {e}")
    
    return activities[:10]  # 最多返回 10 个活动


def check_activity_changes():
    """检查活动页面变化"""
    old_data = load_activities()
    old_activities = old_data.get("activities", {})
    
    new_activities = {}
    changes = []
    
    for provider, config in PROVIDERS.items():
        activity_url = config.get("activity_url")
        if not activity_url:
            continue
        
        print(f"检查 {config['name']} 活动页面...")
        html = fetch_activity_page(activity_url)
        
        if html:
            # 生成页面内容哈希
            page_hash = hashlib.md5(html.encode()).hexdigest()
            old_hash = old_activities.get(provider, {}).get("hash")
            
            # 提取活动信息
            activity_list = extract_activity_info(html, provider)
            
            new_activities[provider] = {
                "hash": page_hash,
                "url": activity_url,
                "activities": activity_list,
                "last_check": datetime.now().isoformat(),
            }
            
            # 检测变化
            if old_hash != page_hash:
                changes.append({
                    "provider": config["name"],
                    "url": activity_url,
                    "type": "updated",
                    "activities": activity_list[:3],  # 只显示前 3 个
                })
                print(f"  ⚠️ {config['name']} 活动页面有更新！")
            else:
                print(f"  ✅ {config['name']} 活动页面无变化")
    
    # 保存新数据
    save_activities({
        "activities": new_activities,
        "last_check": datetime.now().isoformat(),
    })
    
    return changes


def generate_activity_message(changes):
    """生成活动变动通知"""
    if not changes:
        return ""
    
    lines = ["\n\n🎉 **活动页面更新提醒**\n"]
    
    for c in changes:
        lines.append(f"\n**{c['provider']}**: {c['url']}")
        for act in c["activities"]:
            lines.append(f"  • {act['title']}")
    
    return "\n".join(lines)


def send_telegram_message(message):
    """发送 Telegram 消息"""
    try:
        # 使用 openclaw message 工具
        subprocess.run(
            [
                "openclaw",
                "message",
                "send",
                "--target",
                TELEGRAM_CHAT_ID,
                "--message",
                message,
            ],
            capture_output=True,
            text=True,
        )
    except Exception as e:
        print(f"发送消息失败：{e}")


def main():
    """主函数"""
    print(f"[{datetime.now()}] 开始价格监控...")
    
    # === 价格监控 ===
    old_data = load_prices()
    old_prices = old_data.get("prices", [])
    old_hash = old_data.get("hash", "")
    
    new_prices = fetch_all_prices()
    new_hash = get_data_hash(new_prices)
    
    price_changes = compare_prices(old_prices, new_prices)
    
    save_prices({"prices": new_prices, "hash": new_hash, "updated": datetime.now().isoformat()})
    
    history = load_history()
    history["records"].append({
        "timestamp": datetime.now().isoformat(),
        "hash": new_hash,
        "changes_count": len(price_changes),
        "changes": price_changes,
    })
    history["records"] = history["records"][-100:]
    save_history(history)
    
    # === 活动页面监控 ===
    print(f"[{datetime.now()}] 检查活动页面...")
    activity_changes = check_activity_changes()
    
    # === 生成并发送消息 ===
    table_msg = generate_price_table(new_prices)
    
    if price_changes or activity_changes:
        # 有变化，发送详细通知
        msgs = []
        
        if price_changes:
            price_msg = generate_change_message(price_changes)
            msgs.append(price_msg)
        
        if activity_changes:
            activity_msg = generate_activity_message(activity_changes)
            msgs.append(activity_msg)
        
        full_msg = "\n\n".join(msgs) + f"\n\n{table_msg}"
        send_telegram_message(full_msg)
        print(f"发现 {len(price_changes)} 处价格变动，{len(activity_changes)} 个活动页面更新，已发送通知")
    else:
        # 无变化，发送定期检查报告
        report_msg = f"📋 **定时价格检查**\n\n{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n本次检查无价格变动。\n\n{table_msg}"
        send_telegram_message(report_msg)
        print("无价格变动，已发送定期报告")
    
    print(f"[{datetime.now()}] 价格监控完成")


if __name__ == "__main__":
    main()
