# ReadN Linux 云服务器部署指南 (Screen 进程托管)

本指南针对主流 Linux 云服务器（Ubuntu 20.04/22.04/24.04、Debian 11/12、CentOS 7/8/9、AlmaLinux、Rocky Linux 等），详细介绍如何通过 `screen` 在后台托管运行 Python FastAPI 后端服务，并提供 Nginx 反向代理配置与自启动设置。

---

## 一、服务器环境快速准备

登录您的 Linux 云服务器终端（推荐 Ubuntu/Debian 系统）：

### 1. 更新系统并安装 Python3 与 screen
```bash
# Ubuntu / Debian:
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3 python3-pip python3-venv screen curl unzip

# CentOS / RHEL / AlmaLinux / RockyLinux:
sudo yum install -y python3 python3-pip screen curl unzip
```

> **说明**：ReadN 现已全面接入百度云端多模态 PaddleOCR-VL API，**服务器端无需安装任何庞大的本地 OCR 或 C++ 图像识别引擎**，环境极其轻量纯粹，1核1G/1核2G 的轻量云服务器即可流畅运行！

---

## 二、上传并部署后端程序

### 1. 创建服务工作目录
```bash
sudo mkdir -p /opt/readn
sudo chown -R $USER:$USER /opt/readn
cd /opt/readn
```

### 2. 上传并解压后端压缩包
将打包好的 `readn_backend.zip` 上传到 `/opt/readn/` 目录下（可以通过 `scp`、Xftp 或终端拖拽）：
```bash
# 解压到当前目录
unzip -o readn_backend.zip -d /opt/readn/backend

# 进入后端目录
cd /opt/readn/backend
```

---

## 三、使用 Screen 托管运行后端服务

### 方式 A：一键脚本管理（强烈推荐）

我们在 `deploy/start_screen.sh` 中集成了完整的生命周期管理（支持自动创建虚拟环境、安装依赖、启动、停止、重启、查看状态及实时日志）：

```bash
# 赋予执行权限
chmod +x deploy/start_screen.sh

# 1. 启动服务（会自动创建虚拟环境并安装依赖）
./deploy/start_screen.sh start

# 2. 查看服务状态
./deploy/start_screen.sh status

# 3. 实时查看后端运行日志（进入 screen 会话）
./deploy/start_screen.sh logs
# 退出日志查看界面：按下键盘 Ctrl + A，然后按下 D 键（挂起会话，服务在后台继续运行）

# 4. 重启或停止服务
./deploy/start_screen.sh restart
./deploy/start_screen.sh stop
```

---

### 方式 B：手动交互式 Screen 步骤

如果您希望纯手工执行每一个命令：

```bash
# 1. 创建 Python 虚拟环境并安装依赖
cd /opt/readn/backend
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# 2. 新建名为 readn_backend 的后台 Screen 会话并进入
screen -S readn_backend

# 3. 在该会话中启动 Uvicorn 高性能 ASGI 服务
cd /opt/readn/backend
source venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 18903 --workers 2 --proxy-headers

# 4. 分离（挂起）会话：
# 键盘按下：Ctrl + A，随后松开并按下 D 键
# 终端提示 [detached from ...]，此时即已安全在后台运行！
```

---

## 四、Screen 常用运维操作速查表

| 操作需求 | 对应命令 | 说明 |
| :--- | :--- | :--- |
| **启动服务** | `./deploy/start_screen.sh start` | 自动在后台创建并运行 |
| **查看后台所有 Screen 会话** | `screen -ls` | 查看当前活跃会话 |
| **连接到会话 / 查看实时日志** | `screen -r readn_backend` | 进入后端实时运行终端 |
| **挂起并离开会话（保持后台运行）** | 键盘按 `Ctrl + A` 后按 `D` | **核心操作**：断开当前连接但保持进程后台运行 |
| **强制重新连接（若被占用）** | `screen -d -r readn_backend` | 先踢掉旧终端再连接 |
| **停止/关闭后端服务** | `./deploy/start_screen.sh stop` 或 `screen -X -S readn_backend quit` | 优雅终止后台进程 |

---

## 五、验证服务运行与云防火墙放行

### 1. 服务器本地健康检查
```bash
curl http://127.0.0.1:18903/api/health
# 正常输出: {"status":"healthy","service":"ReadN Backend API","version":"1.0.0"}
```

### 2. 云服务器安全组放行端口
- 前往阿里云 / 腾讯云 / 华为云 / AWS 等云控制台，在**安全组（Security Group）**或**防火墙**入站规则中，添加允许 **TCP 18903 端口**（或配置 Nginx 后的 80/443 端口）。

### 3. 前端应用连接配置
- 在 ReadN 前端设置中，将 API 基础地址设置为：`http://<您的云服务器公网IP>:18903` 即可畅享极速云端文档同步与大模型阅读交互！

---

## 六、进阶运维配置（可选）

### 1. 配置开机自启（Crontab）
避免云服务器因维护或重启后服务中断：
```bash
crontab -e
```
在文件末尾添加：
```cron
@reboot /bin/bash /opt/readn/backend/deploy/start_screen.sh start >> /var/log/readn_boot.log 2>&1
```

### 2. 配置 Nginx 反向代理与 HTTPS
如果需要通过标准 80/443 端口及自有域名提供服务，可直接使用提供的 `deploy/nginx.conf`：
```bash
sudo apt install -y nginx
sudo cp /opt/readn/backend/deploy/nginx.conf /etc/nginx/sites-available/readn.conf
sudo ln -s /etc/nginx/sites-available/readn.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```
如需配置免费 SSL 证书：
```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.com
```
