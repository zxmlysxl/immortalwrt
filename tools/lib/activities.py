#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""智能活动监控 - 基于内容去重，不是页面 hash
完全使用 requests（无 Playwright），保证稳定快速完成
"""

import re
import json
import hashlib
import time
from datetime import datetime
from typing import Dict, List, Optional
import requests
from bs4 import BeautifulSoup


# 双语关键词库（中英文都能识别）
ACTIVITY_KEYWORDS = {
    "zh": ["优惠", "特惠", "促销", "活动", "折扣", "免费", "体验", "领券", "秒杀",
           "限时", "直降", "折", "特价", "新用户", "首购", "首单", "返",
           "补贴", "半价", "0元", "省", "立减", "赠送", "抽奖", "红包", "爆款",
           "热销", "抢购", "续费", "升级", "新人", "学生"],
    "en": ["sale", "deal", "off", "discount", "free", "trial", "limited", "hot",
           "save", "promo", "offer", "coupon", "voucher", "rebate", "special",
           "black friday", "cyber monday", "new user", "first", "launch", "flash"],
}

# 厂家活动页配置 - 选用**有公开活动列表**的页面（不是导航页）
# use_playwright=True: 需要 Playwright 渲染（JS 页面）
ACTIVITY_PAGES = {
    "tencent": {
        "name": "腾讯云",
        "url": "https://cloud.tencent.com/act",
        "use_playwright": True,
    },
    "aliyun": {
        "name": "阿里云",
        "url": "https://www.aliyun.com/activity",
        "use_playwright": False,
    },
    "huawei": {
        "name": "华为云",
        "url": "https://activity.huaweicloud.com",
        "use_playwright": False,
    },
    "aws": {
        "name": "AWS",
        "url": "https://aws.amazon.com/cn/campaigns/",
        "use_playwright": False,
    },
    "vultr": {
        "name": "Vultr",
        "url": "https://www.vultr.com/promo/",
        "use_playwright": False,
    },
}

# Playwright 可选
try:
    from playwright.sync_api import sync_playwright
    HAS_PLAYWRIGHT = True
except ImportError:
    HAS_PLAYWRIGHT = False


def _http_get(url: str, timeout: int = 15) -> Optional[str]:
    """简单 HTTP GET"""
    try:
        r = requests.get(url, timeout=timeout, headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "Accept": "text/html,application/xhtml+xml",
        }, allow_redirects=True)
        r.raise_for_status()
        r.encoding = r.apparent_encoding or "utf-8"
        return r.text
    except Exception as e:
        print(f"    [HTTP] {url}: {e}")
        return None


def _is_activity_text(text: str) -> bool:
    """判断文本是否包含活动关键词（双语）"""
    if not text or len(text) < 2 or len(text) > 200:
        return False

    text_lower = text.lower()
    for kw in ACTIVITY_KEYWORDS["zh"]:
        if kw in text:
            return True
    for kw in ACTIVITY_KEYWORDS["en"]:
        if kw in text_lower:
            return True

    # 价格模式
    if re.search(r"\d+\s*折", text):
        return True
    if re.search(r"\d+%\s*off", text_lower):
        return True
    if re.search(r"[¥$￥€£]\s*\d+", text):
        return True

    return False


def _normalize_url(url: str, base: str = "") -> str:
    """URL 规范化"""
    if not url:
        return ""
    if url.startswith("#") or url.startswith("javascript:"):
        return ""
    if url.startswith("/"):
        from urllib.parse import urlparse
        p = urlparse(base)
        return f"{p.scheme}://{p.netloc}{url}"
    if not url.startswith("http"):
        return ""
    url = re.sub(r"[?&](utm_[^&]+|from=[^&]+|spm=[^&]+|ref=[^&]+|refid=[^&]+)=([^&]*)", "", url)
    return url


def _extract_activities(html: str, provider: str, base_url: str) -> List[Dict]:
    """从 HTML 中提取活动条目"""
    if not html:
        return []

    activities = []
    seen_titles = set()

    try:
        soup = BeautifulSoup(html, "html.parser")

        for tag in soup(["script", "style", "noscript", "nav", "footer", "header"]):
            tag.decompose()

        # 提取链接（活动通常是链接）
        for link in soup.find_all("a", href=True):
            text = link.get_text(strip=True)
            if not _is_activity_text(text):
                continue

            title_key = hashlib.md5(text.encode()).hexdigest()[:12]
            if title_key in seen_titles:
                continue
            seen_titles.add(title_key)

            url = _normalize_url(link.get("href", ""), base_url)

            activities.append({
                "title": text[:120],
                "url": url or base_url,
                "provider": provider,
            })

            if len(activities) >= 20:
                break

        # 提取标题元素
        if len(activities) < 5:
            for tag in soup.find_all(["h1", "h2", "h3", "h4", "h5", "span", "div"]):
                text = tag.get_text(strip=True)
                if not _is_activity_text(text):
                    continue

                title_key = hashlib.md5(text.encode()).hexdigest()[:12]
                if title_key in seen_titles:
                    continue
                seen_titles.add(title_key)

                url = base_url
                parent_link = tag.find_parent("a", href=True)
                if parent_link:
                    url = _normalize_url(parent_link.get("href", ""), base_url) or base_url

                activities.append({
                    "title": text[:120],
                    "url": url,
                    "provider": provider,
                })

                if len(activities) >= 20:
                    break
    except Exception as e:
        print(f"    [Parse] {provider}: {e}")

    return activities


def _activity_signature(activity: Dict) -> str:
    """活动内容指纹（用于去重）"""
    title = activity.get("title", "").strip().lower()
    provider = activity.get("provider", "")
    title = re.sub(r"\d+\s*人", "", title)
    title = re.sub(r"\d+", "", title)
    return hashlib.md5(f"{provider}:{title}".encode()).hexdigest()


def check_all_activities(prev_data: Dict = None) -> Dict:
    """检查所有厂家的活动"""
    if prev_data is None:
        prev_data = {"by_provider": {}}

    prev_sigs = set()
    for prov, data in prev_data.get("by_provider", {}).items():
        for act in data.get("activities", []):
            prev_sigs.add(_activity_signature(act))

    result = {
        "by_provider": {},
        "all_activities": [],
        "new_activities": [],
        "timestamp": datetime.now().isoformat(),
    }

    # 收集需要 Playwright 的 URL
    playwright_jobs = []
    for key, config in ACTIVITY_PAGES.items():
        if config.get("use_playwright") and HAS_PLAYWRIGHT:
            playwright_jobs.append((key, config))
        elif config.get("use_playwright") and not HAS_PLAYWRIGHT:
            print(f"  [警告] {config['name']} 需要 Playwright，但未安装")

    # 用一个 Playwright 实例跑所有 JS 页面（复用 browser，避免重复启动）
    pw_results = {}  # key -> html
    if playwright_jobs and HAS_PLAYWRIGHT:
        try:
            with sync_playwright() as p:
                browser = p.chromium.launch(headless=True, args=["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu"])
                context = browser.new_context(
                    user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
                    locale="zh-CN",
                )
                page = context.new_page()
                page.set_default_timeout(25000)

                for key, config in playwright_jobs:
                    url = config["url"]
                    print(f"  [Playwright] {config['name']}: {url}")
                    try:
                        page.goto(url, wait_until="domcontentloaded", timeout=20000)
                        page.wait_for_timeout(2500)  # 等 JS 渲染
                        pw_results[key] = page.content()
                    except Exception as e:
                        print(f"    失败: {e}")

                browser.close()
        except Exception as e:
            print(f"  [Playwright 启动失败]: {e}")

    # 处理所有厂家
    for key, config in ACTIVITY_PAGES.items():
        provider_name = config["name"]
        print(f"[{datetime.now().strftime('%H:%M:%S')}] 检查 {provider_name} 活动…")

        all_acts = []
        url = config["url"]

        # 获取 HTML
        if key in pw_results:
            html = pw_results[key]
        else:
            html = _http_get(url, timeout=12)

        if html:
            acts = _extract_activities(html, key, url)
            all_acts.extend(acts)
            print(f"  提取: {len(acts)} 条")
        else:
            print(f"  未取到 HTML")

        # 去重
        seen_sigs = set()
        unique_acts = []
        for act in all_acts:
            sig = _activity_signature(act)
            if sig not in seen_sigs:
                seen_sigs.add(sig)
                unique_acts.append(act)

        # 检测新活动
        new_acts = []
        for act in unique_acts:
            sig = _activity_signature(act)
            if sig not in prev_sigs:
                new_acts.append(act)

        result["by_provider"][key] = {
            "name": provider_name,
            "activities": unique_acts[:10],
            "new_activities": new_acts,
            "count": len(unique_acts),
            "new_count": len(new_acts),
        }

        result["all_activities"].extend(unique_acts)
        result["new_activities"].extend(new_acts)

        if new_acts:
            print(f"  🆕 {provider_name}: {len(new_acts)} 个新活动")
        else:
            print(f"  ✓ {provider_name}: 无新活动")

        time.sleep(0.5)

    return result


if __name__ == "__main__":
    import time
    t0 = time.time()
    result = check_all_activities()
    elapsed = time.time() - t0
    print(f"\n⏱️  耗时 {elapsed:.1f}s")
    print(f"总活动: {len(result['all_activities'])} 条")
    print(f"新活动: {len(result['new_activities'])} 条")
    for prov, data in result["by_provider"].items():
        print(f"  {data['name']}: {data['count']} 条 ({data['new_count']} 新)")