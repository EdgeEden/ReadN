#!/usr/bin/env bash

# ==============================================================================
# ReadN Backend - Screen Startup & Management Script
# ==============================================================================

SESSION_NAME="readn_backend"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="$APP_DIR/venv"
PORT=8000
HOST="0.0.0.0"
WORKERS=2

echo ">>> ReadN Backend App Directory: $APP_DIR"

# 1. Check if virtual environment exists, create if not
if [ ! -d "$VENV_DIR" ]; then
    echo ">>> Creating Python virtual environment at $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
    "$VENV_DIR/bin/pip" install --upgrade pip
    "$VENV_DIR/bin/pip" install -r "$APP_DIR/requirements.txt"
    echo ">>> Note: For full OCR & Math formula support, ensure system packages are installed:"
    echo "    sudo apt-get update && sudo apt-get install -y tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-eng tesseract-ocr-equ ocrmypdf"
fi

# 2. Check if screen session already exists
if screen -list | grep -q "\.${SESSION_NAME}\s"; then
    echo ">>> A screen session '$SESSION_NAME' is already running!"
    echo ">>> To attach: screen -r $SESSION_NAME"
    echo ">>> To stop:   screen -X -S $SESSION_NAME quit"
    exit 0
fi

# 3. Start uvicorn in a new detached screen session
echo ">>> Starting ReadN Backend in background screen session: $SESSION_NAME..."
screen -dmS "$SESSION_NAME" bash -c "
    cd '$APP_DIR'
    source '$VENV_DIR/bin/activate'
    echo 'Starting Uvicorn ASGI Server on http://$HOST:$PORT ...'
    exec uvicorn app.main:app --host $HOST --port $PORT --workers $WORKERS --proxy-headers
"

echo ">>> Successfully launched in screen session '$SESSION_NAME'!"
echo ">>> Commands:"
echo "    - View logs / attach : screen -r $SESSION_NAME"
echo "    - Detach session     : Press Ctrl+A, then press D"
echo "    - List sessions      : screen -ls"
echo "    - Stop server        : screen -X -S $SESSION_NAME quit"

