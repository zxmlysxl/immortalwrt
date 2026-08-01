#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""各云厂商价格爬虫"""

import re
import json
import time
from datetime import datetime
from typing import Optional, List, Dict
import requests
from bs4 import BeautifulSoup

# Playwright 可选（用于 JS 渲染页面）
try:
    from playwright.sync_api import sync_playwright
    HAS_PLAYWRIGHT = True
except ImportError:
    HAS_PLAYWRIGHT = False


# 美元汇率（可外部覆盖）
USD_TO_CNY = 7.2

# 浏览器请求头
DEFAULT_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept-Language": "en-US,en;q=0.9",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
}


def _http_get(url: str, headers: dict = None, timeout: int = 30) -> Optional[str]:
    """HTTP GET，返回 HTML 文本或 None"""
    try:
        h = {**DEFAULT_HEADERS, **(headers or {})}
        r = requests.get(url, headers=h, timeout=timeout, allow_redirects=True)
        r.raise_for_status()
        r.encoding = r.apparent_encoding or "utf-8"
        return r.text
    except Exception as e:
        print(f"  [HTTP] {url} 失败: {e}")
        return None


def _playwright_get(url: str, wait_selector: str = None, timeout: int = 60, wait_ms: int = 3000) -> Optional[str]:
    """用 Playwright 渲染 JS 页面，返回渲染后的 HTML"""
    if not HAS_PLAYWRIGHT:
        return None
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True, args=["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu"])
            context = browser.new_context(
                user_agent=DEFAULT_HEADERS["User-Agent"],
                locale="zh-CN",
            )
            page = context.new_page()
            page.set_default_timeout(timeout * 1000)
            page.goto(url, wait_until="domcontentloaded", timeout=timeout * 1000)
            
            if wait_selector:
                try:
                    page.wait_for_selector(wait_selector, timeout=min(timeout * 1000, 8000))
                except Exception:
                    pass
            
            # 等 JS 渲染（可缩短）
            page.wait_for_timeout(wait_ms)
            
            html = page.content()
            browser.close()
            return html
    except Exception as e:
        print(f"  [Playwright] {url} 失败: {e}")
        return None


# ============== 腾讯云轻量 ==============
def fetch_tencent() -> List[Dict]:
    """
    腾讯云轻量应用服务器价格
    URL: https://cloud.tencent.com/product/lighthouse
    优先用 Playwright，因为页面用 JS 渲染
    """
    url = "https://cloud.tencent.com/product/lighthouse"
    print(f"  → 抓取腾讯云轻量价格…")
    
    # 尝试 Playwright
    html = _playwright_get(url, wait_selector=".price-list, .lighthouse-item, table", timeout=45)
    
    prices = []
    
    if html:
        soup = BeautifulSoup(html, "html.parser")
        # 尝试从页面中匹配价格模式（人民币月付）
        text = soup.get_text(" ", strip=True)
        
        # 已知套餐作为兜底（如果抓取解析失败）
        known_plans = [
            {"config": "2 核 2G", "cpu": 2, "memory": "2G", "storage": "50GB SSD", "bandwidth": "30Mbps", "traffic": "2000GB/月", "price_monthly": 48, "price_yearly": 480},
            {"config": "2 核 4G", "cpu": 2, "memory": "4G", "storage": "80GB SSD", "bandwidth": "30Mbps", "traffic": "3000GB/月", "price_monthly": 72, "price_yearly": 720},
            {"config": "4 核 8G", "cpu": 4, "memory": "8G", "storage": "100GB SSD", "bandwidth": "30Mbps", "traffic": "4000GB/月", "price_monthly": 144, "price_yearly": 1440},
        ]
        
        # 尝试从页面解析真实价格
        found_prices = {}
        
        # 格式 1: "XX 元/月" 或 "XX元/月"（腾讯云实际是这个）
        monthly_prices = re.findall(r'(\d+)\s*元\s*/\s*月', text)
        
        # 格式 2: "¥XX" 后面跟 "月"  
        yen_prices = re.findall(r'[¥￥]\s*(\d+)[^\\d]*月', text)
        
        all_found = list(set(monthly_prices + yen_prices))
        
        # 腾讯云轻量常见的香港价格: 45/60/100/245 起等
        # 按内存从小到大映射
        target_memories = ["2G", "4G", "8G"]
        target_prices = [45, 60, 100, 120, 150, 180, 245]  # 常见阶梯
        # 简化逻辑：如果找到 XX元/月 格式，按出现顺序映射到 2G/4G/8G
        if monthly_prices:
            sorted_prices = sorted(set([int(p) for p in monthly_prices if int(p) >= 30 and int(p) <= 500]))
            if len(sorted_prices) >= 3:
                found_prices = {
                    "2G": sorted_prices[0],
                    "4G": sorted_prices[1],
                    "8G": sorted_prices[2],
                }
            elif len(sorted_prices) >= 1:
                found_prices["2G"] = sorted_prices[0]
        
        for plan in known_plans:
            actual_price = found_prices.get(plan["memory"], plan["price_monthly"])
            prices.append({
                **plan,
                "price_monthly": actual_price,
                "price_yearly": actual_price * 10,
                "currency": "CNY",
                "region": "香港",
                "source": "scraper" if plan["memory"] in found_prices else "fallback",
                "provider": "tencent",
                "provider_name": "腾讯云轻量",
                "url": url,
            })
    
    if not prices:
        # 完全失败，使用兜底数据但加警告标记
        prices = [{
            "provider": "tencent", "provider_name": "腾讯云轻量",
            "config": "2 核 4G", "cpu": 2, "memory": "4G",
            "storage": "80GB SSD", "bandwidth": "30Mbps", "traffic": "3000GB/月",
            "price_monthly": 72, "price_yearly": 720, "currency": "CNY", "region": "香港",
            "url": url, "source": "fallback", "note": "无法从官网抓取，使用兜底价",
        }]
    
    return prices


# ============== 阿里云轻量 ==============
def fetch_aliyun() -> List[Dict]:
    """
    阿里云轻量应用服务器价格
    URL: https://www.aliyun.com/product/swas
    """
    url = "https://www.aliyun.com/product/swas"
    print(f"  → 抓取阿里云轻量价格…")
    
    html = _playwright_get(url, wait_selector=".price, table, .sku-list", timeout=45)
    
    known_plans = [
        {"config": "2 核 2G", "cpu": 2, "memory": "2G", "storage": "60GB SSD", "bandwidth": "5Mbps", "traffic": "1500GB/月", "price_monthly": 59, "price_yearly": 590},
        {"config": "2 核 4G", "cpu": 2, "memory": "4G", "storage": "80GB SSD", "bandwidth": "6Mbps", "traffic": "2000GB/月", "price_monthly": 89, "price_yearly": 890},
        {"config": "4 核 8G", "cpu": 4, "memory": "8G", "storage": "120GB SSD", "bandwidth": "8Mbps", "traffic": "3000GB/月", "price_monthly": 178, "price_yearly": 1780},
    ]
    
    if html:
        text = BeautifulSoup(html, "html.parser").get_text(" ", strip=True)
        found = {}
        for plan in known_plans:
            mem = plan["memory"]
            pattern = rf"{plan['cpu']}\s*核\s*{mem}.*?[¥￥]\s*(\d+)[\./元月起]*"
            match = re.search(pattern, text)
            if match:
                found[mem] = int(match.group(1))
        
        prices = [{
            **plan,
            "price_monthly": found.get(plan["memory"], plan["price_monthly"]),
            "price_yearly": (found.get(plan["memory"], plan["price_monthly"])) * 10,
            "currency": "CNY", "region": "香港",
            "source": "scraper" if plan["memory"] in found else "fallback",
            "provider": "aliyun", "provider_name": "阿里云轻量",
            "url": url,
        } for plan in known_plans]
        return prices
    
    return [{
        "provider": "aliyun", "provider_name": "阿里云轻量",
        "config": "2 核 4G", "cpu": 2, "memory": "4G",
        "storage": "80GB SSD", "bandwidth": "6Mbps", "traffic": "2000GB/月",
        "price_monthly": 89, "price_yearly": 890, "currency": "CNY", "region": "香港",
        "url": url, "source": "fallback", "note": "无法从官网抓取",
    }]


# ============== 华为云 HECS ==============
def fetch_huawei() -> List[Dict]:
    """
    华为云 HECS 价格
    URL: https://www.huaweicloud.com/product/hecs.html
    """
    url = "https://www.huaweicloud.com/product/hecs.html"
    print(f"  → 抓取华为云 HECS 价格…")
    
    html = _playwright_get(url, wait_selector="table, .price-list", timeout=45)
    
    known_plans = [
        {"config": "2 核 2G", "cpu": 2, "memory": "2G", "storage": "40GB SSD", "bandwidth": "1Mbps", "traffic": "按量", "price_monthly": 52, "price_yearly": 520},
        {"config": "2 核 4G", "cpu": 2, "memory": "4G", "storage": "60GB SSD", "bandwidth": "2Mbps", "traffic": "按量", "price_monthly": 82, "price_yearly": 820},
        {"config": "4 核 8G", "cpu": 4, "memory": "8G", "storage": "100GB SSD", "bandwidth": "3Mbps", "traffic": "按量", "price_monthly": 165, "price_yearly": 1650},
    ]
    
    if html:
        text = BeautifulSoup(html, "html.parser").get_text(" ", strip=True)
        found = {}
        for plan in known_plans:
            mem = plan["memory"]
            pattern = rf"{plan['cpu']}\s*[vV]\s*[cC][pP][uU].*?{mem}.*?[¥￥]\s*(\d+)"
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                found[mem] = int(match.group(1))
        
        prices = [{
            **plan,
            "price_monthly": found.get(plan["memory"], plan["price_monthly"]),
            "price_yearly": (found.get(plan["memory"], plan["price_monthly"])) * 10,
            "currency": "CNY", "region": "香港",
            "source": "scraper" if plan["memory"] in found else "fallback",
            "provider": "huawei", "provider_name": "华为云 HECS",
            "url": url,
        } for plan in known_plans]
        return prices
    
    return [{
        "provider": "huawei", "provider_name": "华为云 HECS",
        "config": "2 核 4G", "cpu": 2, "memory": "4G",
        "storage": "60GB SSD", "bandwidth": "2Mbps", "traffic": "按量",
        "price_monthly": 82, "price_yearly": 820, "currency": "CNY", "region": "香港",
        "url": url, "source": "fallback", "note": "无法从官网抓取",
    }]


# ============== AWS Lightsail ==============
def fetch_aws() -> List[Dict]:
    """
    AWS Lightsail 价格（美元转人民币）
    URL: https://aws.amazon.com/lightsail/pricing/
    """
    url = "https://aws.amazon.com/lightsail/pricing/"
    print(f"  → 抓取 AWS Lightsail 价格…")
    
    # AWS 页面相对静态，优先用 requests
    html = _http_get(url, headers={"Accept-Language": "en-US,en;q=0.9"})
    
    # 已知 AWS Lightsail 香港价格（美元）
    known_plans_usd = [
        {"config": "1 核 2G", "cpu": 1, "memory": "2G", "storage": "80GB SSD", "bandwidth": "1Gbps", "traffic": "100GB/月", "price_usd": 30},
        {"config": "2 核 4G", "cpu": 2, "memory": "4G", "storage": "120GB SSD", "bandwidth": "1Gbps", "traffic": "100GB/月", "price_usd": 60},
        {"config": "2 核 8G", "cpu": 2, "memory": "8G", "storage": "240GB SSD", "bandwidth": "1Gbps", "traffic": "200GB/月", "price_usd": 115},
    ]
    
    found = {}
    if html:
        # AWS Lightsail Bundle 表格在 HTML 中位于 id="Bundles" section
        # Bundle 后面有多个 section, 需要用 Block_storage 作为 end（能拿到所有 Bundle 卡片）
        bundle_idx = html.find('id="Bundles"')
        if bundle_idx > 0:
            # 优先用 Block_storage（包含所有 Bundle 卡片）
            end_idx = html.find('id="Block_storage"', bundle_idx + 1000)
            if end_idx < 0:
                end_idx = html.find('id="CDN_distributions"', bundle_idx + 1000)
            if end_idx < 0:
                end_idx = html.find('id="Managed_databases"', bundle_idx + 1000)
            if end_idx < 0:
                end_idx = bundle_idx + 50000
            bundle_html = html[bundle_idx:end_idx]
            
            # 策略: 用 BeautifulSoup 找所有 lb-xbcol 卡片
            soup = BeautifulSoup(bundle_html, "html.parser")
            for col in soup.find_all("div", class_="lb-xbcol"):
                col_text = col.get_text(" ", strip=True)
                # 找价格（允许价格在 USD/mo 前有任意描述文字，如 "Standard plan"）
                # 格式: $X [任意描述] USD/mo
                price_match = re.search(r'\$\s*(\d+(?:\.\d+)?)\s+[^$]+?USD\s*/\s*mo', col_text)
                if not price_match:
                    continue
                price_usd = float(price_match.group(1))
                
                # 找 RAM (N GB Memory)
                mem_match = re.search(r'(\d+)\s*GB\s*Memory', col_text)
                if not mem_match:
                    continue
                mem_gb = int(mem_match.group(1))
                
                # 只关心 2/4/8 GB
                if mem_gb in [2, 4, 8]:
                    found[f"{mem_gb}G"] = int(price_usd * USD_TO_CNY)
                    print(f"    AWS {mem_gb}GB = ${price_usd}/mo = ¥{int(price_usd * USD_TO_CNY)}")
    
    prices = []
    for plan in known_plans_usd:
        mem = plan["memory"]
        cny = found.get(mem, int(plan["price_usd"] * USD_TO_CNY))
        prices.append({
            "provider": "aws", "provider_name": "AWS Lightsail",
            "config": plan["config"], "cpu": plan["cpu"], "memory": mem,
            "storage": plan["storage"], "bandwidth": plan["bandwidth"], "traffic": plan["traffic"],
            "price_monthly": cny,
            "price_yearly": cny * 12,
            "currency": "CNY", "region": "Asia Pacific (Hong Kong)",
            "url": url,
            "source": "scraper" if mem in found else "fallback",
            "note": f"按 1 USD = {USD_TO_CNY} CNY 换算" if mem in found else "使用兜底价",
        })
    return prices


# ============== Vultr (有 API!) ==============
def fetch_vultr() -> List[Dict]:
    """
    Vultr 价格 - 直接用官方 API！
    API: https://api.vultr.com/v1/plans/list?region=hkg
    """
    print(f"  → 通过 Vultr API 抓取价格…")
    
    prices = []
    api_ok = False
    
    try:
        # Vultr 公共 API，无需 key
        resp = requests.get("https://api.vultr.com/v2/plans", timeout=30,
                            headers={"Accept": "application/json"})
        if resp.status_code == 200:
            data = resp.json()
            # v2 API 返回 list of plans: [{id, vcpu_count, ram_mb, disk, bandwidth, monthly_cost, type}, ...]
            plans = data if isinstance(data, list) else data.get("plans", [])
            
            for plan_data in plans:
                # 只看 Cloud Compute 类型
                plan_type = plan_data.get("type", "")
                if "vc2" not in plan_type.lower() and "cloud compute" not in plan_type.lower():
                    continue
                
                vcpu = plan_data.get("vcpu_count", 0)
                ram_mb = plan_data.get("ram", plan_data.get("memory", 0))
                ram_gb = round(ram_mb / 1024)
                
                # 过滤我们关心的配置
                if ram_gb not in [2, 4, 8]:
                    continue
                
                # 月付美元
                usd_monthly = plan_data.get("monthly_cost", plan_data.get("price_per_month", 0))
                cny_monthly = int(usd_monthly * USD_TO_CNY)
                
                bandwidth_gb = plan_data.get("bandwidth", 0)
                
                prices.append({
                    "provider": "vultr", "provider_name": "Vultr",
                    "config": f"{vcpu} 核 {ram_gb}G",
                    "cpu": vcpu, "memory": f"{ram_gb}G",
                    "storage": f"{plan_data.get('disk', 0)}GB SSD",
                    "bandwidth": f"{bandwidth_gb / 1024:.1f}TB/月" if bandwidth_gb >= 1024 else f"{bandwidth_gb}GB/月",
                    "traffic": f"{bandwidth_gb}GB/月",
                    "price_monthly": cny_monthly,
                    "price_yearly": cny_monthly * 12,
                    "currency": "CNY", "region": "Hong Kong",
                    "url": "https://www.vultr.com/products/cloud-compute/",
                    "source": "api",
                    "note": f"Vultr API 实时: ${usd_monthly}/月 ({plan_type})",
                })
            api_ok = True
            prices.sort(key=lambda x: (x["memory"], x["price_monthly"]))
    except Exception as e:
        print(f"  [Vultr API] 失败: {e}")
    
    if not api_ok:
        # 兜底
        prices = [{
            "provider": "vultr", "provider_name": "Vultr",
            "config": "2 核 4G", "cpu": 2, "memory": "4G",
            "storage": "80GB SSD", "bandwidth": "3TB/月", "traffic": "3000GB/月",
            "price_monthly": int(24 * USD_TO_CNY), "price_yearly": int(24 * USD_TO_CNY * 12),
            "currency": "CNY", "region": "Hong Kong",
            "url": "https://www.vultr.com/products/cloud-compute/",
            "source": "fallback", "note": "API 不可用，使用兜底价",
        }]
    
    return prices


# ============== 聚合函数 ==============
def fetch_all_prices() -> List[Dict]:
    """抓取所有厂家价格"""
    all_prices = []
    
    scrapers = [
        ("腾讯云", fetch_tencent),
        ("阿里云", fetch_aliyun),
        ("华为云", fetch_huawei),
        ("AWS", fetch_aws),
        ("Vultr", fetch_vultr),
    ]
    
    for name, scraper in scrapers:
        print(f"[{datetime.now().strftime('%H:%M:%S')}] 抓取 {name}…")
        try:
            prices = scraper()
            all_prices.extend(prices)
            print(f"  ✓ {name}: 获取 {len(prices)} 条")
        except Exception as e:
            print(f"  ✗ {name}: {e}")
        time.sleep(2)  # 礼貌
    
    return all_prices


if __name__ == "__main__":
    # 测试
    prices = fetch_all_prices()
    for p in prices:
        print(f"{p['provider_name']:20} {p['config']:10} ¥{p['price_monthly']:>4}/月 [{p['source']}]")