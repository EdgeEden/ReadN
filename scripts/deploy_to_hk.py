import os
import sys
import tarfile
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BACKEND = ROOT / "backend"
TAR_PATH = ROOT / "backend_deploy.tar.gz"

def create_tarball():
    print(f"[1/4] Packing backend/app and backend/static into {TAR_PATH.name}...")
    if TAR_PATH.exists():
        TAR_PATH.unlink()

    with tarfile.open(TAR_PATH, "w:gz") as tar:
        # 1. Add app/
        app_dir = BACKEND / "app"
        for p in app_dir.rglob("*"):
            if "__pycache__" in p.parts:
                continue
            arcname = "app/" + p.relative_to(app_dir).as_posix()
            tar.add(p, arcname=arcname)

        # 2. Add static/
        static_dir = BACKEND / "static"
        for p in static_dir.rglob("*"):
            arcname = "static/" + p.relative_to(static_dir).as_posix()
            tar.add(p, arcname=arcname)

    size_mb = TAR_PATH.stat().st_size / (1024 * 1024)
    print(f"  [OK] Archive created successfully ({size_mb:.2f} MB)")

def upload_to_hk():
    print("[2/4] Uploading archive to Hong Kong server via SCP...")
    cmd = ["scp", str(TAR_PATH), "hk:/root/readn/backend_deploy.tar.gz"]
    res = subprocess.run(cmd)
    if res.returncode != 0:
        print("[FAIL] SCP upload failed!")
        sys.exit(1)
    print("  [OK] Upload complete")

def extract_and_restart():
    print("[3/4] Extracting archive and restarting readn.service on HK server...")
    remote_script = (
        "set -e\n"
        "cd /root/readn/backend\n"
        "tar -xzf /root/readn/backend_deploy.tar.gz -C /root/readn/backend/\n"
        "systemctl restart readn.service\n"
        "sleep 2\n"
        "systemctl is-active readn.service\n"
    )
    cmd = ["ssh", "hk", remote_script]
    res = subprocess.run(cmd)
    if res.returncode != 0:
        print("[FAIL] Remote extraction or service restart failed!")
        sys.exit(1)
    print("  [OK] Service restarted and active")

def verify_health():
    print("[4/4] Verifying health check on HK server...")
    cmd = ["ssh", "hk", "curl -s http://127.0.0.1:18903/api/health"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    print(f"  Response: {res.stdout.strip()}")
    if "healthy" in res.stdout:
        print("[SUCCESS] Deployment to HK server completed successfully!")
    else:
        print("[WARN] Health check response unexpected:", res.stdout)

if __name__ == "__main__":
    create_tarball()
    upload_to_hk()
    extract_and_restart()
    verify_health()
