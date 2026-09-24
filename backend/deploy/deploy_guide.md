# ReadN 云服务器极简部署指南 (Screen 进程托管)

本指南针对 Linux 云服务器（Ubuntu / Debian / CentOS / Almalinux），详细说明如何使用 `screen` 在后台托管运行 Python FastAPI 后端服务，并可选配置 Nginx 代理与域名访问。

---

## 目录
1. [服务器环境准备](#1-服务器环境准备)
2. [拉取代码与安装依赖](#2-拉取代码与安装依赖)
3. [使用 Screen 托管后端进程](#3-使用-screen-托管后端进程)
4. [Screen 常用运维指令速查表](#4-screen-常用运维指令速查表)
5. [配置开机自启动与 Watchdog 守护](#5-配置开机自启动与-watchdog-守护)
6. [可选：配置 Nginx 与 SSL 证书](#6-可选配置-nginx-与-ssl-证书)

---

## 1. 服务器环境准备

登录您的云服务器（以 Ubuntu/Debian 为例）：

```bash
# 更新系统包管理器
sudo apt update && sudo apt upgrade -y

# 安装 Python 3、pip、虚拟环境以及 screen
sudo apt install -y python3 python3-pip python3-venv screen git

# 安装 OCR 引擎与数学公式识别扩展包 (双层可检索 PDF 支持)
sudo apt install -y tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-eng tesseract-ocr-equ ocrmypdf
```

如果是 CentOS / RHEL 系列：
```bash
sudo yum install -y python3 python3-pip screen git tesseract tesseract-langpack-chi_sim tesseract-langpack-equ
```

---

## 2. 拉取代码与安装依赖

将项目上传或 clone 到服务器目录（例如 `/opt/readn`）：

```bash
# 创建部署目录
sudo mkdir -p /opt/readn
sudo chown -R $USER:$USER /opt/readn
cd /opt/readn

# 上传或放置 backend 目录到 /opt/readn/backend
cd /opt/readn/backend

# 创建 Python 虚拟环境并激活
python3 -m venv venv
source venv/bin/activate

# 安装依赖
pip install --upgrade pip
pip install -r requirements.txt
```

---

## 3. 使用 Screen 托管后端进程

### 方法 A：一键脚本启动（推荐）

在 `backend/deploy/` 目录下提供了现成的启动脚本：

```bash
# 赋予执行权限
chmod +x deploy/start_screen.sh

# 启动 screen 托管进程
./deploy/start_screen.sh
```

### 方法 B：手动 Screen 交互式启动

```bash
# 1. 创建一个名为 readn_backend 的独立 screen 会话并进入
screen -S readn_backend

# 2. 在该会话窗口中激活虚拟环境并运行 Uvicorn
cd /opt/readn/backend
source venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2

# 3. 分离（挂起）会话回到主终端：
# 键盘按下：Ctrl + A，随后松开并按下 D 键
# 此时终端会显示 [detached from ...]，后端在云端后台稳定运行！
```

---

## 4. Screen 常用运维指令速查表

| 操作 | 对应命令 | 说明 |
| :--- | :--- | :--- |
| **创建并进入会话** | `screen -S readn_backend` | 创建名为 `readn_backend` 的后台窗口 |
| **挂起/离开会话** | `Ctrl + A` 然后按 `D` | 进程保持在后台继续运行 |
| **查看所有运行中的会话** | `screen -ls` | 查看当前已有的 screen 会话列表 |
| **重新连接/查看日志** | `screen -r readn_backend` | 进入会话实时查看 FastAPI/Uvicorn 日志 |
| **强制重新连接** | `screen -d -r readn_backend` | 如果提示 Attached，先分离再连接 |
| **退出并销毁会话** | 进入会话后按 `Ctrl + C` 停服，输入 `exit` | 或执行 `screen -X -S readn_backend quit` |

---

## 5. 配置开机自启动与 Watchdog 守护

为了防止服务器重启后服务中断，可将启动脚本加入 crontab 开机任务：

```bash
crontab -e
```

在末尾添加一行：
```cron
@reboot /bin/bash /opt/readn/backend/deploy/start_screen.sh >> /var/log/readn_boot.log 2>&1
```

---

## 6. 可选：配置 Nginx 与 SSL 证书

如果需要通过 80 / 443 端口与域名对外提供服务：

```bash
# 1. 安装 Nginx
sudo apt install -y nginx

# 2. 复制配置文件
sudo cp /opt/readn/backend/deploy/nginx.conf /etc/nginx/sites-available/readn.conf
sudo ln -s /etc/nginx/sites-available/readn.conf /etc/nginx/sites-enabled/

# 3. 检查并重载 Nginx
sudo nginx -t
sudo systemctl reload nginx

# 4. 配置免费 HTTPS 证书 (Certbot)
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.com
```

---

## 7. 验证部署

访问健康检查接口：
```bash
curl http://127.0.0.1:8000/api/health
# 正常返回: {"status":"healthy","service":"ReadN Backend API","version":"1.0.0"}
```
云服务器防火墙开启 8000 端口（如云厂商安全组放行入站 TCP 8000 端口）。

