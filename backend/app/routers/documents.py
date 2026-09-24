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
)
from app.services.ocr_service import detect_text_layer, ocr_job_manager

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
    
    # Remove physical file
    file_path = STORAGE_DIR / f"{doc.id}.pdf"
    if file_path.exists():
        try:
            os.remove(file_path)
        except OSError:
            pass
            
    await db.delete(doc)
    await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


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
            languages=ocr_req.languages,
            db_session_factory=AsyncSessionLocal
        )
    )

    return OcrStatusResponse(
        doc_id=doc_id,
        status="processing",
        progress=0.05,
        current_page=0,
        total_pages=doc.page_count,
        message="已启动双层可检索 PDF 转换任务..."
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
