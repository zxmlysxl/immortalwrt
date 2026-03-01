#!/usr/bin/env python3
"""
ImmortalWrt 统一通知服务 - 优化版
所有通知均通过MessagePusher发送
"""

import requests
import json
import os
import sys
import logging
import datetime
import socket
import glob
import re

# ========== 配置 ==========
# 自动获取脚本所在目录
SCRIPT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG_DIR = os.path.join(SCRIPT_DIR, "log")
os.makedirs(LOG_DIR, exist_ok=True)

# 日志文件路径
SERVICE_LOG_FILE = os.path.join(LOG_DIR, "notification_service.log")

# ========== 日志配置 ==========
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

file_handler = logging.FileHandler(SERVICE_LOG_FILE, encoding='utf-8')
file_formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
file_handler.setFormatter(file_formatter)

console_handler = logging.StreamHandler()
console_formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
console_handler.setFormatter(console_formatter)

logger.addHandler(file_handler)
logger.addHandler(console_handler)

class NotificationService:
    """统一通知服务类"""
    
    def __init__(self):
        self.config = self._load_config()
        self.logger = logger
    
    def _load_config(self):
        """加载配置"""
        config_path = os.path.join(SCRIPT_DIR, "config/build_config.sh")
        config = {}
        
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    
                    if '=' in line:
                        key, value = line.split('=', 1)
                        key = key.strip()
                        value = value.strip().strip('"\'')
                        
                        if '#' in value:
                            value = value.split('#')[0].strip()
                        
                        # 布尔值处理
                        bool_keys = ['ENABLE_UNIFIED_NOTIFY', 'MESSAGEPUSHER_ASYNC']
                        if key in bool_keys:
                            value = value.lower() in ['true', '1', 'yes', 'y', 'on']
                        
                        config[key] = value
                        
        except Exception as e:
            logger.error(f"加载配置失败: {e}")
        
        return config
    
    def _parse_channels(self):
        """解析消息渠道"""
        channels = {}
        enabled_channels = []
        
        try:
            # 解析渠道配置
            channels_str = self.config.get('MESSAGE_CHANNELS', '{}').strip()
            
            # 使用简单键值对格式解析（避免JSON问题）
            if channels_str:
                # 清理字符串
                channels_str = channels_str.strip('{}').strip()
                
                # 分割键值对
                pairs = [p.strip() for p in channels_str.split(',')]
                
                for pair in pairs:
                    if ':' in pair:
                        key, value = pair.split(':', 1)
                        key = key.strip().strip('"\'')
                        value = value.strip().strip('"\'')
                        if key and value:
                            channels[key] = value
            
            # 解析启用的渠道
            enabled_str = self.config.get('ENABLED_CHANNELS', '')
            enabled_channels = [c.strip() for c in enabled_str.split(',') if c.strip()]
            
            self.logger.info(f"解析的渠道: {channels}")
            self.logger.info(f"启用的渠道: {enabled_channels}")
            
        except Exception as e:
            self.logger.error(f"解析渠道配置失败: {e}")
        
        return channels, enabled_channels
    
    def _format_duration(self, seconds):
        """格式化时间"""
        if seconds is None:
            return "未知"
        
        try:
            seconds = int(seconds)
        except (ValueError, TypeError):
            return "未知"
        
        hours = seconds // 3600
        minutes = (seconds % 3600) // 60
        secs = seconds % 60
        
        if hours > 0:
            return f"{hours}小时{minutes:02d}分{secs:02d}秒"
        elif minutes > 0:
            return f"{minutes}分{secs:02d}秒"
        else:
            return f"{secs}秒"
    
    def _get_firmware_info(self):
        """获取固件信息"""
        project_dir = self.config.get('PROJECT_DIR', '')
        firmware_dir = os.path.join(project_dir, "bin/targets/x86/64")
        
        firmware_info = ""
        try:
            if os.path.exists(firmware_dir):
                firmwares = glob.glob(os.path.join(firmware_dir, "*.img.gz"))
                if firmwares:
                    firmwares.sort(key=os.path.getmtime, reverse=True)
                    latest_firmware = firmwares[0]
                    
                    firmware_name = os.path.basename(latest_firmware)
                    file_size = os.path.getsize(latest_firmware)
                    
                    # 格式化文件大小
                    if file_size >= 1024**3:
                        size_str = f"{file_size/1024**3:.2f} GB"
                    elif file_size >= 1024**2:
                        size_str = f"{file_size/1024**2:.2f} MB"
                    elif file_size >= 1024:
                        size_str = f"{file_size/1024:.2f} KB"
                    else:
                        size_str = f"{file_size} B"
                    
                    firmware_info = f"\n📦 固件: <code>{firmware_name}</code>\n💾 大小: {size_str}"
        except Exception as e:
            self.logger.error(f"获取固件信息失败: {e}")
        
        return firmware_info
    
    def send_notification(self, notification_type, title, content):
        """发送通知到所有配置的渠道"""
        if not self.config.get('ENABLE_UNIFIED_NOTIFY', False):
            self.logger.info("统一通知已禁用")
            return {'success': False, 'message': '通知已禁用'}
        
        channels, enabled_channels = self._parse_channels()
        
        if not enabled_channels:
            self.logger.warning("没有配置启用的通知渠道")
            return {'success': False, 'message': '未配置通知渠道'}
        
        results = {}
        
        for channel_name in enabled_channels:
            try:
                # 获取MessagePusher渠道名称
                mp_channel = channels.get(channel_name)
                if not mp_channel:
                    self.logger.warning(f"渠道 '{channel_name}' 未在MESSAGE_CHANNELS中定义，跳过")
                    continue
                
                # 准备请求参数
                params = {
                    'token': self.config.get('MESSAGEPUSHER_TOKEN', ''),
                    'title': title,
                    'description': content,
                    'channel': mp_channel,
                    'async': 'true' if self.config.get('MESSAGEPUSHER_ASYNC', False) else 'false'
                }
                
                # 接收用户（可选）
                to_user = self.config.get('MESSAGEPUSHER_TO', '')
                if to_user:
                    params['to'] = to_user
                
                # 发送请求
                response = requests.get(
                    self.config.get('MESSAGEPUSHER_URL', ''),
                    params=params,
                    timeout=10
                )
                
                if response.status_code == 200:
                    results[channel_name] = {'success': True, 'message': '发送成功'}
                    self.logger.info(f"渠道 '{channel_name}' 发送成功")
                else:
                    results[channel_name] = {'success': False, 'message': f'HTTP {response.status_code}'}
                    self.logger.error(f"渠道 '{channel_name}' 发送失败: {response.status_code}")
                    
            except Exception as e:
                results[channel_name] = {'success': False, 'message': str(e)}
                self.logger.error(f"渠道 '{channel_name}' 发送异常: {e}")
        
        # 汇总结果
        success_count = sum(1 for r in results.values() if r.get('success'))
        overall_success = success_count > 0
        
        return {
            'success': overall_success,
            'results': results,
            'summary': f'{success_count}/{len(results)}个渠道发送成功'
        }
    
    def send_start_notification(self):
        """发送开始编译通知"""
        start_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        hostname = socket.gethostname()
        project_name = os.path.basename(self.config.get('PROJECT_DIR', 'Unknown'))
        
        title = "🚀 编译任务开始"
        content = (
            f"📦 项目: {project_name}\n"
            f"🖥️  主机: {hostname}\n"
            f"⏰ 开始时间: {start_time}\n\n"
            f"🔧 开始编译 ImmortalWrt 固件..."
        )
        
        return self.send_notification('start', title, content)
    
    def send_success_notification(self, elapsed_time, compile_duration=None):
        """发送成功通知"""
        end_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        project_name = os.path.basename(self.config.get('PROJECT_DIR', 'Unknown'))
        build_date = datetime.datetime.now().strftime("%Y%m%d")
        
        elapsed_str = self._format_duration(elapsed_time)
        compile_str = self._format_duration(compile_duration) if compile_duration else ""
        
        # 获取固件信息
        firmware_info = self._get_firmware_info()
        
        title = "✅ 编译成功完成"
        content = (
            f"📦 项目: {project_name}\n"
            f"🎉 状态: 成功\n"
            f"⏱️  总耗时: {elapsed_str}\n"
        )
        
        if compile_str:
            content += f"🔨 纯编译耗时: {compile_str}\n"
        
        content += f"📅 日期: {build_date}\n"
        
        # 添加固件信息
        if firmware_info:
            match = re.search(r'固件:\s*<code>([^<]+)</code>', firmware_info)
            if match:
                firmware_name = match.group(1)
                content += f"📦 固件: {firmware_name}\n"
        
        content += f"\n⏰ 完成时间: {end_time}\n🎊 固件编译完成，可以开始测试了！"
        
        return self.send_notification('success', title, content)
    
    def send_error_notification(self, error_type, message, elapsed_time=None):
        """发送错误通知"""
        end_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        project_name = os.path.basename(self.config.get('PROJECT_DIR', 'Unknown'))
        
        # 限制消息长度
        if len(message) > 500:
            message = message[:500] + "..."
        
        title = f"❌ {error_type}"
        content = (
            f"📦 项目: {project_name}\n"
            f"🎯 状态: 失败\n"
            f"⏰ 失败时间: {end_time}\n\n"
            f"🔍 错误信息:\n{message}"
        )
        
        if elapsed_time:
            elapsed_str = self._format_duration(elapsed_time)
            content += f"\n⏱️  总耗时: {elapsed_str}"
        
        return self.send_notification('error', title, content)
    
    def send_upload_notification(self, upload_type, status, current_time=None):
        """发送上传通知"""
        if not current_time:
            current_time = datetime.datetime.now().strftime("%H:%M:%S")
        
        if status == "success":
            title = f"📤 {upload_type}上传成功"
            content = f"{upload_type}上传成功\n⏰ 时间: {current_time}"
        else:
            title = f"❌ {upload_type}上传失败"
            content = f"{upload_type}上传失败\n⏰ 时间: {current_time}\n💡 请检查网络连接和配置"
        
        return self.send_notification('upload', title, content)
    
    def send_bot_startup_notification(self):
        """发送机器人启动通知"""
        start_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        hostname = socket.gethostname()
        project_name = os.path.basename(self.config.get('PROJECT_DIR', 'Unknown'))
        
        title = "🤖 编译机器人已启动"
        content = (
            f"🤖 ImmortalWrt编译机器人已启动\n"
            f"🖥️  主机: {hostname}\n"
            f"⏰ 启动时间: {start_time}\n"
            f"📁 项目: {project_name}\n\n"
            "✅ 机器人已就绪，等待指令中...\n"
            "📝 使用说明:\n"
            "• 发送 /menu 查看主菜单\n"
            "• 发送 /build 开始编译\n"
            "• 发送 /help 获取帮助"
        )
        
        return self.send_notification('bot_startup', title, content)
    
    def list_channels(self):
        """列出所有渠道"""
        channels, enabled_channels = self._parse_channels()
        
        print("\n📋 可用消息渠道列表")
        print("=" * 50)
        
        if not channels:
            print("❌ 未配置任何消息渠道")
            return
        
        print("显示名称 -> MessagePusher渠道名称")
        print("-" * 50)
        
        for display_name, channel_name in channels.items():
            enabled = display_name in enabled_channels
            status = "✅ 启用" if enabled else "❌ 禁用"
            print(f"  {display_name:15} -> {channel_name:20} [{status}]")
        
        print(f"\n🎯 默认启用的渠道: {', '.join(enabled_channels)}")

def main():
    """命令行接口"""
    if len(sys.argv) < 2:
        print("\n🤖 ImmortalWrt 统一通知服务")
        print("=" * 60)
        print("用法: notification_service.py <command> [args...]\n")
        print("命令:")
        print("  list               - 列出所有可用渠道")
        print("  start              - 发送开始通知")
        print("  success <elapsed> [compile_duration] - 发送成功通知")
        print("  error <type> <message> [elapsed_time] - 发送错误通知")
        print("  upload <type> <status> [current_time] - 发送上传通知")
        print("  bot_startup        - 发送机器人启动通知\n")
        print("示例:")
        print("  notification_service.py list")
        print("  notification_service.py start")
        print("  notification_service.py success 3600 1800")
        print("  notification_service.py error \"编译失败\" \"make错误\" 3600")
        print("  notification_service.py upload 固件 success 14:30:00\n")
        sys.exit(1)
    
    service = NotificationService()
    command = sys.argv[1]
    
    if command == "list":
        service.list_channels()
        
    elif command == "start":
        result = service.send_start_notification()
        print(f"\n开始通知发送结果:")
        print(f"总体状态: {'✅ 成功' if result['success'] else '❌ 失败'}")
        print(f"发送渠道: {result.get('summary', 'N/A')}")
        
    elif command == "success":
        if len(sys.argv) < 3:
            print("错误: 需要指定elapsed时间")
            sys.exit(1)
        
        try:
            elapsed = int(sys.argv[2])
            compile_duration = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].isdigit() else None
        except ValueError:
            print("错误: 时间参数必须是整数")
            sys.exit(1)
        
        result = service.send_success_notification(elapsed, compile_duration)
        print(f"\n成功通知发送结果:")
        print(f"总体状态: {'✅ 成功' if result['success'] else '❌ 失败'}")
        print(f"发送渠道: {result.get('summary', 'N/A')}")
        
    elif command == "error":
        if len(sys.argv) < 4:
            print("错误: error命令需要参数: <error_type> <message> [elapsed_time]")
            sys.exit(1)
        
        error_type = sys.argv[2]
        message = sys.argv[3]
        elapsed_time = int(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4].isdigit() else None
        
        result = service.send_error_notification(error_type, message, elapsed_time)
        print(f"\n错误通知发送结果:")
        print(f"总体状态: {'✅ 成功' if result['success'] else '❌ 失败'}")
        print(f"发送渠道: {result.get('summary', 'N/A')}")
        
    elif command == "upload":
        if len(sys.argv) < 4:
            print("错误: upload命令需要参数: <type> <status> [current_time]")
            sys.exit(1)
        
        upload_type = sys.argv[2]
        status = sys.argv[3]
        current_time = sys.argv[4] if len(sys.argv) > 4 else None
        
        result = service.send_upload_notification(upload_type, status, current_time)
        print(f"\n上传通知发送结果:")
        print(f"总体状态: {'✅ 成功' if result['success'] else '❌ 失败'}")
        print(f"发送渠道: {result.get('summary', 'N/A')}")
        
    elif command == "bot_startup":
        result = service.send_bot_startup_notification()
        print(f"\n机器人启动通知发送结果:")
        print(f"总体状态: {'✅ 成功' if result['success'] else '❌ 失败'}")
        print(f"发送渠道: {result.get('summary', 'N/A')}")
        
    else:
        print(f"未知命令: {command}")
        sys.exit(1)

if __name__ == "__main__":
    main()
