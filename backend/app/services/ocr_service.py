import asyncio
import hashlib
import io
import json
import logging
import os
import shutil
import time
from pathlib import Path
from typing import Dict, Any, Optional, List
import aiofiles
import fitz
import requests
from pypdf import PdfReader, PdfWriter
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.cidfonts import UnicodeCIDFont
from sqlalchemy import select

from app.models import DocumentModel, OcrRequest

logger = logging.getLogger("ocr_service")

# Try importing Adobe PDF Services SDK
try:
    from adobe.pdfservices.operation.auth.service_principal_credentials import ServicePrincipalCredentials
    from adobe.pdfservices.operation.pdf_services import PDFServices
    from adobe.pdfservices.operation.pdf_services_media_type import PDFServicesMediaType
    from adobe.pdfservices.operation.pdfjobs.jobs.ocr_pdf_job import OCRPDFJob
    from adobe.pdfservices.operation.pdfjobs.params.ocr_pdf.ocr_params import OCRParams
    from adobe.pdfservices.operation.pdfjobs.params.ocr_pdf.ocr_supported_locale import OCRSupportedLocale
    from adobe.pdfservices.operation.pdfjobs.params.ocr_pdf.ocr_supported_type import OCRSupportedType
    from adobe.pdfservices.operation.pdfjobs.result.ocr_pdf_result import OCRPDFResult
    ADOBE_SDK_AVAILABLE = True
except Exception as e:
    logger.warning(f"Adobe PDF Services SDK not loaded: {e}")
    ADOBE_SDK_AVAILABLE = False

# Register standard Adobe CJK Unicode CID font for invisible text layer
try:
    pdfmetrics.registerFont(UnicodeCIDFont('STSong-Light'))
except Exception as e:
    logger.warning(f"Error registering STSong-Light font: {e}")


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


def run_paddleocr_vl_ocr_sync(
    input_path: str,
    output_md_path: str,
    target_pages: Optional[List[int]] = None,
    api_token: str = "REDACTED_BAIDU_TOKEN",
    api_url: str = "https://paddleocr.aistudio-app.com/api/v2/ocr/jobs",
    model_name: str = "PaddleOCR-VL-1.6",
    optional_payload: Optional[Dict[str, Any]] = None,
    progress_callback=None
) -> bool:
    """
    Online Multi-modal OCR using Baidu AI Studio PaddleOCR-VL-1.6 API.
    Parses and saves the structured Markdown (.md) document with formulas, tables, and layouts.
    Supports full document or selective page range OCR.
    """
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
    is_partial = (num_target_pages < total_doc_pages)
    
    if progress_callback:
        progress_callback(
            0.05,
            f"正在准备百度 PaddleOCR-VL API 任务 (目标 {num_target_pages} 页)...",
            current_page=0,
            total_pages=num_target_pages
        )

    # 1. Build sub-PDF containing only target pages
    sub_doc = fitz.open()
    for p_num in active_pages:
        sub_doc.insert_pdf(src_doc, from_page=p_num - 1, to_page=p_num - 1)
    sub_pdf_bytes = sub_doc.tobytes()
    sub_doc.close()
    src_doc.close()

    # 2. Submit Job to PaddleOCR-VL API
    headers = {"Authorization": f"bearer {api_token.strip()}"}
    payload_opts = optional_payload or {
        "useDocOrientationClassify": False,
        "useDocUnwarping": False,
        "useChartRecognition": False,
    }
    
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

    job_res = requests.post(api_url, headers=headers, data=data, files=files, timeout=60)
    if job_res.status_code != 200:
        raise Exception(f"PaddleOCR API 提交失败 ({job_res.status_code}): {job_res.text}")
    
    job_data = job_res.json()
    if job_data.get("code") != 0 or "data" not in job_data:
        raise Exception(f"PaddleOCR API 错误: {job_data.get('msg', job_res.text)}")
        
    job_id = job_data["data"]["jobId"]
    logger.info(f"PaddleOCR-VL Job submitted successfully: jobId={job_id}")

    # 3. Poll for results
    jsonl_url = None
    max_retries = 150  # 150 * 2s = 300s timeout
    for attempt in range(max_retries):
        time.sleep(2)
        poll_res = requests.get(f"{api_url}/{job_id}", headers=headers, timeout=30)
        if poll_res.status_code != 200:
            continue
            
        poll_data = poll_res.json().get("data", {})
        state = poll_data.get("state", "pending")
        
        extracted_p = 0
        total_p = num_target_pages
        if "extractProgress" in poll_data:
            extracted_p = poll_data["extractProgress"].get("extractedPages", 0)
            total_p = poll_data["extractProgress"].get("totalPages", num_target_pages)

        if state == "pending":
            if progress_callback:
                progress_callback(
                    0.25,
                    "PaddleOCR-VL 云端任务排队中...",
                    current_page=0,
                    total_pages=num_target_pages
                )
        elif state == "running":
            prog = 0.25 + 0.65 * (extracted_p / max(total_p, 1))
            if progress_callback:
                progress_callback(
                    prog,
                    f"PaddleOCR-VL 正在多模态解析第 {extracted_p}/{total_p} 页...",
                    current_page=extracted_p,
                    total_pages=num_target_pages
                )
        elif state == "done":
            if progress_callback:
                progress_callback(
                    0.92,
                    "PaddleOCR-VL 识别完成，正在解析并提取 Markdown 文档...",
                    current_page=num_target_pages,
                    total_pages=num_target_pages
                )
            jsonl_url = poll_data.get("resultUrl", {}).get("jsonUrl")
            break
        elif state == "failed":
            error_msg = poll_data.get("errorMsg", "Unknown error")
            raise Exception(f"PaddleOCR-VL 任务失败: {error_msg}")

    if not jsonl_url:
        raise Exception("PaddleOCR-VL 识别超时或未获取到结果数据 URL")

    # 4. Download and Parse JSON/JSONL
    jsonl_resp = requests.get(jsonl_url, timeout=30)
    jsonl_resp.raise_for_status()
    jsonl_text = jsonl_resp.text.strip()
    
    page_markdown_texts: List[str] = []
    try:
        data_obj = json.loads(jsonl_text)
        if isinstance(data_obj, dict) and "result" in data_obj and "layoutParsingResults" in data_obj["result"]:
            for item in data_obj["result"]["layoutParsingResults"]:
                md_t = item.get("markdown", {}).get("text", "")
                if not md_t and "prunedResult" in item:
                    blocks = item["prunedResult"].get("parsing_res_list", [])
                    md_t = "\n\n".join([b.get("block_content", "") for b in blocks if b.get("block_content")])
                page_markdown_texts.append(md_t)
        elif isinstance(data_obj, list):
            for item in data_obj:
                md_t = item.get("markdown", {}).get("text", "")
                page_markdown_texts.append(md_t)
    except Exception:
        for line in jsonl_text.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                line_obj = json.loads(line)
                if isinstance(line_obj, dict) and "result" in line_obj and "layoutParsingResults" in line_obj["result"]:
                    for item in line_obj["result"]["layoutParsingResults"]:
                        md_t = item.get("markdown", {}).get("text", "")
                        page_markdown_texts.append(md_t)
                elif isinstance(line_obj, dict) and "markdown" in line_obj:
                    page_markdown_texts.append(line_obj["markdown"].get("text", ""))
            except Exception:
                pass

    if not page_markdown_texts:
        raise Exception("未从 PaddleOCR-VL 响应中解析出有效的 Markdown 内容")

    # 5. Build and save the Markdown file
    new_page_map = {}
    for i, p_num in enumerate(active_pages):
        if i < len(page_markdown_texts):
            new_page_map[p_num] = page_markdown_texts[i].strip()

    md_sections = []
    for p_num in range(1, total_doc_pages + 1):
        if p_num in new_page_map:
            content = new_page_map[p_num]
            if content:
                md_sections.append(f"<!-- Page {p_num} -->\n{content}")
        elif not is_partial:
            if p_num <= len(page_markdown_texts):
                md_sections.append(f"<!-- Page {p_num} -->\n{page_markdown_texts[p_num - 1].strip()}")

    if not md_sections:
        md_sections = [f"<!-- Page {i+1} -->\n{t.strip()}" for i, t in enumerate(page_markdown_texts) if t.strip()]

    combined_md = "\n\n---\n\n".join(md_sections)

    with open(output_md_path, "w", encoding="utf-8") as f_out:
        f_out.write(combined_md)

    if progress_callback:
        progress_callback(
            1.0,
            f"百度 PaddleOCR-VL Markdown 提取成功！已生成 {len(page_markdown_texts)} 页结构化文档。",
            current_page=num_target_pages,
            total_pages=num_target_pages
        )
    return True


def run_rapidocr_sync(
    input_path: str,
    output_path: str,
    target_pages: Optional[List[int]] = None,
    languages: str = "chi_sim+eng+equ",
    progress_callback=None
) -> bool:
    """
    Local Offline RapidOCR (ONNX) pipeline.
    Supports full document or selective page range OCR with exact bounding box alignment.
    """
    from rapidocr_onnxruntime import RapidOCR
    engine = RapidOCR()

    src_doc = fitz.open(input_path)
    total_doc_pages = len(src_doc)

    if not target_pages:
        active_pages = list(range(1, total_doc_pages + 1))
    else:
        active_pages = sorted(list(set([p for p in target_pages if 1 <= p <= total_doc_pages])))
        if not active_pages:
            active_pages = list(range(1, total_doc_pages + 1))

    num_target_pages = len(active_pages)
    raw_pdf_bytes = src_doc.tobytes()

    if progress_callback:
        progress_callback(
            0.05,
            f"正在启动本地 RapidOCR 引擎 (目标 {num_target_pages} 页)...",
            current_page=0,
            total_pages=num_target_pages
        )

    out_writer = PdfWriter()
    src_reader = PdfReader(io.BytesIO(raw_pdf_bytes))

    for idx, orig_page in enumerate(src_reader.pages):
        page_num = idx + 1
        
        if page_num in active_pages:
            curr_target_idx = active_pages.index(page_num) + 1
            prog = 0.1 + 0.85 * (curr_target_idx / max(num_target_pages, 1))
            if progress_callback:
                progress_callback(
                    prog,
                    f"正在识别第 {page_num} 页 (共目标 {num_target_pages} 页)...",
                    current_page=curr_target_idx,
                    total_pages=num_target_pages
                )

            fitz_page = src_doc[idx]
            page_w = fitz_page.rect.width
            page_h = fitz_page.rect.height

            # High-res rendering for accurate OCR
            pix = fitz_page.get_pixmap(dpi=200)
            img_bytes = pix.tobytes("png")

            scale_x = page_w / max(pix.width, 1)
            scale_y = page_h / max(pix.height, 1)

            ocr_res, _ = engine(img_bytes)

            packet = io.BytesIO()
            can = canvas.Canvas(packet, pagesize=(page_w, page_h))

            if ocr_res:
                for item in ocr_res:
                    box, text, score = item
                    if not text or not text.strip():
                        continue

                    pts_x = [pt[0] * scale_x for pt in box]
                    pts_y = [pt[1] * scale_y for pt in box]
                    x_min = min(pts_x)
                    y_min = min(pts_y)
                    x_max = max(pts_x)
                    y_max = max(pts_y)

                    box_w = max(1.0, x_max - x_min)
                    box_h = max(6.0, y_max - y_min)
                    pdf_y = page_h - y_max

                    font_size = max(5.0, min(box_h * 0.82, 28.0))
                    t = can.beginText(x_min, pdf_y + (box_h - font_size) * 0.4)
                    t.setFont('STSong-Light', font_size)
                    t.setTextRenderMode(3)

                    calc_w = can.stringWidth(text, 'STSong-Light', font_size)
                    if calc_w > 0 and len(text) > 1 and box_w > calc_w:
                        extra_space = min((box_w - calc_w) / (len(text) - 1), font_size * 0.4)
                        t.setCharSpace(extra_space)
                    elif calc_w > box_w and box_w > 10:
                        adj_font_size = max(5.0, font_size * (box_w / calc_w))
                        t.setFont('STSong-Light', adj_font_size)

                    t.textOut(text)
                    can.drawText(t)

            can.save()
            packet.seek(0)

            overlay_reader = PdfReader(packet)

            # Rasterize page background to high-res image to completely eliminate old text layer on this page
            clean_doc = fitz.open()
            clean_page = clean_doc.new_page(width=page_w, height=page_h)
            clean_page.insert_image(fitz.Rect(0, 0, page_w, page_h), stream=img_bytes)
            clean_bytes = clean_doc.tobytes()
            clean_doc.close()

            clean_reader = PdfReader(io.BytesIO(clean_bytes))
            clean_p = clean_reader.pages[0]
            if len(overlay_reader.pages) > 0:
                clean_p.merge_page(overlay_reader.pages[0])
            out_writer.add_page(clean_p)
        else:
            out_writer.add_page(orig_page)

    src_doc.close()

    with open(output_path, "wb") as f_out:
        out_writer.write(f_out)

    if progress_callback:
        progress_callback(
            1.0,
            f"本地 RapidOCR 处理完成！已合并 {num_target_pages} 页可检索文本层。",
            current_page=num_target_pages,
            total_pages=num_target_pages
        )
    return True


def get_adobe_credentials(client_id: Optional[str] = None, client_secret: Optional[str] = None) -> tuple[str, str]:
    """
    Retrieves Adobe Client ID and Secret.
    Priority:
    1. Explicit arguments
    2. pdfservices-api-credentials.json in workspace root or backend dir
    3. Default credentials
    """
    if client_id and client_id.strip() and client_secret and client_secret.strip():
        return client_id.strip(), client_secret.strip()

    search_paths = [
        Path("pdfservices-api-credentials.json"),
        Path("../pdfservices-api-credentials.json"),
        Path(os.getcwd()) / "pdfservices-api-credentials.json",
        Path(os.getcwd()).parent / "pdfservices-api-credentials.json",
        Path(__file__).resolve().parent.parent.parent.parent / "pdfservices-api-credentials.json",
    ]
    for p in search_paths:
        if p.exists():
            try:
                with open(p, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    cid = data.get("client_credentials", {}).get("client_id")
                    csec = data.get("client_credentials", {}).get("client_secret")
                    if cid and csec:
                        return cid.strip(), csec.strip()
            except Exception:
                pass
    return "REDACTED_ADOBE_CLIENT_ID", "REDACTED_ADOBE_CLIENT_SECRET"


def map_adobe_locale(locale_str: str):
    """
    Maps string locale identifier to Adobe OCRSupportedLocale enum.
    """
    if not ADOBE_SDK_AVAILABLE:
        return None
    normalized = (locale_str or "zh-CN").strip()
    locale_map = {
        "zh-CN": OCRSupportedLocale.ZH_CN,
        "zh_cn": OCRSupportedLocale.ZH_CN,
        "zh-cn": OCRSupportedLocale.ZH_CN,
        "chi_sim": OCRSupportedLocale.ZH_CN,
        "chinese": OCRSupportedLocale.ZH_CN,
        "en-US": OCRSupportedLocale.EN_US,
        "en_us": OCRSupportedLocale.EN_US,
        "en-us": OCRSupportedLocale.EN_US,
        "eng": OCRSupportedLocale.EN_US,
        "english": OCRSupportedLocale.EN_US,
        "zh-HK": OCRSupportedLocale.ZH_HK,
        "zh_hk": OCRSupportedLocale.ZH_HK,
        "zh-hk": OCRSupportedLocale.ZH_HK,
        "ja-JP": OCRSupportedLocale.JA_JP,
        "ja_jp": OCRSupportedLocale.JA_JP,
        "ja-jp": OCRSupportedLocale.JA_JP,
        "ko-KR": OCRSupportedLocale.KO_KR,
        "ko_kr": OCRSupportedLocale.KO_KR,
        "de-DE": OCRSupportedLocale.DE_DE,
        "de_de": OCRSupportedLocale.DE_DE,
        "fr-FR": OCRSupportedLocale.FR_FR,
        "fr_fr": OCRSupportedLocale.FR_FR,
        "es-ES": OCRSupportedLocale.ES_ES,
        "es_es": OCRSupportedLocale.ES_ES,
        "ru-RU": OCRSupportedLocale.RU_RU,
        "ru_ru": OCRSupportedLocale.RU_RU,
        "it-IT": OCRSupportedLocale.IT_IT,
        "pt-BR": OCRSupportedLocale.PT_BR,
    }
    return locale_map.get(normalized, OCRSupportedLocale.ZH_CN)


def map_adobe_type(type_str: str):
    """
    Maps string OCR type identifier to Adobe OCRSupportedType enum.
    """
    if not ADOBE_SDK_AVAILABLE:
        return None
    normalized = (type_str or "searchable_image_exact").lower().strip()
    if normalized == "searchable_image":
        return OCRSupportedType.SEARCHABLE_IMAGE
    return OCRSupportedType.SEARCHABLE_IMAGE_EXACT


def run_adobe_ocr_sync(
    input_path: str,
    output_path: str,
    target_pages: Optional[List[int]] = None,
    client_id: Optional[str] = None,
    client_secret: Optional[str] = None,
    locale: str = "zh-CN",
    ocr_type: str = "searchable_image_exact",
    progress_callback=None
) -> bool:
    """
    Executes Adobe PDF Services OCR, outputting a high-fidelity dual-layer searchable PDF.
    Supports full document or selective page range OCR.
    """
    if not ADOBE_SDK_AVAILABLE:
        raise RuntimeError("Adobe PDF Services SDK 未正确安装或导入失败。")

    resolved_cid, resolved_csec = get_adobe_credentials(client_id, client_secret)
    if not resolved_cid or not resolved_csec:
        raise ValueError("缺少 Adobe PDF Services 凭据 (Client ID / Client Secret)。")

    src_doc = fitz.open(input_path)
    total_doc_pages = len(src_doc)

    if not target_pages:
        active_pages = list(range(1, total_doc_pages + 1))
    else:
        active_pages = sorted(list(set([p for p in target_pages if 1 <= p <= total_doc_pages])))
        if not active_pages:
            active_pages = list(range(1, total_doc_pages + 1))

    num_target_pages = len(active_pages)
    is_partial_pages = (num_target_pages < total_doc_pages)

    if progress_callback:
        progress_callback(
            0.10,
            f"正在初始化 Adobe PDF Services 引擎 (目标 {num_target_pages}/{total_doc_pages} 页)...",
            current_page=0,
            total_pages=num_target_pages
        )

    # If partial pages, extract target pages to a sub-PDF
    if is_partial_pages:
        sub_doc = fitz.open()
        for p_num in active_pages:
            sub_doc.insert_pdf(src_doc, from_page=p_num - 1, to_page=p_num - 1)
        pdf_bytes_to_send = sub_doc.tobytes()
        sub_doc.close()
    else:
        with open(input_path, "rb") as f_in:
            pdf_bytes_to_send = f_in.read()

    # Initialize Adobe SDK
    credentials = ServicePrincipalCredentials(client_id=resolved_cid, client_secret=resolved_csec)
    pdf_services = PDFServices(credentials=credentials)

    if progress_callback:
        progress_callback(
            0.25,
            f"正在上传文档至 Adobe 云端处理中心 ({max(1, len(pdf_bytes_to_send) // 1024)} KB)...",
            current_page=0,
            total_pages=num_target_pages
        )

    input_stream = io.BytesIO(pdf_bytes_to_send)
    input_asset = pdf_services.upload(
        input_stream=input_stream,
        mime_type=PDFServicesMediaType.PDF.value
    )

    if progress_callback:
        progress_callback(
            0.45,
            f"Adobe 官方引擎正在进行高保真双层 PDF 转换 (语言: {locale})...",
            current_page=0,
            total_pages=num_target_pages
        )

    adobe_locale_enum = map_adobe_locale(locale)
    adobe_type_enum = map_adobe_type(ocr_type)
    ocr_params = OCRParams(ocr_locale=adobe_locale_enum, ocr_type=adobe_type_enum)
    ocr_job = OCRPDFJob(input_asset=input_asset, ocr_pdf_params=ocr_params)

    location = pdf_services.submit(ocr_job)
    logger.info(f"Adobe OCR Job submitted successfully: polling_url={location}")

    if progress_callback:
        progress_callback(
            0.65,
            "Adobe 云端任务执行中，正在等待检索层生成...",
            current_page=0,
            total_pages=num_target_pages
        )

    response = pdf_services.get_job_result(location, OCRPDFResult)
    status = response.get_status()
    if status != "done":
        raise Exception(f"Adobe OCR 任务未成功完成，返回状态: {status}")

    if progress_callback:
        progress_callback(
            0.85,
            "Adobe OCR 处理完成，正在下载并合并双层 PDF 页面...",
            current_page=num_target_pages,
            total_pages=num_target_pages
        )

    result_asset = response.get_result().get_asset()
    stream_asset = pdf_services.get_content(result_asset)
    out_stream = stream_asset.get_input_stream()
    if hasattr(out_stream, "read"):
        result_pdf_bytes = out_stream.read()
    else:
        result_pdf_bytes = out_stream

    if is_partial_pages:
        # Merge processed pages back into the original document
        ocr_sub_doc = fitz.open(stream=result_pdf_bytes, filetype="pdf")
        merged_doc = fitz.open()

        ocr_page_idx = 0
        for page_idx in range(total_doc_pages):
            curr_p = page_idx + 1
            if curr_p in active_pages:
                merged_doc.insert_pdf(ocr_sub_doc, from_page=ocr_page_idx, to_page=ocr_page_idx)
                ocr_page_idx += 1
            else:
                merged_doc.insert_pdf(src_doc, from_page=page_idx, to_page=page_idx)

        merged_doc.save(output_path)
        merged_doc.close()
        ocr_sub_doc.close()
    else:
        with open(output_path, "wb") as f_out:
            f_out.write(result_pdf_bytes)

    src_doc.close()

    if progress_callback:
        progress_callback(
            1.0,
            f"Adobe OCR 转换完成！已成功构建 {num_target_pages} 页官方高保真双层可检索 PDF。",
            current_page=num_target_pages,
            total_pages=num_target_pages
        )
    return True


def run_ocr_sync_dispatcher(
    input_path: str,
    output_path: str,
    ocr_req: OcrRequest,
    progress_callback=None
) -> bool:
    """
    Dispatches OCR execution to selected engine (Adobe PDF Services, PaddleOCR-VL Online API, or Local RapidOCR).
    """
    engine = (ocr_req.engine or "adobe").lower()
    target_pages = ocr_req.target_pages

    if engine == "adobe" or engine == "adobe_ocr" or engine == "pdfservices":
        return run_adobe_ocr_sync(
            input_path=input_path,
            output_path=output_path,
            target_pages=target_pages,
            client_id=ocr_req.adobe_client_id,
            client_secret=ocr_req.adobe_client_secret,
            locale=ocr_req.adobe_locale or "zh-CN",
            ocr_type=ocr_req.adobe_type or "searchable_image_exact",
            progress_callback=progress_callback
        )
    elif engine == "paddleocr_vl" or engine == "paddleocr" or engine == "online_api":
        md_output_path = str(Path(input_path).with_suffix(".md"))
        return run_paddleocr_vl_ocr_sync(
            input_path=input_path,
            output_md_path=md_output_path,
            target_pages=target_pages,
            api_token=ocr_req.api_token or "REDACTED_BAIDU_TOKEN",
            api_url=ocr_req.api_url or "https://paddleocr.aistudio-app.com/api/v2/ocr/jobs",
            model_name=ocr_req.model_name or "PaddleOCR-VL-1.6",
            optional_payload={
                "useDocOrientationClassify": ocr_req.use_doc_orientation_classify,
                "useDocUnwarping": ocr_req.use_doc_unwarping,
                "useChartRecognition": ocr_req.use_chart_recognition,
            },
            progress_callback=progress_callback
        )
    else:
        return run_rapidocr_sync(
            input_path=input_path,
            output_path=output_path,
            target_pages=target_pages,
            languages=ocr_req.languages,
            progress_callback=progress_callback
        )


def ensure_orig_pdf_exists(file_path: Path) -> Path:
    """
    Guarantees a pristine copy of the original uploaded PDF (.orig.pdf) exists.
    """
    orig_path = file_path.with_suffix(".orig.pdf")
    if not orig_path.exists() and file_path.exists():
        shutil.copyfile(str(file_path), str(orig_path))
    return orig_path


def revert_ocr_sync(
    active_path: str,
    orig_path: str,
    target_pages: Optional[List[int]] = None
) -> bool:
    """
    Reverts OCR on target_pages by restoring them from orig_path into active_path.
    If target_pages is None or empty, restores all pages.
    """
    if not os.path.exists(orig_path):
        raise FileNotFoundError(f"Original pristine PDF not found at {orig_path}")

    orig_reader = PdfReader(orig_path)
    total_pages = len(orig_reader.pages)

    if not target_pages:
        shutil.copyfile(orig_path, active_path)
        return True

    active_pages_set = set([p for p in target_pages if 1 <= p <= total_pages])
    if len(active_pages_set) == total_pages or len(active_pages_set) == 0:
        shutil.copyfile(orig_path, active_path)
        return True

    active_reader = PdfReader(active_path)
    out_writer = PdfWriter()

    for idx in range(total_pages):
        page_num = idx + 1
        if page_num in active_pages_set:
            out_writer.add_page(orig_reader.pages[idx])
        else:
            if idx < len(active_reader.pages):
                out_writer.add_page(active_reader.pages[idx])
            else:
                out_writer.add_page(orig_reader.pages[idx])

    temp_path = active_path + ".revert.tmp.pdf"
    with open(temp_path, "wb") as f_out:
        out_writer.write(f_out)

    if os.path.exists(active_path):
        os.remove(active_path)
    shutil.move(temp_path, active_path)
    return True


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
        error: Optional[str] = None
    ):
        self._jobs[doc_id] = {
            "doc_id": doc_id,
            "status": status,
            "progress": progress,
            "current_page": current_page,
            "total_pages": total_pages,
            "message": message,
            "error": error
        }

    async def run_ocr_task(self, doc_id: str, file_path: Path, ocr_req: OcrRequest, db_session_factory):
        init_total_pages = 1
        try:
            reader = PdfReader(str(file_path))
            init_total_pages = len(reader.pages)
        except Exception:
            pass

        # Guarantee pristine backup copy exists before any OCR modification
        ensure_orig_pdf_exists(file_path)

        target_count = len(ocr_req.target_pages) if ocr_req.target_pages else init_total_pages

        self.set_job_status(
            doc_id,
            "processing",
            progress=0.05,
            current_page=0,
            total_pages=target_count,
            message="已启动 OCR 任务..."
        )

        temp_output_path = file_path.with_suffix(".ocr.tmp.pdf")

        def progress_cb(prog: float, msg: str, current_page: int = 0, total_pages: int = target_count):
            self.set_job_status(
                doc_id,
                "processing",
                progress=prog,
                current_page=current_page,
                total_pages=total_pages or target_count,
                message=msg
            )

        try:
            loop = asyncio.get_running_loop()
            success = await loop.run_in_executor(
                None,
                run_ocr_sync_dispatcher,
                str(file_path),
                str(temp_output_path),
                ocr_req,
                progress_cb
            )

            if success:
                is_md_engine = ("paddle" in (ocr_req.engine or "").lower())
                md_path = file_path.with_suffix(".md")

                if is_md_engine and md_path.exists():
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
                        message="百度 PaddleOCR-VL Markdown 解析成功！可在阅读界面切换至 MD 视图浏览。"
                    )
                elif temp_output_path.exists():
                    # Atomically replace original file with the new dual-layer PDF
                    if file_path.exists():
                        os.remove(file_path)
                    shutil.move(str(temp_output_path), str(file_path))

                    # Compute new checksum and file size
                    sha256_hash = hashlib.sha256()
                    total_size = 0
                    async with aiofiles.open(file_path, "rb") as f:
                        while chunk := await f.read(65536):
                            total_size += len(chunk)
                            sha256_hash.update(chunk)
                    checksum = sha256_hash.hexdigest()

                    # Update database
                    async with db_session_factory() as db:
                        stmt = select(DocumentModel).where(DocumentModel.id == doc_id)
                        result = await db.execute(stmt)
                        doc = result.scalar_one_or_none()
                        if doc:
                            doc.has_text_layer = 1
                            doc.ocr_status = "completed"
                            doc.file_size = total_size
                            doc.checksum = checksum
                            await db.commit()

                    self.set_job_status(
                        doc_id,
                        "completed",
                        progress=1.0,
                        current_page=target_count,
                        total_pages=target_count,
                        message="双层可检索 PDF 转换成功！已支持划词高亮。"
                    )
                else:
                    raise Exception("OCR 输出文件生成失败")

        except Exception as e:
            logger.error(f"OCR task failed for {doc_id}: {e}", exc_info=True)
            self.set_job_status(
                doc_id,
                "failed",
                progress=0.0,
                current_page=0,
                total_pages=target_count,
                message="OCR 转换失败",
                error=str(e)
            )
            if temp_output_path.exists():
                try:
                    os.remove(temp_output_path)
                except OSError:
                    pass
            # Update DB status
            async with db_session_factory() as db:
                stmt = select(DocumentModel).where(DocumentModel.id == doc_id)
                result = await db.execute(stmt)
                doc = result.scalar_one_or_none()
                if doc:
                    doc.ocr_status = "failed"
                    await db.commit()


ocr_job_manager = OcrJobManager()

