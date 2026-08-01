#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""快速生成实战教程"""
import requests, re, os
from datetime import datetime

def fetch(url):
    try:
        return requests.get(url, timeout=10, headers={'User-Agent':'Mozilla/5.0'}).text
    except:
        return None

html = fetch("https://www.dkewl.com/code/")
if not html:
    print("获取失败")
    exit(1)

# 提取文章
matches = re.findall(r'<h2[^>]*class="[^"]*layui-elip[^"]*"[^>]*><a[^>]*href="(/code/detail\d+\.html)"[^>]*>([^<]+)</a>', html)
if not matches:
    print("没找到文章")
    exit(1)

# 选一篇技术相关的
selected = None
for link, title in matches[:20]:
    if any(kw in title for kw in ["博客","商城","系统","管理","聊天","API"]):
        if not any(kw in title for kw in ["下载","破解","激活"]):
            selected = (link, title)
            break

if not selected:
    print("没找到合适的")
    exit(1)

link, title = selected
print(f"选择：{title}")

# 获取详情
detail = fetch("https://www.dkewl.com" + link)
if not detail:
    print("获取详情失败")
    exit(1)

# 提取描述
desc_match = re.search(r'<meta name="description" content="([^"]+)"', detail)
desc = desc_match.group(1) if desc_match else "开源系统"

# 生成教程
tutorial = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>实战：{title.replace("源码","")}部署教程</title>
<style>
body{{font-family:-apple-system,sans-serif;line-height:1.8;max-width:800px;margin:0 auto;padding:20px;background:#f5f5f5}}
.article{{background:#fff;padding:30px;border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,.1)}}
h1{{color:#333;border-bottom:3px solid #07c160;padding-bottom:15px}}
h2{{color:#1a1a1a;margin-top:25px}}
h3{{color:#333;margin:20px 0 10px}}
pre{{background:#f6f8fa;padding:16px;border-radius:6px;overflow-x:auto}}
code{{background:#f6f8fa;padding:2px 6px;border-radius:3px;color:#e96900}}
</style>
</head>
<body>
<div class="article">
<h1>实战：{title.replace("源码","")}部署教程</h1>
<p><strong>简介：</strong>{desc[:150]}...</p>

<h2>一、环境准备</h2>
<p>服务器要求：CentOS 7+ / Ubuntu 18.04+，2 核 4G 以上</p>
<pre><code># 安装基础软件
yum install -y nginx php php-fpm php-mysql mysql-server git unzip</code></pre>

<h2>二、下载源码</h2>
<pre><code>cd /var/www/html
# 上传源码或 git clone
unzip project.zip
mv project/* .
chown -R nginx:nginx /var/www/html
chmod -R 755 /var/www/html</code></pre>

<h2>三、配置数据库</h2>
<pre><code>mysql -u root -p
CREATE DATABASE project DEFAULT CHARACTER SET utf8mb4;
GRANT ALL ON project.* TO 'project'@'localhost' IDENTIFIED BY 'password123';
FLUSH PRIVILEGES;
EXIT;</code></pre>

<h2>四、导入数据</h2>
<pre><code>mysql -u project -p project < database.sql</code></pre>

<h2>五、修改配置</h2>
<pre><code>vi config/database.php
# 修改数据库连接信息</code></pre>

<h2>六、配置 Nginx</h2>
<pre><code>server {
    listen 80;
    server_name your-domain.com;
    root /var/www/html;
    index index.php;
    
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    
    location ~ \.php$ {
        fastcgi_pass unix:/run/php-fpm/php-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
    }
}</code></pre>

<h2>七、启动服务</h2>
<pre><code>systemctl enable nginx && systemctl start nginx
systemctl enable php-fpm && systemctl start php-fpm
systemctl enable mysqld && systemctl start mysqld</code></pre>

<h2>八、访问测试</h2>
<p>浏览器访问 <code>http://your-domain.com</code>，完成初始化配置。</p>

<h2>常见问题</h2>
<ul>
<li>502 错误：检查 PHP-FPM 是否运行</li>
<li>数据库连接失败：检查配置文件</li>
<li>权限错误：chmod -R 755 目录</li>
</ul>

<p style="color:#999;font-size:14px;margin-top:40px">来源：刀客源码 | {datetime.now().strftime('%Y-%m-%d')}</p>
</div>
</body>
</html>"""

# 保存
filepath = "/root/.openclaw/workspace/iptv-collector/articles/tutorial.html"
with open(filepath, 'w', encoding='utf-8') as f:
    f.write(tutorial)

print(f"✅ 已生成：{filepath}")
