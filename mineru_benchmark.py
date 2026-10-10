#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MinerU API v4 速率与稳定性基准测试脚本 (Benchmark & Conversion Script)
用于在服务器（如 HK 服务器）上测试 MinerU 接口的连通性、上传速率、解析耗时、下载带宽及转换效果。

特性：
1. 全球/海外 OSS 传输加速 (OSS Transfer Acceleration)：
   - 针对香港及海外服务器跨境直连上海节点丢包卡顿问题，自动/按需启用阿里云全球传输加速专线：
     `mineru.oss-accelerate-overseas.aliyuncs.com` / `mineru.oss-accelerate.aliyuncs.com`
   - 彻底避免公网跨境拥塞导致的 SSLEOFError / Connection Reset。
2. 增强型大文件流式上传 (Streaming Upload)：
   - 解决 100MB+ 大文件上传时由单一内存缓冲导致的 SSL EOF 异常。
   - 包含实时动态进度条（已上传MB、百分比、实时瞬时带宽、剩余时间估算）。
   - 智能双引擎：原生 Python 流式上传 + 系统原生 curl 引擎（支持自动故障切换与重试）。
3. 自动检索目标 PDF 文件（自动匹配 /root 目录下或当前目录下的 PDF 文档）。
4. 详细的全链路耗时与吞吐量测算（API申请 -> OSS流式PUT上传 -> 云端排队与解析 -> 结果包下载 -> 解压与MD质量分析）。
5. 优雅的终端高亮与表格化报告输出。
"""

import os
import sys
import time
import json
import glob
import shutil
import zipfile
import argparse
import subprocess
from datetime import datetime

# 默认配置
DEFAULT_TOKEN = os.getenv("MINERU_API_TOKEN", "")
API_BASE = "https://mineru.net/api/v4"

try:
    import requests
    from requests.adapters import HTTPAdapter
    from urllib3.util.retry import Retry
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False
    import urllib.request
    import urllib.error


class StreamProgressReader:
    """流式文件读取器，支持在请求发送过程中计算实时进度与速率"""
    def __init__(self, filepath, callback=None, chunk_size=256 * 1024):
        self.filepath = filepath
        self.file = open(filepath, "rb")
        self.total_size = os.path.getsize(filepath)
        self.read_bytes = 0
        self.chunk_size = chunk_size
        self.callback = callback
        self.start_time = time.time()
        self.last_update = 0

    def read(self, size=-1):
        read_size = self.chunk_size if size is None or size < 0 else min(size, self.chunk_size)
        chunk = self.file.read(read_size)
        if chunk:
            self.read_bytes += len(chunk)
            now = time.time()
            if self.callback and (now - self.last_update >= 0.15 or self.read_bytes >= self.total_size):
                self.last_update = now
                self.callback(self.read_bytes, self.total_size, now - self.start_time)
        return chunk

    def __len__(self):
        return self.total_size

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()

    def close(self):
        if self.file and not self.file.closed:
            self.file.close()


class MinerUBenchmark:
    def __init__(self, token: str, file_path: str, model_version: str = "vlm", 
                 enable_formula: bool = True, enable_table: bool = True, 
                 upload_engine: str = "auto", oss_acc: str = "overseas"):
        self.token = token.strip()
        self.file_path = os.path.abspath(file_path)
        self.file_name = os.path.basename(self.file_path)
        self.file_size_bytes = os.path.getsize(self.file_path)
        self.file_size_mb = self.file_size_bytes / (1024 * 1024)
        self.model_version = model_version
        self.enable_formula = enable_formula
        self.enable_table = enable_table
        self.upload_engine = upload_engine
        self.oss_acc = oss_acc  # "overseas", "global", "off"

        self.session = None
        if HAS_REQUESTS:
            self.session = requests.Session()
            retry_strategy = Retry(
                total=3,
                backoff_factor=1,
                status_forcelist=[500, 502, 503, 504],
                raise_on_status=False
            )
            adapter = HTTPAdapter(max_retries=retry_strategy, pool_connections=5, pool_maxsize=5)
            self.session.mount("https://", adapter)
            self.session.mount("http://", adapter)

        self.stats = {
            "file_name": self.file_name,
            "file_size_mb": self.file_size_mb,
            "token_masked": self.token[:6] + "..." + self.token[-4:] if len(self.token) > 10 else "***",
            "upload_engine_used": "",
            "oss_acceleration_domain": "",
            "t_apply_api": 0.0,
            "t_upload": 0.0,
            "upload_speed_mb_s": 0.0,
            "t_parse_wait": 0.0,
            "t_download": 0.0,
            "download_size_mb": 0.0,
            "download_speed_mb_s": 0.0,
            "t_total": 0.0,
            "batch_id": None,
            "state": "unknown",
            "md_stats": {}
        }

    def _apply_oss_acceleration(self, url: str) -> str:
        """根据配置自动将普通 OSS 域名替换为阿里云传输加速专线域名"""
        if not url:
            return url
        
        target_domain = ""
        if self.oss_acc == "overseas":
            target_domain = "mineru.oss-accelerate-overseas.aliyuncs.com"
        elif self.oss_acc == "global":
            target_domain = "mineru.oss-accelerate.aliyuncs.com"
        else:
            return url

        if "mineru.oss-cn-shanghai.aliyuncs.com" in url:
            new_url = url.replace("mineru.oss-cn-shanghai.aliyuncs.com", target_domain)
            self.stats["oss_acceleration_domain"] = target_domain
            return new_url
        return url

    def _http_json(self, method: str, url: str, headers: dict = None, json_body: dict = None, timeout: int = 60):
        headers = headers or {}
        if HAS_REQUESTS:
            resp = self.session.request(method, url, headers=headers, json=json_body, timeout=timeout)
            return resp.status_code, resp.headers, resp.content
        else:
            req_data = json.dumps(json_body).encode("utf-8") if json_body is not None else None
            if json_body is not None:
                headers["Content-Type"] = "application/json"
            req = urllib.request.Request(url, data=req_data, headers=headers, method=method)
            try:
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    return resp.status, resp.headers, resp.read()
            except urllib.error.HTTPError as e:
                return e.code, e.headers, e.read()

    @staticmethod
    def _print_progress_bar(current: int, total: int, elapsed: float, prefix: str = "上传进度"):
        percent = (current / total) * 100 if total > 0 else 0
        speed_mb_s = (current / (1024 * 1024)) / elapsed if elapsed > 0 else 0
        remaining_s = (total - current) / (current / elapsed) if current > 0 and elapsed > 0 else 0
        
        cur_mb = current / (1024 * 1024)
        tot_mb = total / (1024 * 1024)
        
        bar_len = 25
        filled_len = int(bar_len * current // total) if total > 0 else 0
        bar = "=" * filled_len + ">" if filled_len < bar_len else "=" * bar_len
        bar = bar.ljust(bar_len, " ")

        sys.stdout.write(
            f"\r  ⏳ {prefix}: [{bar}] {percent:5.1f}% | {cur_mb:6.2f}/{tot_mb:.2f} MB | {speed_mb_s:5.2f} MB/s | 剩余 ~{remaining_s:4.1f}s   "
        )
        sys.stdout.flush()

    def run(self):
        print("\n" + "=" * 68)
        print("  🚀 MinerU API v4 连通性与转换性能基准测试 (VLM 大模型版)")
        print("=" * 68)
        print(f"  • 测试文件: {self.file_path}")
        print(f"  • 文件大小: {self.file_size_mb:.2f} MB ({self.file_size_bytes:,} 字节)")
        print(f"  • API Token: {self.stats['token_masked']}")
        print(f"  • 模型版本: {self.model_version} | 启用公式: {self.enable_formula} | 启用表格: {self.enable_table}")
        print(f"  • OSS 传输加速: {self.oss_acc.upper()} ({'开启 (推荐香港/海外服务器)' if self.oss_acc != 'off' else '关闭'})")
        print(f"  • 系统 curl 探测: {'可用' if shutil.which('curl') else '未检测到'}")
        print("-" * 68)

        start_total_time = time.time()

        try:
            # 1. 申请预签名上传 URL 与 Batch ID
            batch_id, raw_upload_url = self.step_apply_upload_url()

            # 应用 OSS 传输加速路由
            upload_url = self._apply_oss_acceleration(raw_upload_url)
            if self.stats["oss_acceleration_domain"]:
                print(f"  ⚡ 已启用专线传输加速 -> {self.stats['oss_acceleration_domain']}")

            # 2. 流式上传 PDF 文件到 OSS (带进度条与失败自动重试/回退)
            self.step_upload_file_robust(upload_url)

            # 3. 轮询云端解析状态
            extract_result = self.step_poll_parsing(batch_id)

            # 4. 下载并解压结果 Markdown Zip
            raw_zip_url = extract_result.get("full_zip_url")
            if not raw_zip_url:
                raise RuntimeError(f"解析完成但未返回 full_zip_url: {extract_result}")

            zip_url = self._apply_oss_acceleration(raw_zip_url)
            output_dir = self.step_download_and_extract(zip_url)

            # 5. 分析生成 Markdown 的内容质量与结构
            self.step_analyze_markdown(output_dir)

            self.stats["t_total"] = time.time() - start_total_time
            self.print_report(output_dir)

        except Exception as e:
            self.stats["t_total"] = time.time() - start_total_time
            print(f"\n❌ [ERROR] 转换测试过程中发生异常: {str(e)}")
            import traceback
            traceback.print_exc()
            sys.exit(1)

    def step_apply_upload_url(self):
        print("\n[阶段 1/4] 正在向 MinerU API 申请预签名上传链接与 Batch ID...")
        url = f"{API_BASE}/file-urls/batch"
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json"
        }
        payload = {
            "files": [
                {
                    "name": self.file_name,
                    "data_id": f"bench_{int(time.time())}"
                }
            ],
            "model_version": self.model_version,
            "enable_formula": self.enable_formula,
            "enable_table": self.enable_table
        }

        t0 = time.time()
        status, _, body_bytes = self._http_json("POST", url, headers=headers, json_body=payload)
        t_cost = time.time() - t0
        self.stats["t_apply_api"] = t_cost

        if status != 200:
            raise RuntimeError(f"申请 URL 接口返回非 200 (HTTP {status}): {body_bytes.decode('utf-8', errors='ignore')}")

        res = json.loads(body_bytes.decode("utf-8"))
        if res.get("code") != 0:
            raise RuntimeError(f"API 返回业务错误 (code={res.get('code')}): {res.get('msg')}")

        data = res.get("data", {})
        batch_id = data.get("batch_id")
        file_urls = data.get("file_urls", [])

        if not batch_id or not file_urls:
            raise RuntimeError(f"接口未返回有效的 batch_id 或 file_urls: {res}")

        self.stats["batch_id"] = batch_id
        print(f"  ✓ 申请成功 (耗时: {t_cost:.2f}s)")
        print(f"  • Batch ID: {batch_id}")
        return batch_id, file_urls[0]

    def step_upload_file_robust(self, upload_url: str):
        print(f"\n[阶段 2/4] 正在上传 PDF 文档到对象存储 (OSS)...")
        
        has_curl = shutil.which("curl") is not None
        
        # 决策使用哪个引擎
        if self.upload_engine == "curl" and has_curl:
            self._upload_with_curl(upload_url)
            return
        elif self.upload_engine == "python":
            self._upload_with_python_stream(upload_url)
            return

        # 默认 auto 模式：优先 Python 流式上传，遇到 SSL/连接重置自动回退至 curl
        try:
            self._upload_with_python_stream(upload_url)
        except Exception as py_err:
            if has_curl:
                print(f"\n  ⚠️ Python 流式上传遇到网络异常 ({type(py_err).__name__})，正在自动切换至系统原生 curl 引擎重试...")
                self._upload_with_curl(upload_url)
            else:
                raise py_err

    def _upload_with_python_stream(self, upload_url: str):
        self.stats["upload_engine_used"] = "Python Streaming"
        t0 = time.time()
        
        def progress_cb(current, total, elapsed):
            self._print_progress_bar(current, total, elapsed, prefix="上传进度")

        headers = {
            "Content-Length": str(self.file_size_bytes)
        }

        if HAS_REQUESTS:
            with StreamProgressReader(self.file_path, callback=progress_cb) as stream:
                resp = self.session.put(
                    upload_url, 
                    data=stream, 
                    headers=headers, 
                    timeout=(30, 900),
                    allow_redirects=False
                )
                status_code = resp.status_code
                resp_text = resp.text
        else:
            with StreamProgressReader(self.file_path, callback=progress_cb) as stream:
                req = urllib.request.Request(upload_url, data=stream, headers=headers, method="PUT")
                try:
                    with urllib.request.urlopen(req, timeout=900) as resp:
                        status_code = resp.status
                        resp_text = resp.read().decode("utf-8", errors="ignore")
                except urllib.error.HTTPError as e:
                    status_code = e.code
                    resp_text = e.read().decode("utf-8", errors="ignore")

        t_cost = time.time() - t0
        self.stats["t_upload"] = t_cost

        if status_code not in (200, 201):
            raise RuntimeError(f"OSS 上传失败 (HTTP {status_code}): {resp_text}")

        speed = self.file_size_mb / t_cost if t_cost > 0 else 0
        self.stats["upload_speed_mb_s"] = speed
        print(f"\n  ✓ 上传完成! 耗时: {t_cost:.2f}s | 平均上传带宽: {speed:.2f} MB/s ({speed*8:.2f} Mbps) [引擎: Python Streaming]")

    def _upload_with_curl(self, upload_url: str):
        self.stats["upload_engine_used"] = "Native cURL"
        t0 = time.time()
        print(f"  • 使用系统原生 curl 执行底层流式传输...")

        cmd = [
            "curl",
            "-X", "PUT",
            "--upload-file", self.file_path,
            "-H", f"Content-Length: {self.file_size_bytes}",
            "--progress-bar",
            "-w", "\nHTTP_STATUS:%{http_code}\nTIME_TOTAL:%{time_total}\nSPEED_UPLOAD:%{speed_upload}\n",
            upload_url
        ]

        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=sys.stderr, text=True)
        stdout, _ = proc.communicate()
        t_cost = time.time() - t0
        self.stats["t_upload"] = t_cost

        http_code = 0
        curl_speed_bytes = 0.0
        for line in stdout.splitlines():
            if line.startswith("HTTP_STATUS:"):
                try:
                    http_code = int(line.split(":", 1)[1].strip())
                except ValueError:
                    pass
            elif line.startswith("SPEED_UPLOAD:"):
                try:
                    curl_speed_bytes = float(line.split(":", 1)[1].strip())
                except ValueError:
                    pass

        if proc.returncode != 0 or http_code not in (200, 201):
            raise RuntimeError(f"curl 上传失败 (退出码: {proc.returncode}, HTTP 状态码: {http_code})")

        speed = (curl_speed_bytes / (1024 * 1024)) if curl_speed_bytes > 0 else (self.file_size_mb / t_cost if t_cost > 0 else 0)
        self.stats["upload_speed_mb_s"] = speed
        print(f"\n  ✓ 上传完成! 耗时: {t_cost:.2f}s | 平均上传带宽: {speed:.2f} MB/s ({speed*8:.2f} Mbps) [引擎: Native cURL]")

    def step_poll_parsing(self, batch_id: str, poll_interval: int = 3, max_timeout: int = 1800):
        print(f"\n[阶段 3/4] 正在等待 MinerU 云端模型解析 (轮询间隔: {poll_interval}s)...")
        url = f"{API_BASE}/extract-results/batch/{batch_id}"
        headers = {
            "Authorization": f"Bearer {self.token}"
        }

        t0 = time.time()
        dots = 0
        last_state = ""

        while True:
            elapsed = time.time() - t0
            if elapsed > max_timeout:
                raise TimeoutError(f"云端解析超时 (已等待超过 {max_timeout}s)")

            status, _, body_bytes = self._http_json("GET", url, headers=headers, timeout=30)
            if status != 200:
                print(f"\n  ⚠️ 轮询返回非 200 (HTTP {status})，重试中...")
                time.sleep(poll_interval)
                continue

            res = json.loads(body_bytes.decode("utf-8"))
            if res.get("code") != 0:
                raise RuntimeError(f"查询解析状态失败 (code={res.get('code')}): {res.get('msg')}")

            extract_results = res.get("data", {}).get("extract_result", [])
            if not extract_results:
                time.sleep(poll_interval)
                continue

            item = extract_results[0]
            state = item.get("state", "pending")
            self.stats["state"] = state
            progress = item.get("extract_progress", "")
            prog_str = f" [进度: {progress}]" if progress else ""

            if state != last_state:
                last_state = state
                print(f"\n  • 状态变更 -> [{state.upper()}]{prog_str} (已耗时: {elapsed:.1f}s)")
            else:
                sys.stdout.write(f"\r  ⏳ 等待中... 状态: [{state.upper()}]{prog_str} | 已耗时: {elapsed:.1f}s " + ("." * (dots % 4)) + "   ")
                sys.stdout.flush()
                dots += 1

            if state == "done":
                print(f"\n  ✓ 云端解析完成! 耗时: {elapsed:.2f}s")
                self.stats["t_parse_wait"] = elapsed
                return item
            elif state == "failed":
                err_msg = item.get("err_msg", "未知错误")
                raise RuntimeError(f"云端解析任务失败: {err_msg}")

            time.sleep(poll_interval)

    def step_download_and_extract(self, zip_url: str):
        print(f"\n[阶段 4/4] 正在下载并解压 Markdown 结果包...")
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        base_dir = os.path.dirname(self.file_path)
        out_dir = os.path.join(base_dir, f"mineru_output_{timestamp}")
        os.makedirs(out_dir, exist_ok=True)
        zip_path = os.path.join(out_dir, "result.zip")

        t0 = time.time()
        downloaded_bytes = 0
        total_length = 0

        if HAS_REQUESTS:
            with self.session.get(zip_url, stream=True, timeout=300) as r:
                r.raise_for_status()
                total_length = int(r.headers.get("content-length", 0))
                with open(zip_path, "wb") as f:
                    for chunk in r.iter_content(chunk_size=512 * 1024):
                        if chunk:
                            f.write(chunk)
                            downloaded_bytes += len(chunk)
                            if total_length > 0:
                                self._print_progress_bar(downloaded_bytes, total_length, time.time() - t0, prefix="下载进度")
        else:
            with urllib.request.urlopen(zip_url, timeout=300) as resp:
                total_length = int(resp.headers.get("Content-Length", 0))
                with open(zip_path, "wb") as f:
                    while True:
                        chunk = resp.read(512 * 1024)
                        if not chunk:
                            break
                        f.write(chunk)
                        downloaded_bytes += len(chunk)
                        if total_length > 0:
                            self._print_progress_bar(downloaded_bytes, total_length, time.time() - t0, prefix="下载进度")

        t_cost = time.time() - t0
        self.stats["t_download"] = t_cost
        zip_size_mb = os.path.getsize(zip_path) / (1024 * 1024)
        self.stats["download_size_mb"] = zip_size_mb
        speed = zip_size_mb / t_cost if t_cost > 0 else 0
        self.stats["download_speed_mb_s"] = speed

        print(f"\n  ✓ 下载完成! 大小: {zip_size_mb:.2f} MB | 耗时: {t_cost:.2f}s | 平均下载带宽: {speed:.2f} MB/s ({speed*8:.2f} Mbps)")

        with zipfile.ZipFile(zip_path, "r") as zf:
            zf.extractall(out_dir)

        print(f"  ✓ 结果已成功解压至: {out_dir}")
        return out_dir

    def step_analyze_markdown(self, output_dir: str):
        md_files = glob.glob(os.path.join(output_dir, "**", "*.md"), recursive=True)
        if not md_files:
            print("  ⚠️ 未在结果包中找到 .md 文件")
            return

        main_md = md_files[0]
        for mf in md_files:
            if "full.md" in os.path.basename(mf):
                main_md = mf
                break

        with open(main_md, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()

        lines = content.splitlines()
        char_count = len(content)
        inline_formulas = content.count("$") - content.count("$$") * 2
        block_formulas = content.count("$$") // 2
        tables_count = content.count("|---")
        headings_count = sum(1 for line in lines if line.strip().startswith("#"))

        image_files = []
        for ext in ("*.png", "*.jpg", "*.jpeg", "*.webp"):
            image_files.extend(glob.glob(os.path.join(output_dir, "**", ext), recursive=True))

        self.stats["md_stats"] = {
            "main_md_path": main_md,
            "char_count": char_count,
            "line_count": len(lines),
            "headings_count": headings_count,
            "inline_formulas": max(0, inline_formulas),
            "block_formulas": max(0, block_formulas),
            "tables_count": tables_count,
            "image_count": len(image_files)
        }

    def print_report(self, output_dir: str):
        s = self.stats
        md = s.get("md_stats", {})

        print("\n" + "=" * 68)
        print("  📊 MinerU API 性能基准测试与转换结果报告")
        print("=" * 68)
        print(f"  【任务信息】")
        print(f"    • 文档名称: {s['file_name']}")
        print(f"    • 文档大小: {s['file_size_mb']:.2f} MB")
        print(f"    • 任务批次 (Batch ID): {s['batch_id']}")
        print(f"    • 最终状态: {s['state'].upper()}")
        print(f"    • 上传引擎: {s['upload_engine_used']}")
        print(f"    • 传输专线: {s['oss_acceleration_domain'] or '默认直连'}")
        print("-" * 68)
        print(f"  【全链路耗时与速率分析】")
        print(f"    1. 接口预申请耗时 : {s['t_apply_api']:.3f} s")
        print(f"    2. 文件上传耗时   : {s['t_upload']:.2f} s  (速率: {s['upload_speed_mb_s']:.2f} MB/s = {s['upload_speed_mb_s']*8:.2f} Mbps)")
        print(f"    3. 云端解析耗时   : {s['t_parse_wait']:.2f} s  (MinerU VLM 模型端到端推理)")
        print(f"    4. 结果下载耗时   : {s['t_download']:.2f} s  (包大小: {s['download_size_mb']:.2f} MB, 速率: {s['download_speed_mb_s']:.2f} MB/s)")
        print(f"    --------------------------------------------------")
        print(f"    ⏱️ 全流程总用时   : {s['t_total']:.2f} s (约 {s['t_total']/60:.1f} 分钟)")
        print("-" * 68)
        if md:
            print(f"  【Markdown 转换质量指标】")
            print(f"    • 主文件路径 : {md.get('main_md_path')}")
            print(f"    • 字符总数   : {md.get('char_count'):,} 字 / {md.get('line_count'):,} 行")
            print(f"    • 标题层级   : {md.get('headings_count')} 个")
            print(f"    • 公式识别   : {md.get('inline_formulas')} 处行内公式 / {md.get('block_formulas')} 处块级公式")
            print(f"    • 表格识别   : {md.get('tables_count')} 个")
            print(f"    • 提取图片   : {md.get('image_count')} 张")
            print("-" * 68)
        print(f"  📁 输出目录: {output_dir}")
        print("=" * 68 + "\n")


def find_default_pdf():
    search_dirs = ["/root", ".", "..", os.path.expanduser("~")]
    candidates = []

    for d in search_dirs:
        if os.path.exists(d):
            candidates.extend(glob.glob(os.path.join(d, "*光纤*.pdf")))
            candidates.extend(glob.glob(os.path.join(d, "*Fiber*.pdf")))
            candidates.extend(glob.glob(os.path.join(d, "*.pdf")))

    valid = []
    for c in candidates:
        if c not in valid and os.path.isfile(c):
            valid.append(c)

    return valid[0] if valid else None


def main():
    parser = argparse.ArgumentParser(description="MinerU API v4 速率与稳定性测试工具 (支持 OSS 传输加速)")
    parser.add_argument("--file", "-f", type=str, default=None, help="待转换的 PDF 文件路径 (默认自动在 /root 或当前目录搜索)")
    parser.add_argument("--token", "-t", type=str, default=DEFAULT_TOKEN, help="MinerU API Token")
    parser.add_argument("--model", "-m", type=str, default="vlm", choices=["vlm", "pipeline"], help="模型版本 (默认: vlm)")
    parser.add_argument("--engine", "-e", type=str, default="auto", choices=["auto", "curl", "python"], help="文件上传引擎 (默认: auto，支持自动回退)")
    parser.add_argument("--oss-acc", "-a", type=str, default="overseas", choices=["overseas", "global", "off"], 
                        help="OSS 传输加速专线模式 (默认: overseas 海外专线加速，可选: global 全球加速, off 关闭)")
    parser.add_argument("--no-formula", action="store_true", help="禁用公式识别")
    parser.add_argument("--no-table", action="store_true", help="禁用表格识别")

    args = parser.parse_args()

    target_file = args.file
    if not target_file:
        target_file = find_default_pdf()
        if not target_file:
            print("❌ 错误: 未指定 --file 且在 /root 及当前目录下未找到 PDF 文件！")
            print("用法: python3 mineru_benchmark.py --file /path/to/your.pdf")
            sys.exit(1)

    if not os.path.exists(target_file):
        print(f"❌ 错误: 指定的 PDF 文件不存在: {target_file}")
        sys.exit(1)

    runner = MinerUBenchmark(
        token=args.token,
        file_path=target_file,
        model_version=args.model,
        enable_formula=not args.no_formula,
        enable_table=not args.no_table,
        upload_engine=args.engine,
        oss_acc=args.oss_acc
    )
    runner.run()


if __name__ == "__main__":
    main()
