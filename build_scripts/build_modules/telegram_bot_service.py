#!/usr/bin/env python3
"""
ImmortalWrt Telegram编译机器人 - 优化版
使用统一通知服务
"""

import telebot
import subprocess
import os
import threading
import logging
import datetime
import time
import traceback
from functools import wraps
import psutil
import shutil

# ========== 配置 ==========
# 自动获取脚本所在目录
SCRIPT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG_DIR = os.path.join(SCRIPT_DIR, "log")
os.makedirs(LOG_DIR, exist_ok=True)

# 日志配置
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

file_handler = logging.FileHandler(os.path.join(LOG_DIR, "telegram_bot.log"), encoding='utf-8')
file_formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
file_handler.setFormatter(file_formatter)

console_handler = logging.StreamHandler()
console_formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
console_handler.setFormatter(console_formatter)

logger.addHandler(file_handler)
logger.addHandler(console_handler)

# 加载配置
def load_config():
    """从配置文件加载配置"""
    config_path = os.path.join(SCRIPT_DIR, "config", "build_config.sh")
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
                    
                    # 处理PROJECT_DIR相对路径
                    if key == 'PROJECT_DIR':
                        if not os.path.isabs(value):
                            value = os.path.join(os.path.dirname(SCRIPT_DIR), value)
                    
                    config[key] = value
    except Exception as e:
        logger.error(f"加载配置失败: {e}")
    
    return config

config = load_config()
TOKEN = config.get('TELEGRAM_BOT_TOKEN', '')
ALLOWED_USERS = config.get('ALLOWED_USERS', '').split(',')
PROJECT_DIR = config.get('PROJECT_DIR', '/home/zuoxm/immortalwrt')
PROJECT_DIR = PROJECT_DIR.strip('"')

# 初始化bot
bot = telebot.TeleBot(TOKEN)

# ========== 装饰器 ==========
def restricted(func):
    """限制用户访问的装饰器"""
    @wraps(func)
    def wrapper(message, *args, **kwargs):
        user_id = str(message.from_user.id)
        if user_id not in ALLOWED_USERS:
            bot.reply_to(message, "❌ 您没有权限使用此机器人")
            logger.warning(f"用户 {user_id} 尝试无权限访问")
            return
        return func(message, *args, **kwargs)
    return wrapper

def send_notification(command, *args):
    """发送通知到MessagePusher"""
    try:
        service_path = os.path.join(SCRIPT_DIR, "build_modules", "notification_service.py")
        
        if not os.path.exists(service_path):
            logger.error(f"通知服务不存在: {service_path}")
            return False
        
        cmd = ['python3', service_path, command]
        for arg in args:
            cmd.append(str(arg))
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode == 0:
            logger.info(f"通知发送成功: {command}")
            return True
        else:
            logger.error(f"通知发送失败: {result.stderr}")
            return False
            
    except Exception as e:
        logger.error(f"发送通知异常: {e}")
        return False

# ========== 编译管理 ==========
def is_compile_running():
    """检查是否有编译正在运行"""
    try:
        result = subprocess.run(
            ['pgrep', '-f', 'make.*V=s'],
            capture_output=True,
            text=True
        )
        
        if result.returncode == 0 and result.stdout.strip():
            return True
        
        # 检查编译日志
        compile_log = os.path.join(PROJECT_DIR, "build.log")
        if os.path.exists(compile_log):
            log_mtime = os.path.getmtime(compile_log)
            if time.time() - log_mtime < 120:
                return True
        
        return False
        
    except Exception as e:
        logger.error(f"检查编译状态失败: {e}")
        return False

def get_compile_progress():
    """获取编译进度"""
    try:
        build_log = os.path.join(LOG_DIR, "build.log")
        if not os.path.exists(build_log):
            return "❌ 编译日志文件不存在"
        
        # 获取日志最后20行
        result = subprocess.run(
            ['tail', '-20', build_log],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode == 0 and result.stdout:
            progress_text = f"📊 *编译进度（最后20行）*\n\n```\n{result.stdout}\n```"
        else:
            progress_text = "❌ 无法读取编译日志"
            
        return progress_text
        
    except Exception as e:
        logger.error(f"获取编译进度失败: {e}")
        return f"❌ 获取进度失败: {str(e)}"

def get_system_status():
    """获取系统状态"""
    try:
        # CPU信息
        cpu_percent = psutil.cpu_percent(interval=1)
        cpu_cores = psutil.cpu_count()
        
        # 内存信息
        mem = psutil.virtual_memory()
        mem_used = f"{mem.used / 1024 / 1024 / 1024:.1f}GB"
        mem_total = f"{mem.total / 1024 / 1024 / 1024:.1f}GB"
        mem_percent = mem.percent
        
        # 磁盘信息
        disk = shutil.disk_usage(PROJECT_DIR)
        disk_used = f"{disk.used / 1024 / 1024 / 1024:.1f}GB"
        disk_total = f"{disk.total / 1024 / 1024 / 1024:.1f}GB"
        disk_percent = (disk.used / disk.total) * 100
        
        # 编译状态
        compile_status = "✅ 运行中" if is_compile_running() else "❌ 未运行"
        
        status_text = f"""
🖥️ *系统状态信息*

📊 CPU: {cpu_percent}% (核心数: {cpu_cores})
💾 内存: {mem_used}/{mem_total} ({mem_percent}%)
💿 磁盘: {disk_used}/{disk_total} ({disk_percent:.1f}%)
🔨 编译状态: {compile_status}
⏰ 更新时间: {datetime.datetime.now().strftime('%H:%M:%S')}
"""
        return status_text
        
    except Exception as e:
        logger.error(f"获取系统状态失败: {e}")
        return f"❌ 获取系统状态失败: {str(e)}"

def get_recent_logs(log_type="compile", lines=50):
    """获取最近的日志"""
    try:
        log_files = {
            "compile": os.path.join(LOG_DIR, "build.log"),
            "bot": os.path.join(LOG_DIR, "telegram_bot.log"),
            "notification": os.path.join(LOG_DIR, "notification_service.log"),
            "daily": os.path.join(LOG_DIR, f"z-{datetime.datetime.now().strftime('%Y%m%d')}.log")
        }
        
        log_file = log_files.get(log_type, log_files["compile"])
        
        if not os.path.exists(log_file):
            return f"❌ 日志文件不存在: {os.path.basename(log_file)}"
        
        # 获取最后N行
        result = subprocess.run(
            ['tail', f'-{lines}', log_file],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode == 0 and result.stdout:
            log_text = f"📋 *{log_type.upper()}日志（最后{lines}行）*\n\n```\n{result.stdout}\n```"
        else:
            log_text = "❌ 无法读取日志文件"
            
        return log_text
        
    except Exception as e:
        logger.error(f"获取日志失败: {e}")
        return f"❌ 获取日志失败: {str(e)}"

def get_compile_history(days=7):
    """获取编译历史记录"""
    try:
        history = []
        
        # 检查每日日志文件
        for i in range(days):
            date = datetime.datetime.now() - datetime.timedelta(days=i)
            date_str = date.strftime('%Y%m%d')
            daily_log = os.path.join(LOG_DIR, f"z-{date_str}.log")
            
            if os.path.exists(daily_log):
                # 解析日志文件中的编译记录
                with open(daily_log, 'r', encoding='utf-8') as f:
                    lines = f.readlines()
                    
                # 查找编译开始和结束记录
                start_time = None
                end_time = None
                status = "未知"
                mode = "未知"
                
                for line in lines:
                    if "脚本开始执行" in line:
                        start_time = line[1:20]  # 提取时间戳
                    elif "编译成功" in line or "编译失败" in line:
                        end_time = line[1:20]
                        if "编译成功" in line:
                            status = "✅ 成功"
                        elif "编译失败" in line:
                            status = "❌ 失败"
                    elif "开始编译 (使用" in line:
                        if "完整" in line:
                            mode = "完整编译"
                        else:
                            mode = "增量编译"
                
                if start_time or end_time:
                    history.append({
                        'date': date_str,
                        'start': start_time,
                        'end': end_time,
                        'status': status,
                        'mode': mode,
                        'log_file': f"z-{date_str}.log"
                    })
        
        # 检查编译日志中的最近记录
        compile_log = os.path.join(LOG_DIR, "build.log")
        if os.path.exists(compile_log):
            log_mtime = datetime.datetime.fromtimestamp(os.path.getmtime(compile_log))
            today_str = datetime.datetime.now().strftime('%Y%m%d')
            
            # 如果今天的记录还没被包含
            if not any(h['date'] == today_str for h in history):
                # 从编译日志提取信息
                with open(compile_log, 'r', encoding='utf-8') as f:
                    lines = f.readlines()[-50:]  # 只取最后50行
                
                status = "未知"
                for line in lines:
                    if "编译成功" in line:
                        status = "✅ 成功 (进行中)"
                        break
                    elif "编译失败" in line:
                        status = "❌ 失败 (进行中)"
                        break
                
                history.append({
                    'date': today_str,
                    'start': log_mtime.strftime('%Y-%m-%d %H:%M:%S'),
                    'end': '进行中',
                    'status': status,
                    'mode': '未知',
                    'log_file': 'build.log'
                })
        
        # 按日期排序
        history.sort(key=lambda x: x['date'], reverse=True)
        
        return history
        
    except Exception as e:
        logger.error(f"获取编译历史失败: {e}")
        return []

def run_compile(mode, upload, chat_id, user_id):
    """执行编译"""
    if is_compile_running():
        bot.send_message(chat_id, "❌ 已有编译任务正在运行，请等待完成后再试！")
        return
    
    # 发送开始通知
    send_notification("start")
    
    # 显示编译详情
    mode_text = "增量" if mode == "quick" else "完整"
    upload_text = "并上传所有文件" if upload == "upload" else "不上传文件"
    expected_time = "30-60分钟" if mode == "quick" else "1-2小时"
    
    compile_info = f"""
📋 *编译任务详情*

• 编译模式: *{mode_text}编译*
• 上传设置: *{upload_text}*
• 预计时间: *{expected_time}*

🔄 正在启动编译进程...
"""
    bot.send_message(chat_id, compile_info, parse_mode='Markdown')
    
    # 启动编译线程
    thread = threading.Thread(
        target=_compile_thread,
        args=(mode, upload, chat_id, user_id)
    )
    thread.daemon = True
    thread.start()

def _compile_thread(mode, upload, chat_id, user_id):
    """编译线程"""
    start_time = time.time()
    
    try:
        # 设置环境变量
        env = os.environ.copy()
        env.update({
            'PATH': '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games',
            'HOME': '/home/zuoxm',
            'USER': 'zuoxm',
            'FORCE_UNSAFE_CONFIGURE': '1',
            'MAKE_JOBS': '2',
        })
        
        upload_firmware = '1' if upload == 'upload' else '0'
        upload_plugins = '1' if upload == 'upload' else '0'
        
        # 执行远程编译脚本
        cmd = [
            os.path.join(SCRIPT_DIR, 'build_modules/remote_compile.sh'),
            mode,
            upload_firmware,
            upload_plugins,
            str(chat_id)
        ]
        
        logger.info(f"开始编译: 用户={user_id}, 命令={' '.join(cmd)}")
        
        # 执行编译
        result = subprocess.run(
            cmd,
            cwd=PROJECT_DIR,
            env=env,
            timeout=10800,  # 3小时超时
            capture_output=True,
            text=True
        )
        
        total_duration = int(time.time() - start_time)
        
        if result.returncode == 0:
            # 编译成功
            send_notification("success", total_duration)
            bot.send_message(chat_id, f"✅ 编译成功！总耗时: {_format_duration(total_duration)}")
        else:
            # 编译失败
            error_msg = "❌ 编译失败！"
            if result.returncode == 124:
                error_msg += " (超时)"
            else:
                error_msg += f" (返回码: {result.returncode})"
            
            send_notification("error", "编译失败", error_msg)
            bot.send_message(chat_id, error_msg)
            
    except subprocess.TimeoutExpired:
        send_notification("error", "编译超时", "编译任务运行超过3小时被终止")
        bot.send_message(chat_id, "❌ 编译超时 (3小时)")
    except Exception as e:
        send_notification("error", "编译异常", str(e))
        bot.send_message(chat_id, f"❌ 编译异常: {str(e)}")
        logger.error(f"编译线程异常: {e}")
        logger.error(traceback.format_exc())

def _format_duration(seconds):
    """格式化时间"""
    hours = seconds // 3600
    minutes = (seconds % 3600) // 60
    secs = seconds % 60
    
    if hours > 0:
        return f"{hours}小时{minutes}分{secs}秒"
    elif minutes > 0:
        return f"{minutes}分{secs}秒"
    else:
        return f"{secs}秒"

# ========== 菜单命令 ==========
@bot.message_handler(commands=['start', 'menu'])
@restricted
def show_main_menu(message):
    """显示主菜单"""
    markup = telebot.types.ReplyKeyboardMarkup(
        row_width=2,
        resize_keyboard=True,
        one_time_keyboard=False
    )
    
    buttons = [
        "🚀 开始编译",
        "📊 编译进度",
        "📋 查看日志",
        "📜 编译历史",
        "⚙️ 系统状态",
        "ℹ️ 帮助"
    ]
    
    markup.add(*buttons)
    
    welcome_text = f"""
🤖 *ImmortalWrt 编译机器人*

欢迎使用！您可以通过菜单按钮或命令操作。

*用户:* {message.from_user.first_name}
*时间:* {datetime.datetime.now().strftime('%H:%M:%S')}

📝 可用命令:
/menu - 显示主菜单
/help - 显示帮助信息
/progress - 查看编译进度
/status - 查看系统状态
/logs - 查看编译日志
/history - 查看编译历史
"""
    
    bot.send_message(
        message.chat.id,
        welcome_text,
        reply_markup=markup,
        parse_mode='Markdown'
    )

# 新增命令处理器
@bot.message_handler(commands=['progress'])
@restricted
def show_compile_progress(message):
    """显示编译进度（命令版）"""
    progress_text = get_compile_progress()
    bot.send_message(message.chat.id, progress_text, parse_mode='Markdown')

@bot.message_handler(commands=['history'])
@restricted
def show_compile_history(message):
    """显示编译历史记录（命令版）"""
    history = get_compile_history(7)  # 获取最近7天记录
    
    if not history:
        bot.send_message(
            message.chat.id,
            "📋 *编译历史*\n\n❌ 未找到编译历史记录",
            parse_mode='Markdown'
        )
        return
    
    history_text = "📋 *编译历史（最近7天）*\n\n"
    
    for record in history:
        date_display = f"{record['date'][0:4]}-{record['date'][4:6]}-{record['date'][6:8]}"
        history_text += f"📅 *{date_display}*\n"
        history_text += f"⏱️ 开始: {record['start']}\n"
        
        if record['end'] != '进行中':
            history_text += f"⏱️ 结束: {record['end']}\n"
        else:
            history_text += f"⏱️ 结束: *{record['end']}*\n"
            
        history_text += f"📊 状态: {record['status']}\n"
        history_text += f"🔧 模式: {record['mode']}\n"
        history_text += f"📁 日志: {record['log_file']}\n\n"
    
    # 处理超长消息
    if len(history_text) > 4096:
        parts = [history_text[i:i+4096] for i in range(0, len(history_text), 4096)]
        for i, part in enumerate(parts, 1):
            if i == 1:
                bot.send_message(message.chat.id, part, parse_mode='Markdown')
            else:
                bot.send_message(message.chat.id, f"📋 *历史记录（续 {i}/{len(parts)}）*\n\n{part}", parse_mode='Markdown')
    else:
        bot.send_message(message.chat.id, history_text, parse_mode='Markdown')
        
@bot.message_handler(commands=['status'])
@restricted
def show_system_status(message):
    """显示系统状态（命令版）"""
    status_text = get_system_status()
    bot.send_message(message.chat.id, status_text, parse_mode='Markdown')

@bot.message_handler(commands=['logs'])
@restricted
def show_logs_menu(message):
    """显示日志菜单（命令版）"""
    markup = telebot.types.InlineKeyboardMarkup()
    markup.add(
        telebot.types.InlineKeyboardButton("编译日志", callback_data="log_compile"),
        telebot.types.InlineKeyboardButton("机器人日志", callback_data="log_bot"),
        telebot.types.InlineKeyboardButton("通知日志", callback_data="log_notification"),
        telebot.types.InlineKeyboardButton("每日日志", callback_data="log_daily")
    )
    
    bot.send_message(
        message.chat.id,
        "📋 *选择要查看的日志类型*",
        reply_markup=markup,
        parse_mode='Markdown'
    )

# 菜单按钮处理器
@bot.message_handler(func=lambda message: message.text == "🚀 开始编译")
@restricted
def show_compile_menu(message):
    """显示编译菜单"""
    if is_compile_running():
        bot.send_message(message.chat.id, "⚠️ *编译任务正在运行*\n\n请等待当前编译完成")
        return
    
    markup = telebot.types.ReplyKeyboardMarkup(
        row_width=2,
        resize_keyboard=True,
        one_time_keyboard=False
    )
    
    markup.add(
        "⚡ 增量编译",
        "🔨 完整编译",
        "🔙 返回主菜单"
    )
    
    bot.send_message(
        message.chat.id,
        "🔧 *编译选项*\n\n请选择编译模式：",
        reply_markup=markup,
        parse_mode='Markdown'
    )

@bot.message_handler(func=lambda message: message.text == "📊 编译进度")
@restricted
def show_progress_button(message):
    """显示编译进度（按钮版）"""
    show_compile_progress(message)

@bot.message_handler(func=lambda message: message.text == "⚙️ 系统状态")
@restricted
def show_status_button(message):
    """显示系统状态（按钮版）"""
    show_system_status(message)

@bot.message_handler(func=lambda message: message.text == "📜 编译历史")
@restricted
def show_history_button(message):
    """显示编译历史（按钮版）"""
    show_compile_history(message)
    
@bot.message_handler(func=lambda message: message.text == "📋 查看日志")
@restricted
def show_logs_button(message):
    """显示日志菜单（按钮版）"""
    show_logs_menu(message)

@bot.message_handler(func=lambda message: message.text == "ℹ️ 帮助")
@restricted
def show_help_menu(message):
    """显示帮助菜单"""
    show_help(message)

@bot.message_handler(func=lambda message: message.text in ["⚡ 增量编译", "🔨 完整编译"])
@restricted
def show_upload_options(message):
    """显示上传选项"""
    text = message.text
    is_quick = "增量" in text
    
    markup = telebot.types.ReplyKeyboardMarkup(
        row_width=2,
        resize_keyboard=True
    )
    
    mode_text = "增量" if is_quick else "完整"
    markup.add(
        f"✅ {mode_text}编译并上传",
        f"❌ {mode_text}编译不上传",
        "🔙 返回上一级"
    )
    
    bot.send_message(
        message.chat.id,
        f"⚙️ *{mode_text}编译设置*\n\n请选择上传选项：",
        reply_markup=markup,
        parse_mode='Markdown'
    )
    
    # 注册下一步处理器
    bot.register_next_step_handler(message, lambda msg: process_upload_selection(msg, is_quick))

def process_upload_selection(message, is_quick):
    """处理上传选项选择"""
    if not message.text:
        return
    
    text = message.text
    
    if text == "🔙 返回上一级":
        show_compile_menu(message)
        return
    
    mode = "quick" if is_quick else "full"
    
    if "不上传" in text:
        upload = "noupload"
    else:
        upload = "upload"
    
    # 显示确认对话框
    confirm_compile(message.chat.id, mode, upload)

def confirm_compile(chat_id, mode, upload):
    """显示确认对话框"""
    markup = telebot.types.InlineKeyboardMarkup()
    markup.add(
        telebot.types.InlineKeyboardButton("✅ 确认开始", callback_data=f"confirm_{mode}_{upload}"),
        telebot.types.InlineKeyboardButton("❌ 取消", callback_data="cancel_compile")
    )
    
    mode_text = "增量" if mode == "quick" else "完整"
    upload_text = "并上传所有文件" if upload == "upload" else "不上传文件"
    
    confirm_msg = f"""
📋 *编译任务确认*

• 编译模式: *{mode_text}编译*
• 上传设置: *{upload_text}*
• 预计时间: {"30-60分钟" if mode == "quick" else "1-2小时"}

确认开始编译吗？
"""
    
    bot.send_message(chat_id, confirm_msg, reply_markup=markup, parse_mode='Markdown')

@bot.callback_query_handler(func=lambda call: call.data.startswith("confirm_"))
def handle_confirm(call):
    """处理确认回调"""
    chat_id = call.message.chat.id
    user_id = str(call.from_user.id)
    
    if user_id not in ALLOWED_USERS:
        bot.answer_callback_query(call.id, "❌ 您没有权限")
        return
    
    _, mode, upload = call.data.split("_")
    
    bot.edit_message_text("✅ 任务已确认，开始编译...", chat_id, call.message.message_id)
    
    run_compile(mode, upload, chat_id, user_id)
    
    bot.answer_callback_query(call.id, "开始编译...")

@bot.callback_query_handler(func=lambda call: call.data == "cancel_compile")
def handle_cancel(call):
    """处理取消回调"""
    bot.edit_message_text("❌ 编译已取消", call.message.chat.id, call.message.message_id)
    bot.answer_callback_query(call.id, "已取消")

@bot.callback_query_handler(func=lambda call: call.data.startswith("log_"))
def handle_log_selection(call):
    """处理日志选择"""
    log_type = call.data.split("_")[1]
    log_text = get_recent_logs(log_type)
    
    # 处理超长日志（Telegram限制4096字符）
    if len(log_text) > 4096:
        # 分割日志发送
        chunks = [log_text[i:i+4096] for i in range(0, len(log_text), 4096)]
        bot.send_message(call.message.chat.id, f"📋 *{log_type.upper()}日志（第1/{len(chunks)}部分）*", parse_mode='Markdown')
        bot.send_message(call.message.chat.id, chunks[0], parse_mode='Markdown')
        
        for i, chunk in enumerate(chunks[1:], 2):
            bot.send_message(call.message.chat.id, f"📋 *第{i}/{len(chunks)}部分*", parse_mode='Markdown')
            bot.send_message(call.message.chat.id, chunk, parse_mode='Markdown')
    else:
        bot.send_message(call.message.chat.id, log_text, parse_mode='Markdown')
    
    bot.answer_callback_query(call.id, "日志已加载")

# ========== 其他命令 ==========
@bot.message_handler(commands=['help'])
@restricted
def show_help(message):
    """显示帮助信息"""
    help_text = """
🤖 *ImmortalWrt 编译机器人 - 帮助手册*

📋 *主要功能:*
1. 🚀 开始编译
   - ⚡ 增量编译 (推荐)
   - 🔨 完整编译

2. 📊 编译进度
   - 实时查看编译进度

3. 📋 查看日志
   - 编译日志和机器人日志

4. 📜 编译历史
   - 查看最近7天的编译记录

5. ⚙️ 系统状态
   - 系统资源使用情况

📝 *所有命令:*
/menu - 显示主菜单
/help - 显示此帮助信息
/progress - 查看编译进度
/status - 查看系统状态
/logs - 查看各类日志
/history - 查看编译历史

📝 *所有通知都通过MessagePusher发送到配置的渠道*
"""
    
    bot.reply_to(message, help_text, parse_mode='Markdown')

@bot.message_handler(func=lambda message: message.text == "🔙 返回主菜单")
@restricted
def return_to_main_menu(message):
    """返回主菜单"""
    show_main_menu(message)

# ========== 处理未知消息 ==========
@bot.message_handler(func=lambda message: True)
@restricted
def handle_unknown(message):
    """处理未知消息"""
    bot.reply_to(message, "❓ 未知命令\n请使用菜单按钮或 /help 查看帮助")

# ========== 主程序 ==========
def main():
    """主函数"""
    logger.info("=" * 50)
    logger.info("ImmortalWrt Telegram Bot 启动")
    logger.info(f"项目目录: {PROJECT_DIR}")
    logger.info(f"允许的用户: {ALLOWED_USERS}")
    logger.info("=" * 50)
    
    # 发送机器人启动通知
    send_notification("bot_startup")
    
    try:
        bot_info = bot.get_me()
        logger.info(f"机器人连接成功: @{bot_info.username}")
        
        bot.infinity_polling(timeout=60, long_polling_timeout=60)
        
    except Exception as e:
        logger.error(f"机器人启动失败: {e}")
        logger.error(traceback.format_exc())

if __name__ == "__main__":
    main()

