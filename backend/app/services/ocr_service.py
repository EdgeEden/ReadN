import asyncio
import hashlib
import json
import logging
import os
import re
import shutil
import time
from pathlib import Path
from typing import Dict, Any, Optional, List
import aiofiles
import fitz
import requests
from pypdf import PdfReader
from sqlalchemy import select

from app.models import DocumentModel, OcrRequest

logger = logging.getLogger("ocr_service")


def detect_text_layer(pdf_path: str) -> bool:
    """
    Detect whether a PDF has an embedded digital text layer.
    Returns True if extractable text is present (digital PDF), False if scanned/image-only PDF.
    """
    try:
        reader = PdfReader(pdf_path)
        total_chars = 0
        for i, page in enumerate(reader.pages):
            text = page.extract_text() or ""
            total_chars += len(text.strip())
            if total_chars >= 30:
                return True
        return total_chars >= 30
    except Exception as e:
        logger.warning(f"Error detecting text layer in {pdf_path}: {e}")
        return True


DEFAULT_PADDLEOCR_OPTIONAL_PAYLOAD = {
    "markdownIgnoreLabels": [
        "header",
        "header_image",
        "footer",
        "footer_image",
        "number",
        "footnote",
        "aside_text"
    ],
    "useDocOrientationClassify": False,
    "useDocUnwarping": False,
    "useLayoutDetection": True,
    "useChartRecognition": False,
    "useSealRecognition": True,
    "useOcrForImageBlock": False,
    "mergeTables": True,
    "relevelTitles": True,
    "layoutShapeMode": "auto",
    "promptLabel": "ocr",
    "repetitionPenalty": 1,
    "temperature": 0,
    "topP": 1,
    "minPixels": 147384,
    "maxPixels": 2822400,
    "layoutNms": True,
    "restructurePages": True
}


def run_paddleocr_vl_ocr_sync(
    input_path: str,
    output_path: Optional[str] = None,
    markdown_path: Optional[str] = None,
    target_pages: Optional[List[int]] = None,
    api_token: str = "REDACTED_BAIDU_TOKEN",
    api_url: str = "https://paddleocr.aistudio-app.com/api/v2/ocr/jobs",
    model_name: str = "PaddleOCR-VL-1.6",
    optional_payload: Optional[Dict[str, Any]] = None,
    progress_callback=None
) -> bool:
    """
    Online Multi-modal OCR using Baidu AI Studio PaddleOCR-VL-1.6 API.
    Supports full document or selective page range OCR with mathematical formula LaTeX support,
    extracting structured Markdown (with LaTeX math & HTML tables) without modifying the original PDF.
    """
    src_doc = None
    sub_doc = None
    try:
        src_doc = fitz.open(input_path)
        total_doc_pages = len(src_doc)
        
        # Resolve target pages (1-indexed)
        if not target_pages:
            active_pages = list(range(1, total_doc_pages + 1))
        else:
            active_pages = sorted(list(set([p for p in target_pages if 1 <= p <= total_doc_pages])))
            if not active_pages:
                active_pages = list(range(1, total_doc_pages + 1))
                
        num_target_pages = len(active_pages)
        
        if progress_callback:
            progress_callback(
                0.05,
                f"正在准备 PaddleOCR-VL API 任务 (目标 {num_target_pages} 页)...",
                current_page=0,
                total_pages=num_target_pages
            )

        # 1. Build sub-PDF containing only target pages
        sub_doc = fitz.open()
        for p_num in active_pages:
            sub_doc.insert_pdf(src_doc, from_page=p_num - 1, to_page=p_num - 1)
        sub_pdf_bytes = sub_doc.tobytes()
    finally:
        if sub_doc:
            try:
                sub_doc.close()
            except Exception:
                pass
        if src_doc:
            try:
                src_doc.close()
            except Exception:
                pass

    # 2. Submit Job to PaddleOCR-VL API
    token_clean = (api_token or "").strip()
    if token_clean.lower().startswith("bearer "):
        token_clean = token_clean[7:].strip()
        
    headers = {
        "Authorization": f"bearer {token_clean}",
    }
    
    payload_opts = dict(DEFAULT_PADDLEOCR_OPTIONAL_PAYLOAD)
    if optional_payload:
        for k, v in optional_payload.items():
            if v is not None:
                payload_opts[k] = v
    
    data = {
        "model": model_name,
        "optionalPayload": json.dumps(payload_opts)
    }
    files = {"file": ("ocr_target.pdf", sub_pdf_bytes, "application/pdf")}

    if progress_callback:
        progress_callback(
            0.15,
            "正在上传文档并创建 PaddleOCR-VL 识别任务...",
            current_page=0,
            total_pages=num_target_pages
        )

    job_res = requests.post(api_url, headers=headers, data=data, files=files, timeout=90)
    if job_res.status_code != 200:
        raise Exception(f"PaddleOCR API 提交失败 ({job_res.status_code}): {job_res.text}")
    
    job_data = job_res.json()
    if job_data.get("code") != 0 or "data" not in job_data:
        raise Exception(f"PaddleOCR API 错误: {job_data.get('msg', job_res.text)}")
        
    job_id = job_data["data"]["jobId"]
    logger.info(f"PaddleOCR-VL Job submitted successfully: jobId={job_id}")

    # 3. Poll for results
    jsonl_url = None
    max_retries = 150  # 150 * 3s = 450s timeout
    for attempt in range(max_retries):
        time.sleep(3)
        try:
            poll_res = requests.get(f"{api_url}/{job_id}", headers=headers, timeout=30)
            if poll_res.status_code != 200:
                continue
            poll_data = poll_res.json().get("data", {})
        except Exception as e:
            logger.warning(f"PaddleOCR-VL polling network warning (attempt {attempt+1}): {e}")
            continue

        state = poll_data.get("state", "pending")
        extract_prog = poll_data.get("extractProgress", {})
        extracted_p = extract_prog.get("extractedPages", 0)
        total_p = extract_prog.get("totalPages", num_target_pages)

        if state == "pending":
            if progress_callback:
                progress_callback(
                    0.20,
                    "PaddleOCR-VL 云端任务排队中...",
                    current_page=0,
                    total_pages=num_target_pages
                )
        elif state == "running":
            prog = 0.20 + 0.70 * (extracted_p / max(total_p, 1))
            if progress_callback:
                progress_callback(
                    prog,
                    f"PaddleOCR-VL 正在识别第 {extracted_p}/{total_p} 页 (排版与数学公式解析)...",
                    current_page=extracted_p,
                    total_pages=num_target_pages
                )
        elif state == "done":
            extracted_pages = extract_prog.get("extractedPages", num_target_pages)
            start_time = extract_prog.get("startTime", "")
            end_time = extract_prog.get("endTime", "")
            logger.info(f"PaddleOCR-VL Job completed: extracted={extracted_pages}, start={start_time}, end={end_time}")
            if progress_callback:
                progress_callback(
                    0.95,
                    "PaddleOCR-VL 识别完成，正在解析 Markdown 内容...",
                    current_page=num_target_pages,
                    total_pages=num_target_pages
                )
            result_url_obj = poll_data.get("resultUrl", {})
            if isinstance(result_url_obj, dict):
                jsonl_url = result_url_obj.get("jsonUrl") or result_url_obj.get("jsonlUrl")
            elif isinstance(result_url_obj, str):
                jsonl_url = result_url_obj
            break
        elif state == "failed":
            error_msg = poll_data.get("errorMsg", "Unknown error")
            raise Exception(f"PaddleOCR-VL 任务失败: {error_msg}")

    if not jsonl_url:
        raise Exception("PaddleOCR-VL 识别超时或未获取到结果数据 URL")

    # 4. Download and Parse JSON/JSONL
    jsonl_resp = requests.get(jsonl_url, timeout=60)
    jsonl_resp.raise_for_status()
    jsonl_text = jsonl_resp.text.strip()
    lines = jsonl_text.split('\n')
    
    page_results = []
    for line_num, line in enumerate(lines, start=1):
        line = line.strip()
        if not line:
            continue
        try:
            line_data = json.loads(line)
            result = line_data.get("result", {})
            if isinstance(result, dict) and "layoutParsingResults" in result:
                page_results.extend(result["layoutParsingResults"])
            elif "layoutParsingResults" in line_data:
                page_results.extend(line_data["layoutParsingResults"])
            elif "prunedResult" in line_data or "markdown" in line_data:
                page_results.append(line_data)
        except Exception as e:
            logger.warning(f"Error parsing JSONL line {line_num}: {e}")

    if not page_results:
        try:
            data_obj = json.loads(jsonl_text)
            if isinstance(data_obj, dict) and "result" in data_obj and "layoutParsingResults" in data_obj["result"]:
                page_results = data_obj["result"]["layoutParsingResults"]
            elif isinstance(data_obj, list):
                page_results = data_obj
        except Exception:
            pass

    # 5. Extract Markdown text per page & write to Markdown output path
    target_idx_to_markdown = {}
    for i, p_num in enumerate(active_pages):
        if i < len(page_results):
            res = page_results[i]
            md_text = ""
            if isinstance(res, dict) and "markdown" in res and isinstance(res["markdown"], dict):
                md_text = res["markdown"].get("text", "")
            elif isinstance(res, dict) and "text" in res:
                md_text = res.get("text", "")
            target_idx_to_markdown[p_num] = md_text

    effective_md_path = markdown_path or str(Path(input_path).with_suffix(".md"))
    try:
        existing_pages = {}
        if os.path.exists(effective_md_path):
            try:
                with open(effective_md_path, "r", encoding="utf-8") as f_md:
                    existing_content = f_md.read()
                page_splits = re.split(r'<!--\s*Page\s+(\d+)\s*-->', existing_content, flags=re.IGNORECASE)
                if len(page_splits) > 1:
                    for j in range(1, len(page_splits), 2):
                        try:
                            p_no = int(page_splits[j])
                            p_txt = page_splits[j + 1].strip()
                            existing_pages[p_no] = p_txt
                        except Exception:
                            pass
            except Exception as e:
                logger.warning(f"Error reading existing markdown {effective_md_path}: {e}")
        
        # Merge newly extracted markdown pages
        for p_num, md_text in target_idx_to_markdown.items():
            if md_text:
                existing_pages[p_num] = md_text

        sorted_pnums = sorted(existing_pages.keys())
        if sorted_pnums:
            with open(effective_md_path, "w", encoding="utf-8") as f_md:
                for idx_p, p_no in enumerate(sorted_pnums):
                    f_md.write(f"<!-- Page {p_no} -->\n\n")
                    f_md.write(existing_pages[p_no])
                    if idx_p < len(sorted_pnums) - 1:
                        f_md.write("\n\n")
            logger.info(f"PaddleOCR-VL Markdown saved successfully: {effective_md_path}")
        else:
            raise Exception("未从 PaddleOCR-VL 识别结果中提取到有效 Markdown 内容")
    except Exception as e:
        logger.error(f"Failed to write Markdown file {effective_md_path}: {e}")
        raise

    if progress_callback:
        progress_callback(
            1.0,
            f"PaddleOCR-VL 解析成功！已提取 {num_target_pages} 页结构化 Markdown。",
            current_page=num_target_pages,
            total_pages=num_target_pages
        )
class ChunkInfo:
    def __init__(self, chunk_index: int, pages: List[int], pdf_bytes: bytes, size_bytes: int):
        self.chunk_index = chunk_index
        self.pages = pages
        self.pdf_bytes = pdf_bytes
        self.size_bytes = size_bytes


def split_pdf_into_chunks(
    input_path: str,
    target_pages: Optional[List[int]] = None,
    max_pages_per_chunk: int = 200,
    max_size_mb: int = 180
) -> List[ChunkInfo]:
    """
    静默将超大或超长 PDF 按 MinerU 平台限制 (<=200页, <=200MB) 自动切分成若干连续子 PDF 分片。
    """
    src_doc = fitz.open(input_path)
    try:
        total_doc_pages = len(src_doc)
        if not target_pages:
            active_pages = list(range(1, total_doc_pages + 1))
        else:
            active_pages = sorted(list(set([p for p in target_pages if 1 <= p <= total_doc_pages])))
            if not active_pages:
                active_pages = list(range(1, total_doc_pages + 1))

        chunks: List[ChunkInfo] = []
        max_bytes = max_size_mb * 1024 * 1024

        # Group pages into slices of at most max_pages_per_chunk
        page_groups = []
        for i in range(0, len(active_pages), max_pages_per_chunk):
            page_groups.append(active_pages[i:i + max_pages_per_chunk])

        chunk_idx = 0
        for group in page_groups:
            # Build sub-pdf
            sub_doc = fitz.open()
            try:
                for p_num in group:
                    sub_doc.insert_pdf(src_doc, from_page=p_num - 1, to_page=p_num - 1)
                sub_bytes = sub_doc.tobytes()

                # If size still exceeds max_bytes, further subdivide
                if len(sub_bytes) > max_bytes and len(group) > 1:
                    mid = len(group) // 2
                    sub_groups = [group[:mid], group[mid:]]
                    for sg in sub_groups:
                        sd = fitz.open()
                        try:
                            for pn in sg:
                                sd.insert_pdf(src_doc, from_page=pn - 1, to_page=pn - 1)
                            sb = sd.tobytes()
                            chunks.append(ChunkInfo(chunk_idx, sg, sb, len(sb)))
                            chunk_idx += 1
                        finally:
                            sd.close()
                else:
                    chunks.append(ChunkInfo(chunk_idx, group, sub_bytes, len(sub_bytes)))
                    chunk_idx += 1
            finally:
                sub_doc.close()

        return chunks
    finally:
        src_doc.close()


def run_mineru_ocr_sync(
    input_path: str,
    markdown_path: Optional[str] = None,
    target_pages: Optional[List[int]] = None,
    api_token: str = "REDACTED_MINERU_TOKEN",
    model_version: str = "vlm",
    language: str = "auto",
    enable_formula: bool = True,
    enable_table: bool = True,
    layout_model: str = "doclayout_yolo",
    oss_accelerate: bool = True,
    progress_callback=None
) -> bool:
    """
    执行 MinerU API v4 结构化 Markdown 解析 (支持海外/全球 OSS 专线传输加速与静默自动分片合并)。
    """
    token_clean = (api_token or "").strip()
    if token_clean.lower().startswith("bearer "):
        token_clean = token_clean[7:].strip()

    headers = {
        "Authorization": f"Bearer {token_clean}",
        "Content-Type": "application/json"
    }

    # 1. 静默自动分片
    if progress_callback:
        progress_callback(0.05, "正在准备文档并检测分片...", phase="preparing", current_page=0, total_pages=len(target_pages or []))

    chunks = split_pdf_into_chunks(input_path, target_pages, max_pages_per_chunk=200, max_size_mb=180)
    total_chunks = len(chunks)
    total_target_pages = sum(len(c.pages) for c in chunks)
    logger.info(f"MinerU: Target document split into {total_chunks} chunk(s), total target pages: {total_target_pages}")

    chunk_markdowns: Dict[int, str] = {}

    for c in chunks:
        chunk_no = c.chunk_index + 1
        chunk_page_count = len(c.pages)
        chunk_size_mb = c.size_bytes / (1024 * 1024)

        # 2. 申请上传预签名 URL 与 Batch ID
        if progress_callback:
            base_p = 0.05 + (0.90 * (c.chunk_index / total_chunks))
            progress_callback(
                base_p,
                f"正在申请 MinerU 解析任务 [分片 {chunk_no}/{total_chunks}]...",
                phase="preparing",
                current_page=c.pages[0],
                total_pages=total_target_pages
            )

        payload = {
            "files": [
                {
                    "name": f"chunk_{chunk_no}.pdf",
                    "data_id": f"chunk_{int(time.time())}_{c.chunk_index}"
                }
            ],
            "model_version": model_version,
            "enable_formula": enable_formula,
            "enable_table": enable_table,
            "layout_model": layout_model
        }
        if language and language != "auto":
            payload["language"] = language

        req_res = requests.post("https://mineru.net/api/v4/file-urls/batch", headers=headers, json=payload, timeout=60)
        if req_res.status_code != 200:
            raise Exception(f"MinerU API 申请上传 URL 失败 ({req_res.status_code}): {req_res.text}")

        res_json = req_res.json()
        if res_json.get("code") != 0 or "data" not in res_json:
            raise Exception(f"MinerU API 错误: {res_json.get('msg', req_res.text)}")

        batch_id = res_json["data"]["batch_id"]
        file_urls = res_json["data"]["file_urls"]
        if not file_urls:
            raise Exception("MinerU API 未返回有效的 file_urls")

        raw_upload_url = file_urls[0]
        # ⚡ 专线传输加速域名替换
        if oss_accelerate and "mineru.oss-cn-shanghai.aliyuncs.com" in raw_upload_url:
            upload_url = raw_upload_url.replace(
                "mineru.oss-cn-shanghai.aliyuncs.com",
                "mineru.oss-accelerate-overseas.aliyuncs.com"
            )
        else:
            upload_url = raw_upload_url

        # 3. 流式上传 PDF 分片至 OSS
        t_upload_start = time.time()
        upload_headers = {"Content-Length": str(c.size_bytes)}

        if progress_callback:
            progress_callback(
                base_p + 0.02,
                f"正在上传文档 [分片 {chunk_no}/{total_chunks}]: 0.0/{chunk_size_mb:.1f} MB (0%)",
                phase="uploading",
                upload_speed_mb_s=0.0,
                upload_progress=0.0,
                current_page=c.pages[0],
                total_pages=total_target_pages
            )

        # PUT Upload (Binary streaming)
        put_res = requests.put(upload_url, data=c.pdf_bytes, headers=upload_headers, timeout=600)
        t_upload_cost = time.time() - t_upload_start
        upload_speed = chunk_size_mb / t_upload_cost if t_upload_cost > 0 else 0.0

        if put_res.status_code not in (200, 201):
            raise Exception(f"MinerU OSS 上传失败 ({put_res.status_code}): {put_res.text}")

        logger.info(f"MinerU Chunk {chunk_no} uploaded successfully in {t_upload_cost:.2f}s ({upload_speed:.2f} MB/s)")

        if progress_callback:
            progress_callback(
                base_p + 0.05,
                f"上传完成 [分片 {chunk_no}/{total_chunks}] • 速率: {upload_speed:.1f} MB/s，等待云端排队解析...",
                phase="processing",
                upload_speed_mb_s=upload_speed,
                upload_progress=1.0,
                current_page=c.pages[0],
                total_pages=total_target_pages
            )

        # 4. 轮询云端解析状态
        poll_url = f"https://mineru.net/api/v4/extract-results/batch/{batch_id}"
        full_zip_url = None
        max_retries = 300  # 300 * 3s = 900s timeout per chunk
        dots = 0

        for attempt in range(max_retries):
            time.sleep(3)
            dots += 1
            try:
                poll_res = requests.get(poll_url, headers=headers, timeout=30)
                if poll_res.status_code != 200:
                    continue
                poll_data = poll_res.json().get("data", {})
            except Exception as e:
                logger.warning(f"MinerU polling warning (attempt {attempt+1}): {e}")
                continue

            extract_results = poll_data.get("extract_result", [])
            if not extract_results:
                continue

            item = extract_results[0]
            state = item.get("state", "pending")
            progress_info = item.get("extract_progress", "")
            prog_label = f" [进度: {progress_info}]" if progress_info else ""

            if state == "pending":
                if progress_callback:
                    progress_callback(
                        base_p + 0.08,
                        f"MinerU 云端任务排队中 [分片 {chunk_no}/{total_chunks}]" + ("." * (dots % 4)),
                        phase="processing",
                        current_page=c.pages[0],
                        total_pages=total_target_pages
                    )
            elif state == "running":
                if progress_callback:
                    progress_callback(
                        base_p + 0.15 + (0.50 * (min(attempt * 3, 200) / 200.0) / total_chunks),
                        f"MinerU VLM 正在深度解析 [分片 {chunk_no}/{total_chunks}]{prog_label}...",
                        phase="processing",
                        current_page=c.pages[0],
                        total_pages=total_target_pages
                    )
            elif state == "done":
                full_zip_url = item.get("full_zip_url")
                break
            elif state == "failed":
                err_msg = item.get("err_msg", "未知错误")
                raise Exception(f"MinerU 云端解析失败: {err_msg}")

        if not full_zip_url:
            raise Exception(f"MinerU 解析超时或未返回 full_zip_url [分片 {chunk_no}]")

        # 5. 专线高速下载 Zip 结果包并解压提取 full.md
        if oss_accelerate and "mineru.oss-cn-shanghai.aliyuncs.com" in full_zip_url:
            zip_download_url = full_zip_url.replace(
                "mineru.oss-cn-shanghai.aliyuncs.com",
                "mineru.oss-accelerate-overseas.aliyuncs.com"
            )
        else:
            zip_download_url = full_zip_url

        if progress_callback:
            progress_callback(
                base_p + 0.80 / total_chunks,
                f"正在下载结果包 [分片 {chunk_no}/{total_chunks}]...",
                phase="downloading",
                current_page=c.pages[-1],
                total_pages=total_target_pages
            )

        zip_resp = requests.get(zip_download_url, timeout=120)
        zip_resp.raise_for_status()

        import io
        import zipfile
        chunk_md_text = ""
        
        # Prepare document images directory (e.g. storage/documents/{doc_id}_images)
        effective_md_target = markdown_path or str(Path(input_path).with_suffix(".md"))
        doc_images_dir = Path(effective_md_target).parent / f"{Path(input_path).stem}_images"
        try:
            doc_images_dir.mkdir(parents=True, exist_ok=True)
        except Exception:
            pass

        with zipfile.ZipFile(io.BytesIO(zip_resp.content)) as zf:
            # 1. Extract all images from zip
            for item in zf.infolist():
                fname = item.filename
                if fname.lower().endswith((".jpg", ".jpeg", ".png", ".webp", ".gif", ".svg")) and not fname.startswith("__MACOSX"):
                    clean_img_name = Path(fname).name
                    try:
                        with zf.open(item) as src_img, open(doc_images_dir / clean_img_name, "wb") as dst_img:
                            dst_img.write(src_img.read())
                    except Exception as e:
                        logger.warning(f"Error extracting image {fname}: {e}")

            # 2. Extract full.md markdown
            md_names = [n for n in zf.namelist() if n.endswith(".md")]
            target_md_name = None
            for n in md_names:
                if "full.md" in n:
                    target_md_name = n
                    break
            if not target_md_name and md_names:
                target_md_name = md_names[0]

            if target_md_name:
                with zf.open(target_md_name) as mf:
                    chunk_md_text = mf.read().decode("utf-8", errors="ignore")

        if not chunk_md_text:
            raise Exception(f"未在 MinerU 结果包中找到 Markdown 内容 [分片 {chunk_no}]")

        chunk_markdowns[c.chunk_index] = chunk_md_text

    # 6. 合并所有分片的 Markdown 并写入目标文件
    if progress_callback:
        progress_callback(0.95, "正在合并 Markdown 结构化文档...", phase="merging", current_page=total_target_pages, total_pages=total_target_pages)

    effective_md_path = markdown_path or str(Path(input_path).with_suffix(".md"))
    
    # 构建最终 Markdown
    if len(chunks) == 1 and not target_pages:
        # 单文件全篇转换，直接写入
        final_md = chunk_markdowns.get(0, "")
    else:
        # 多分片或指定页码转换，按 <!-- Page X --> 格式组织与合并
        existing_pages = {}
        if os.path.exists(effective_md_path):
            try:
                with open(effective_md_path, "r", encoding="utf-8") as f_md:
                    existing_content = f_md.read()
                page_splits = re.split(r'<!--\s*Page\s+(\d+)\s*-->', existing_content, flags=re.IGNORECASE)
                if len(page_splits) > 1:
                    for j in range(1, len(page_splits), 2):
                        try:
                            p_no = int(page_splits[j])
                            p_txt = page_splits[j + 1].strip()
                            existing_pages[p_no] = p_txt
                        except Exception:
                            pass
            except Exception as e:
                logger.warning(f"Error reading existing markdown {effective_md_path}: {e}")

        # 写入各分片内容
        for c in chunks:
            cmd = chunk_markdowns.get(c.chunk_index, "")
            if not cmd:
                continue
            # 若单分片内包含多个逻辑页或单段落，将该分片内容赋给起始页
            start_p = c.pages[0]
            existing_pages[start_p] = cmd

        sorted_pnums = sorted(existing_pages.keys())
        if sorted_pnums:
            md_parts = []
            for p_no in sorted_pnums:
                md_parts.append(f"<!-- Page {p_no} -->\n\n{existing_pages[p_no]}")
            final_md = "\n\n".join(md_parts)
        else:
            final_md = "\n\n".join([chunk_markdowns[c.chunk_index] for c in chunks if c.chunk_index in chunk_markdowns])

    with open(effective_md_path, "w", encoding="utf-8") as f_md:
        f_md.write(final_md)

    logger.info(f"MinerU Markdown saved successfully: {effective_md_path}")

    if progress_callback:
        progress_callback(
            1.0,
            f"MinerU 解析完成！已提取 {total_target_pages} 页高质量 Markdown。",
            phase="completed",
            current_page=total_target_pages,
            total_pages=total_target_pages
        )
    return True


def run_ocr_sync_dispatcher(
    input_path: str,
    ocr_req: OcrRequest,
    progress_callback=None
) -> bool:
    """
    分发 OCR/Markdown 解析任务 (支持 MinerU 与 PaddleOCR-VL 引擎)。
    """
    target_pages = ocr_req.target_pages
    engine = (ocr_req.engine or "mineru").lower().strip()

    if engine == "mineru":
        return run_mineru_ocr_sync(
            input_path=input_path,
            markdown_path=str(Path(input_path).with_suffix(".md")),
            target_pages=target_pages,
            api_token=ocr_req.mineru_token or "REDACTED_MINERU_TOKEN",
            model_version=ocr_req.mineru_model_version or "vlm",
            language=ocr_req.mineru_language or "auto",
            enable_formula=ocr_req.enable_formula,
            enable_table=ocr_req.enable_table,
            layout_model=ocr_req.layout_model or "doclayout_yolo",
            oss_accelerate=ocr_req.oss_accelerate,
            progress_callback=progress_callback
        )
    else:
        return run_paddleocr_vl_ocr_sync(
            input_path=input_path,
            markdown_path=str(Path(input_path).with_suffix(".md")),
            target_pages=target_pages,
            api_token=ocr_req.api_token or "REDACTED_BAIDU_TOKEN",
            api_url=ocr_req.api_url or "https://paddleocr.aistudio-app.com/api/v2/ocr/jobs",
            model_name=ocr_req.model_name or "PaddleOCR-VL-1.6",
            optional_payload={
                "markdownIgnoreLabels": ocr_req.markdown_ignore_labels,
                "useDocOrientationClassify": ocr_req.use_doc_orientation_classify,
                "useDocUnwarping": ocr_req.use_doc_unwarping,
                "useLayoutDetection": ocr_req.use_layout_detection,
                "useChartRecognition": ocr_req.use_chart_recognition,
                "useSealRecognition": ocr_req.use_seal_recognition,
                "useOcrForImageBlock": ocr_req.use_ocr_for_image_block,
                "mergeTables": ocr_req.merge_tables,
                "relevelTitles": ocr_req.relevel_titles,
                "layoutShapeMode": ocr_req.layout_shape_mode,
                "promptLabel": ocr_req.prompt_label,
                "repetitionPenalty": ocr_req.repetition_penalty,
                "temperature": ocr_req.temperature,
                "topP": ocr_req.top_p,
                "minPixels": ocr_req.min_pixels,
                "maxPixels": ocr_req.max_pixels,
                "layoutNms": ocr_req.layout_nms,
                "restructurePages": ocr_req.restructure_pages,
            },
            progress_callback=progress_callback
        )


def ensure_orig_pdf_exists(file_path: Path) -> Path:
    """
    Guarantees a backup copy exists if needed.
    """
    orig_path = file_path.with_suffix(".orig.pdf")
    if not orig_path.exists() and file_path.exists():
        try:
            shutil.copyfile(str(file_path), str(orig_path))
        except Exception:
            pass
    return orig_path


def revert_ocr_sync(
    file_path: str,
    target_pages: Optional[List[int]] = None
) -> bool:
    """
    Clears OCR Markdown for the document or specific pages.
    """
    md_path = Path(file_path).with_suffix(".md")
    if not md_path.exists():
        return True

    if not target_pages:
        try:
            os.remove(str(md_path))
        except OSError:
            pass
        return True

    try:
        with open(str(md_path), "r", encoding="utf-8") as f_md:
            content = f_md.read()
        page_splits = re.split(r'<!--\s*Page\s+(\d+)\s*-->', content, flags=re.IGNORECASE)
        pages_dict = {}
        if len(page_splits) > 1:
            for j in range(1, len(page_splits), 2):
                try:
                    p_no = int(page_splits[j])
                    p_txt = page_splits[j + 1].strip()
                    pages_dict[p_no] = p_txt
                except Exception:
                    pass
        for p in target_pages:
            pages_dict.pop(p, None)

        if not pages_dict:
            try:
                os.remove(str(md_path))
            except OSError:
                pass
        else:
            sorted_pnums = sorted(pages_dict.keys())
            with open(str(md_path), "w", encoding="utf-8") as f_md:
                for idx_p, p_no in enumerate(sorted_pnums):
                    f_md.write(f"<!-- Page {p_no} -->\n\n")
                    f_md.write(pages_dict[p_no])
                    if idx_p < len(sorted_pnums) - 1:
                        f_md.write("\n\n")
        return True
    except Exception as e:
        logger.error(f"Error reverting OCR Markdown: {e}")
        return False


class OcrJobManager:
    """
    Manages asynchronous OCR background jobs and live progress.
    """
    def __init__(self):
        self._jobs: Dict[str, Dict[str, Any]] = {}

    def get_job_status(self, doc_id: str) -> Dict[str, Any]:
        return self._jobs.get(doc_id, {
            "doc_id": doc_id,
            "status": "none",
            "progress": 0.0,
            "current_page": 0,
            "total_pages": 0,
            "message": "",
            "phase": "idle",
            "upload_speed_mb_s": 0.0,
            "upload_progress": 0.0,
            "error": None
        })

    def set_job_status(
        self,
        doc_id: str,
        status: str,
        progress: float = 0.0,
        current_page: int = 0,
        total_pages: int = 0,
        message: str = "",
        phase: str = "processing",
        upload_speed_mb_s: Optional[float] = None,
        upload_progress: Optional[float] = None,
        error: Optional[str] = None
    ):
        self._jobs[doc_id] = {
            "doc_id": doc_id,
            "status": status,
            "progress": progress,
            "current_page": current_page,
            "total_pages": total_pages,
            "message": message,
            "phase": phase,
            "upload_speed_mb_s": upload_speed_mb_s,
            "upload_progress": upload_progress,
            "error": error
        }

    async def run_ocr_task(self, doc_id: str, file_path: Path, ocr_req: OcrRequest, db_session_factory):
        init_total_pages = 1
        try:
            reader = PdfReader(str(file_path))
            init_total_pages = len(reader.pages)
        except Exception:
            pass

        target_count = len(ocr_req.target_pages) if ocr_req.target_pages else init_total_pages
        engine_name = "MinerU VLM" if (ocr_req.engine or "").lower() == "mineru" else "百度 PaddleOCR-VL"

        self.set_job_status(
            doc_id,
            "processing",
            progress=0.05,
            current_page=0,
            total_pages=target_count,
            message=f"已启动 {engine_name} 任务...",
            phase="preparing"
        )

        def progress_cb(
            prog: float,
            msg: str,
            current_page: int = 0,
            total_pages: int = target_count,
            phase: str = "processing",
            upload_speed_mb_s: Optional[float] = None,
            upload_progress: Optional[float] = None
        ):
            self.set_job_status(
                doc_id,
                "processing",
                progress=prog,
                current_page=current_page,
                total_pages=total_pages or target_count,
                message=msg,
                phase=phase,
                upload_speed_mb_s=upload_speed_mb_s,
                upload_progress=upload_progress
            )

        try:
            loop = asyncio.get_running_loop()
            success = await loop.run_in_executor(
                None,
                run_ocr_sync_dispatcher,
                str(file_path),
                ocr_req,
                progress_cb
            )

            if success:
                async with db_session_factory() as db:
                    stmt = select(DocumentModel).where(DocumentModel.id == doc_id)
                    result = await db.execute(stmt)
                    doc = result.scalar_one_or_none()
                    if doc:
                        doc.ocr_status = "completed"
                        await db.commit()

                self.set_job_status(
                    doc_id,
                    "completed",
                    progress=1.0,
                    current_page=target_count,
                    total_pages=target_count,
                    message=f"{engine_name} 解析完成！Markdown 文档已就绪。",
                    phase="completed"
                )
            else:
                raise Exception(f"{engine_name} 未能生成 Markdown 结果")

        except Exception as e:
            logger.error(f"OCR task failed for {doc_id}: {e}", exc_info=True)
            self.set_job_status(
                doc_id,
                "failed",
                progress=0.0,
                current_page=0,
                total_pages=target_count,
                message="Markdown 转换失败",
                phase="idle",
                error=str(e)
            )
            async with db_session_factory() as db:
                stmt = select(DocumentModel).where(DocumentModel.id == doc_id)
                result = await db.execute(stmt)
                doc = result.scalar_one_or_none()
                if doc:
                    doc.ocr_status = "failed"
                    await db.commit()


ocr_job_manager = OcrJobManager()


