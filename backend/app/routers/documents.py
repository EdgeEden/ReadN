import asyncio
import hashlib
import os
import re
import uuid
from typing import List
import aiofiles
from fastapi import APIRouter, Depends, File, HTTPException, Request, Response, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from pypdf import PdfReader

from app.config import STORAGE_DIR, DEFAULT_CHUNK_SIZE
from app.database import get_db, AsyncSessionLocal
from app.models import (
    DocumentModel,
    DocumentResponse,
    DocumentUpdate,
    AnnotationModel,
    OcrRequest,
    OcrStatusResponse,
    OcrRevertRequest,
    MarkdownResponse,
    MarkdownUpdateRequest,
)
from app.services.ocr_service import detect_text_layer, ocr_job_manager, ensure_orig_pdf_exists, revert_ocr_sync

router = APIRouter(prefix="/api/documents", tags=["documents"])


@router.post("/upload", response_model=DocumentResponse, status_code=status.HTTP_201_CREATED)
async def upload_document(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db)
):
    if not file.filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Only PDF files are supported.")
    
    doc_id = str(uuid.uuid4())
    save_filename = f"{doc_id}.pdf"
    file_path = STORAGE_DIR / save_filename
    
    # Stream upload to disk to maintain low memory usage
    sha256_hash = hashlib.sha256()
    total_size = 0
    
    async with aiofiles.open(file_path, "wb") as out_file:
        while content := await file.read(DEFAULT_CHUNK_SIZE):
            total_size += len(content)
            sha256_hash.update(content)
            await out_file.write(content)
            
    checksum = sha256_hash.hexdigest()
    ensure_orig_pdf_exists(file_path)
    
    # Extract page count and detect if document has text layer
    page_count = 0
    try:
        reader = PdfReader(str(file_path))
        page_count = len(reader.pages)
    except Exception:
        page_count = 1

    has_text = detect_text_layer(str(file_path))
    clean_title = re.sub(r"\.pdf$", "", file.filename, flags=re.IGNORECASE)

    db_doc = DocumentModel(
        id=doc_id,
        filename=file.filename,
        title=clean_title,
        file_size=total_size,
        page_count=page_count,
        has_text_layer=1 if has_text else 0,
        ocr_status="none",
        checksum=checksum
    )
    db.add(db_doc)
    await db.commit()
    await db.refresh(db_doc)

    return DocumentResponse(
        id=db_doc.id,
        filename=db_doc.filename,
        title=db_doc.title,
        file_size=db_doc.file_size,
        page_count=db_doc.page_count,
        has_text_layer=bool(db_doc.has_text_layer),
        has_markdown=(STORAGE_DIR / f"{db_doc.id}.md").exists(),
        ocr_status=db_doc.ocr_status,
        checksum=db_doc.checksum,
        created_at=db_doc.created_at,
        updated_at=db_doc.updated_at,
        annotation_count=0
    )


@router.get("", response_model=List[DocumentResponse])
async def list_documents(db: AsyncSession = Depends(get_db)):
    stmt = (
        select(
            DocumentModel,
            func.count(AnnotationModel.id).label("annotation_count")
        )
        .outerjoin(AnnotationModel, DocumentModel.id == AnnotationModel.doc_id)
        .group_by(DocumentModel.id)
        .order_by(DocumentModel.updated_at.desc())
    )
    result = await db.execute(stmt)
    rows = result.all()
    
    response = []
    for doc, count in rows:
        response.append(
            DocumentResponse(
                id=doc.id,
                filename=doc.filename,
                title=doc.title,
                file_size=doc.file_size,
                page_count=doc.page_count,
                has_text_layer=bool(doc.has_text_layer),
                has_markdown=(STORAGE_DIR / f"{doc.id}.md").exists(),
                ocr_status=doc.ocr_status,
                checksum=doc.checksum,
                created_at=doc.created_at,
                updated_at=doc.updated_at,
                annotation_count=count
            )
        )
    return response


@router.get("/{doc_id}", response_model=DocumentResponse)
async def get_document(doc_id: str, db: AsyncSession = Depends(get_db)):
    stmt = (
        select(
            DocumentModel,
            func.count(AnnotationModel.id).label("annotation_count")
        )
        .outerjoin(AnnotationModel, DocumentModel.id == AnnotationModel.doc_id)
        .where(DocumentModel.id == doc_id)
        .group_by(DocumentModel.id)
    )
    result = await db.execute(stmt)
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="Document not found")
    
    doc, count = row
    return DocumentResponse(
        id=doc.id,
        filename=doc.filename,
        title=doc.title,
        file_size=doc.file_size,
        page_count=doc.page_count,
        has_text_layer=bool(doc.has_text_layer),
        has_markdown=(STORAGE_DIR / f"{doc.id}.md").exists(),
        ocr_status=doc.ocr_status,
        checksum=doc.checksum,
        created_at=doc.created_at,
        updated_at=doc.updated_at,
        annotation_count=count
    )


@router.patch("/{doc_id}", response_model=DocumentResponse)
async def update_document(
    doc_id: str,
    update_data: DocumentUpdate,
    db: AsyncSession = Depends(get_db)
):
    stmt = select(DocumentModel).where(DocumentModel.id == doc_id)
    result = await db.execute(stmt)
    doc = result.scalar_one_or_none()
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")
    
    if update_data.title is not None:
        doc.title = update_data.title.strip()
    
    await db.commit()
    await db.refresh(doc)
    return await get_document(doc_id, db)


@router.delete("/{doc_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_document(doc_id: str, db: AsyncSession = Depends(get_db)):
    stmt = select(DocumentModel).where(DocumentModel.id == doc_id)
    result = await db.execute(stmt)
    doc = result.scalar_one_or_none()
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")
    
    # Remove physical files
    for suffix in [".pdf", ".orig.pdf", ".ocr.tmp.pdf", ".revert.tmp.pdf", ".md"]:
        p = STORAGE_DIR / f"{doc.id}{suffix}"
        if p.exists():
            try:
                os.remove(p)
            except OSError:
                pass
            
    await db.delete(doc)
    await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/{doc_id}/markdown", response_model=MarkdownResponse)
async def get_document_markdown(doc_id: str, db: AsyncSession = Depends(get_db)):
    """
    Fetches the structured Markdown content parsed by Baidu PaddleOCR-VL.
    """
    stmt = select(DocumentModel).where(DocumentModel.id == doc_id)
    result = await db.execute(stmt)
    doc = result.scalar_one_or_none()
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")

    md_path = STORAGE_DIR / f"{doc.id}.md"
    if not md_path.exists():
        return MarkdownResponse(
            doc_id=doc_id,
            has_markdown=False,
            markdown="",
            page_count=doc.page_count
        )

    try:
        async with aiofiles.open(md_path, "r", encoding="utf-8") as f:
            content = await f.read()
        return MarkdownResponse(
            doc_id=doc_id,
            has_markdown=True,
            markdown=content,
            page_count=doc.page_count
        )
    except Exception as e:
        return MarkdownResponse(
            doc_id=doc_id,
            has_markdown=False,
            markdown="",
            page_count=doc.page_count
        )


@router.put("/{doc_id}/markdown", response_model=MarkdownResponse)
async def update_document_markdown(
    doc_id: str,
    update_req: MarkdownUpdateRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    Updates or saves user-edited Markdown text for the document.
    """
    stmt = select(DocumentModel).where(DocumentModel.id == doc_id)
    result = await db.execute(stmt)
    doc = result.scalar_one_or_none()
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")

    md_path = STORAGE_DIR / f"{doc.id}.md"
    async with aiofiles.open(md_path, "w", encoding="utf-8") as f:
        await f.write(update_req.markdown)

    if update_req.markdown.strip():
        doc.ocr_status = "completed"
        ocr_job_manager.set_job_status(
            doc_id,
            "completed",
            progress=1.0,
            current_page=doc.page_count,
            total_pages=doc.page_count,
            message="OCR Markdown 已同步至云端"
        )
        await db.commit()
        await db.refresh(doc)

    return MarkdownResponse(
        doc_id=doc_id,
        has_markdown=True,
        markdown=update_req.markdown,
        page_count=doc.page_count
    )


@router.get("/{doc_id}/markdown/download")
async def download_document_markdown(doc_id: str, db: AsyncSession = Depends(get_db)):
    """
    Downloads the OCR Markdown file directly as an attachment.
    """
    stmt = select(DocumentModel).where(DocumentModel.id == doc_id)
    result = await db.execute(stmt)
    doc = result.scalar_one_or_none()
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")

    md_path = STORAGE_DIR / f"{doc.id}.md"
    if not md_path.exists():
        raise HTTPException(status_code=404, detail="Markdown file not found for this document")

    safe_title = re.sub(r'[\\/*?:"<>|]', '_', doc.title)
    download_filename = f"{safe_title}.md"
    return FileResponse(
        path=str(md_path),
        media_type="text/markdown; charset=utf-8",
        filename=download_filename,
        headers={
            "Content-Disposition": f'attachment; filename="{download_filename}"'
        }
    )



@router.get("/{doc_id}/file")
async def get_document_file(doc_id: str, request: Request, db: AsyncSession = Depends(get_db)):
    """
    High-performance PDF streamer supporting HTTP 206 Partial Content (Byte Range Requests).
    Uses Starlette FileResponse which automatically handles Range requests, ETags, and chunked streaming.
    """
    stmt = select(DocumentModel).where(DocumentModel.id == doc_id)
    result = await db.execute(stmt)
    doc = result.scalar_one_or_none()
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")
    
    file_path = STORAGE_DIR / f"{doc.id}.pdf"
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Document file missing on server")
    
    return FileResponse(
        path=str(file_path),
        media_type="application/pdf",
        filename=doc.filename,
        headers={
            "Accept-Ranges": "bytes",
            "Access-Control-Expose-Headers": "Content-Range, Accept-Ranges, Content-Length, Content-Disposition",
        }
    )


@router.post("/{doc_id}/ocr", response_model=OcrStatusResponse)
async def trigger_document_ocr(
    doc_id: str,
    ocr_req: OcrRequest = OcrRequest(),
    db: AsyncSession = Depends(get_db)
):
    """
    Triggers dual-layer searchable PDF OCR conversion for scanned/image PDFs.
    Processes asynchronously in background and embeds invisible text with math support.
    """
    stmt = select(DocumentModel).where(DocumentModel.id == doc_id)
    result = await db.execute(stmt)
    doc = result.scalar_one_or_none()
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")

    file_path = STORAGE_DIR / f"{doc.id}.pdf"
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Document file missing on server")

    # Mark document as processing in DB
    doc.ocr_status = "processing"
    await db.commit()

    # Launch background task
    asyncio.create_task(
        ocr_job_manager.run_ocr_task(
            doc_id=doc_id,
            file_path=file_path,
            ocr_req=ocr_req,
            db_session_factory=AsyncSessionLocal
        )
    )

    target_count = len(ocr_req.target_pages) if ocr_req.target_pages else doc.page_count
    return OcrStatusResponse(
        doc_id=doc_id,
        status="processing",
        progress=0.05,
        current_page=0,
        total_pages=target_count,
        message="已启动百度 AI Studio PaddleOCR-VL 识别任务..."
    )


@router.get("/{doc_id}/ocr-status", response_model=OcrStatusResponse)
async def get_document_ocr_status(doc_id: str, db: AsyncSession = Depends(get_db)):
    """
    Fetches real-time status and progress of the OCR conversion job.
    """
    stmt = select(DocumentModel).where(DocumentModel.id == doc_id)
    result = await db.execute(stmt)
    doc = result.scalar_one_or_none()
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")

    job_status = ocr_job_manager.get_job_status(doc_id)
    if job_status["status"] == "none" and doc.ocr_status != "none":
        return OcrStatusResponse(
            doc_id=doc_id,
            status=doc.ocr_status,
            progress=1.0 if doc.ocr_status == "completed" else 0.0,
            current_page=doc.page_count if doc.ocr_status == "completed" else 0,
            total_pages=doc.page_count,
            message="OCR 已完成" if doc.ocr_status == "completed" else ""
        )

    return OcrStatusResponse(
        doc_id=doc_id,
        status=job_status["status"],
        progress=job_status.get("progress", 0.0),
        current_page=job_status.get("current_page", 0),
        total_pages=job_status.get("total_pages", doc.page_count),
        message=job_status.get("message", ""),
        error=job_status.get("error")
    )


@router.post("/{doc_id}/ocr/revert", response_model=DocumentResponse)
async def revert_document_ocr(
    doc_id: str,
    revert_req: OcrRevertRequest = OcrRevertRequest(),
    db: AsyncSession = Depends(get_db)
):
    """
    Clears OCR Markdown on target pages (or entire document).
    """
    stmt = select(DocumentModel).where(DocumentModel.id == doc_id)
    result = await db.execute(stmt)
    doc = result.scalar_one_or_none()
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")

    file_path = STORAGE_DIR / f"{doc.id}.pdf"
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Document file missing on server")

    # Execute revert in thread pool
    loop = asyncio.get_running_loop()
    target_pages = None if revert_req.page_scope == "all" else revert_req.target_pages
    success = await loop.run_in_executor(
        None,
        revert_ocr_sync,
        str(file_path),
        target_pages
    )

    if not success:
        raise HTTPException(status_code=500, detail="Failed to revert OCR on document")

    md_path = STORAGE_DIR / f"{doc.id}.md"
    if not md_path.exists() or revert_req.page_scope == "all" or not target_pages:
        doc.ocr_status = "none"
        ocr_job_manager.set_job_status(doc_id, "none", progress=0.0, message="已清除 OCR 结果")

    await db.commit()
    await db.refresh(doc)
    return await get_document(doc_id, db)


