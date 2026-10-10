import os
import sys
import tarfile
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BACKEND = ROOT / "backend"
TAR_PATH = ROOT / "backend_deploy.tar.gz"

def log(msg: str):
    print(msg, flush=True)

def create_tarball():
    log(f"[1/4] Packing backend/app and backend/static into {TAR_PATH.name}...")
    if TAR_PATH.exists():
        TAR_PATH.unlink()

    with tarfile.open(TAR_PATH, "w:gz") as tar:
        # 1. Add app/
        app_dir = BACKEND / "app"
        for p in app_dir.rglob("*"):
            if "__pycache__" in p.parts:
                continue
            arcname = "app/" + p.relative_to(app_dir).as_posix()
            tar.add(p, arcname=arcname, recursive=False)

        # 2. Add static/
        static_dir = BACKEND / "static"
        for p in static_dir.rglob("*"):
            arcname = "static/" + p.relative_to(static_dir).as_posix()
            tar.add(p, arcname=arcname, recursive=False)

    size_mb = TAR_PATH.stat().st_size / (1024 * 1024)
    log(f"  [OK] Archive created successfully ({size_mb:.2f} MB)")

def upload_to_hk():
    log("[2/4] Uploading archive to Hong Kong server via SCP...")
    cmd = ["scp", "-o", "ConnectTimeout=15", "-o", "BatchMode=yes", str(TAR_PATH), "hk:/root/readn/backend_deploy.tar.gz"]
    try:
        res = subprocess.run(cmd, stdin=subprocess.DEVNULL, timeout=120)
        if res.returncode != 0:
            log("[FAIL] SCP upload failed!")
            sys.exit(1)
        log("  [OK] Upload complete")
    except subprocess.TimeoutExpired:
        log("[FAIL] SCP upload timed out after 120s!")
        sys.exit(1)

def extract_and_restart():
    log("[3/4] Extracting archive and restarting readn.service on HK server...")
    remote_script = (
        "set -e\n"
        "cd /root/readn/backend\n"
        "tar -xzf /root/readn/backend_deploy.tar.gz -C /root/readn/backend/\n"
        "systemctl restart readn.service\n"
        "sleep 2\n"
        "systemctl is-active readn.service\n"
    )
    cmd = ["ssh", "-n", "-o", "ConnectTimeout=15", "-o", "BatchMode=yes", "hk", remote_script]
    try:
        res = subprocess.run(cmd, stdin=subprocess.DEVNULL, timeout=40)
        if res.returncode != 0:
            log("[FAIL] Remote extraction or service restart failed!")
            sys.exit(1)
        log("  [OK] Service restarted and active")
    except subprocess.TimeoutExpired:
        log("[FAIL] Remote restart command timed out!")
        sys.exit(1)

def verify_health():
    log("[4/4] Verifying health check on HK server...")
    import urllib.request
    import json
    for target in ["http://107.151.245.68:18903/api/health"]:
        try:
            req = urllib.request.Request(target, headers={"User-Agent": "ReadNDeploy/1.0"})
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                log(f"  Health check response: {data}")
                if data.get("status") == "healthy":
                    log("[SUCCESS] Deployment to HK server completed successfully!")
                    return
        except Exception as e:
            log(f"  Direct HTTP check error: {e}")
            
    # Fallback to ssh curl with timeout
    try:
        cmd = ["ssh", "-n", "-o", "ConnectTimeout=10", "-o", "BatchMode=yes", "hk", "curl -s http://127.0.0.1:18903/api/health"]
        res = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15)
        log(f"  SSH fallback response: {res.stdout.strip()}")
        if "healthy" in res.stdout:
            log("[SUCCESS] Deployment to HK server completed successfully!")
            return
    except Exception as e:
        log(f"  SSH fallback failed: {e}")
    log("[WARN] Health check verification could not confirm status.")

if __name__ == "__main__":
    create_tarball()
    upload_to_hk()
    extract_and_restart()
    verify_health()
