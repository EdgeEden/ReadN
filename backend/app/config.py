import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
STORAGE_DIR = BASE_DIR / "storage" / "documents"
STORAGE_DIR.mkdir(parents=True, exist_ok=True)
STATIC_DIR = BASE_DIR / "static"
STATIC_DIR.mkdir(parents=True, exist_ok=True)

DB_PATH = BASE_DIR / "readn.db"
DATABASE_URL = os.getenv("DATABASE_URL", f"sqlite+aiosqlite:///{DB_PATH}")

HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "18903"))

# Default byte range chunk size: 512 KB
DEFAULT_CHUNK_SIZE = 512 * 1024

CORS_ORIGINS = [
    "*",
    "http://localhost",
    "http://localhost:3000",
    "http://localhost:8080",
    "http://127.0.0.1",
    "http://127.0.0.1:3000",
    "http://127.0.0.1:8080",
]


APP_VERSION = "1.1.16"
