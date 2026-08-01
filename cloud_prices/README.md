# ☁️ 云服务器价格监控系统

监控主流云厂商的香港地区服务器价格和优惠活动。

## 📊 监控厂商

| 厂商 | 产品 | 地区 |
|------|------|------|
| 腾讯云 | 轻量应用服务器 (Lighthouse) | 香港 |
| 阿里云 | 轻量应用服务器 (SWAS) | 香港 |
| 华为云 | HECS 云服务器 | 香港 |
| AWS | Lightsail | Asia Pacific (Hong Kong) |

## 🎯 监控配置

- **内存配置**: 2G / 4G / 8G
- **检查频率**: 每天 2 次（8:00 和 20:00）
- **通知方式**: Telegram
- **通知规则**: 
  - 每天 2 次定时报告（无论有无变化）
  - 价格/活动变动立即通知

## 📁 文件结构

```
/root/.openclaw/workspace/
├── tools/
│   └── cloud_price_monitor.py    # 监控主脚本
├── cloud_prices/
│   ├── prices.json               # 当前价格数据
│   ├── activities.json           # 活动页面监控
│   └── history.json              # 历史记录
└── logs/
    └── cloud_price_monitor.log   # 运行日志
```

## 🔧 手动运行

```bash
cd /root/.openclaw/workspace
python3 tools/cloud_price_monitor.py
```

## 📅 Cron 任务

```cron
# 云服务器价格监控 - 每天 2 次
0 8 * * * cd /root/.openclaw/workspace && python3 tools/cloud_price_monitor.py >> /tmp/cloud_price_monitor.log 2>&1
0 20 * * * cd /root/.openclaw/workspace && python3 tools/cloud_price_monitor.py >> /tmp/cloud_price_monitor.log 2>&1
```

## 📝 更新价格

当前价格是**预设参考价**，如需更新：

1. 编辑 `tools/cloud_price_monitor.py`
2. 找到对应的 `fetch_xxx_prices()` 函数
3. 修改价格数据
4. 保存并运行一次脚本

## 🎉 活动监控

监控以下活动页面：
- 腾讯云：https://cloud.tencent.com/act
- 阿里云：https://www.aliyun.com/activity
- 华为云：https://activity.huaweicloud.com
- AWS: https://aws.amazon.com/cn/free/

检测到页面内容变化时立即通知。

## ⚠️ 注意事项

1. **价格准确性**: 当前为预设参考价，实际价格以官网为准
2. **活动监控限制**: 
   - 只能监控公开页面
   - 登录后可见的新用户专享、账户专享券无法监控
   - 页面结构变化可能导致监控失效
3. **汇率**: AWS 价格按 1 USD = 7.2 CNY 计算

## 📊 查看历史

```bash
# 查看价格历史
cat /root/.openclaw/workspace/cloud_prices/history.json | jq '.records | length'

# 查看活动监控状态
cat /root/.openclaw/workspace/cloud_prices/activities.json | jq '.last_check'
```

## 🛠️ 依赖

- Python 3.6+
- requests
- beautifulsoup4

安装依赖：
```bash
apt-get install -y python3-requests python3-bs4
```
