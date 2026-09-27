#!/usr/bin/env bash

# ==============================================================================
# ReadN Backend - Screen Process Manager (Linux Cloud Deployment)
# Usage:
#   ./deploy/start_screen.sh [start|stop|restart|status|logs]
# ==============================================================================

SESSION_NAME="readn_backend"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="$APP_DIR/venv"
PORT=18903
HOST="0.0.0.0"
WORKERS=2

is_running() {
    screen -list | grep -q "${SESSION_NAME}"
}

start_server() {
    if is_running; then
        echo ">>> [提示] ReadN 后端服务已在 Screen 会话 '$SESSION_NAME' 中运行！"
        echo ">>> 执行 './deploy/start_screen.sh logs' 或 'screen -r $SESSION_NAME' 查看实时日志。"
        return 0
    fi

    echo ">>> ReadN 部署目录: $APP_DIR"

    # 1. 自动初始化 Python 虚拟环境并安装依赖
    if [ ! -d "$VENV_DIR" ]; then
        echo ">>> 正在创建 Python 3 虚拟环境 ($VENV_DIR)..."
        python3 -m venv "$VENV_DIR" || {
            echo ">>> [错误] 创建虚拟环境失败，请确认系统已安装 python3-venv (例如 sudo apt install python3-venv)"
            exit 1
        }
        echo ">>> 正在安装后端依赖库 (requirements.txt)..."
        "$VENV_DIR/bin/pip" install -i https://mirrors.aliyun.com/pypi/simple/ -r "$APP_DIR/requirements.txt"
    fi

    # 2. 确保存储目录就绪
    mkdir -p "$APP_DIR/storage/documents"

    # 3. 确保端口没有残留孤儿进程占用
    fuser -k "$PORT/tcp" 2>/dev/null || true
    sleep 0.5

    # 4. 在独立的后台 Screen 会话中启动 Uvicorn ASGI 服务
    echo ">>> 正在通过 Screen 启动 ReadN 后端服务 (端口: $PORT, Worker: $WORKERS)..."
    screen -dmS "$SESSION_NAME" bash -c "
        cd '$APP_DIR'
        exec '$VENV_DIR/bin/uvicorn' app.main:app --host $HOST --port $PORT --workers $WORKERS --proxy-headers
    "

    sleep 1.5

    if is_running; then
        echo "=================================================================="
        echo ">>> [成功] ReadN 后端已在 Screen 后台会话 '$SESSION_NAME' 中启动！"
        echo ">>> API 地址: http://$HOST:$PORT"
        echo ">>> 健康检查: curl http://127.0.0.1:$PORT/api/health"
        echo "=================================================================="
        echo "常用运维命令:"
        echo "  - 查看实时日志: ./deploy/start_screen.sh logs   (退出查看按 Ctrl+A 然后按 D)"
        echo "  - 查看运行状态: ./deploy/start_screen.sh status"
        echo "  - 停止后端服务: ./deploy/start_screen.sh stop"
        echo "  - 重启后端服务: ./deploy/start_screen.sh restart"
        echo "=================================================================="
    else
        echo ">>> [警告] 服务启动后未检测到活跃的 Screen 会话，请手动排查或检查端口占用情况。"
    fi
}

stop_server() {
    echo ">>> 正在停止 ReadN 后端服务..."
    if is_running; then
        screen -X -S "$SESSION_NAME" quit 2>/dev/null || true
        sleep 1
    fi
    # Thoroughly ensure port is released
    pkill -f "uvicorn app.main:app.*$PORT" 2>/dev/null || true
    fuser -k "$PORT/tcp" 2>/dev/null || true
    sleep 0.5
    echo ">>> [成功] ReadN 后端服务已停止。"
}

status_server() {
    if is_running; then
        echo ">>> [运行中] Screen 会话 '$SESSION_NAME' 正在后台运行。"
        screen -list | grep "$SESSION_NAME"
    else
        echo ">>> [未运行] Screen 会话 '$SESSION_NAME' 当前未运行。"
    fi
}

logs_server() {
    if is_running; then
        echo ">>> 正在连接到 Screen 会话 '$SESSION_NAME' (退出查看请按 Ctrl+A 然后按 D)..."
        screen -r "$SESSION_NAME"
    else
        echo ">>> [提示] Screen 会话 '$SESSION_NAME' 当前未运行，无法查看实时日志。"
    fi
}

case "$1" in
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    restart)
        stop_server
        sleep 1
        start_server
        ;;
    status)
        status_server
        ;;
    logs)
        logs_server
        ;;
    *)
        start_server
        ;;
esac
