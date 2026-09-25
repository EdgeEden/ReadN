import json
import uuid
from typing import List
from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import select, delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import (
    AnnotationModel,
    AnnotationCreate,
    AnnotationUpdate,
    AnnotationResponse,
    BatchAnnotationSync,
    DocumentModel,
    Rect
)

router = APIRouter(prefix="/api/documents/{doc_id}/annotations", tags=["annotations"])


def to_response(anno: AnnotationModel) -> AnnotationResponse:
    try:
        raw_rects = json.loads(anno.rects_json)
        rects = [Rect(**r) for r in raw_rects]
    except Exception:
        rects = []
        
    return AnnotationResponse(
        id=anno.id,
        doc_id=anno.doc_id,
        type=anno.type,
        page_number=anno.page_number,
        color_hex=anno.color_hex,
        rects=rects,
        selected_text=anno.selected_text or "",
        note_content=anno.note_content or "",
        created_at=anno.created_at,
        updated_at=anno.updated_at
    )


async def ensure_document_exists(doc_id: str, db: AsyncSession):
    stmt = select(DocumentModel.id).where(DocumentModel.id == doc_id)
    result = await db.execute(stmt)
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Document not found")


@router.get("", response_model=List[AnnotationResponse])
async def list_annotations(doc_id: str, db: AsyncSession = Depends(get_db)):
    await ensure_document_exists(doc_id, db)
    stmt = (
        select(AnnotationModel)
        .where(AnnotationModel.doc_id == doc_id)
        .order_by(AnnotationModel.page_number.asc(), AnnotationModel.created_at.asc())
    )
    result = await db.execute(stmt)
    annotations = result.scalars().all()
    return [to_response(a) for a in annotations]


@router.post("", response_model=AnnotationResponse, status_code=status.HTTP_201_CREATED)
async def create_annotation(
    doc_id: str,
    payload: AnnotationCreate,
    db: AsyncSession = Depends(get_db)
):
    await ensure_document_exists(doc_id, db)
    anno_id = payload.id if payload.id else str(uuid.uuid4())
    
    # Rectangles converted to JSON string
    rects_json = json.dumps([r.model_dump() for r in payload.rects])
    
    db_anno = AnnotationModel(
        id=anno_id,
        doc_id=doc_id,
        type=payload.type,
        page_number=payload.page_number,
        color_hex=payload.color_hex,
        rects_json=rects_json,
        selected_text=payload.selected_text or "",
        note_content=payload.note_content or ""
    )
    db.add(db_anno)
    await db.commit()
    await db.refresh(db_anno)
    return to_response(db_anno)


@router.put("/{annotation_id}", response_model=AnnotationResponse)
async def update_annotation(
    doc_id: str,
    annotation_id: str,
    payload: AnnotationUpdate,
    db: AsyncSession = Depends(get_db)
):
    await ensure_document_exists(doc_id, db)
    stmt = select(AnnotationModel).where(
        AnnotationModel.id == annotation_id,
        AnnotationModel.doc_id == doc_id
    )
    result = await db.execute(stmt)
    anno = result.scalar_one_or_none()
    if not anno:
        raise HTTPException(status_code=404, detail="Annotation not found")
    
    if payload.color_hex is not None:
        anno.color_hex = payload.color_hex
    if payload.note_content is not None:
        anno.note_content = payload.note_content
    if payload.selected_text is not None:
        anno.selected_text = payload.selected_text
    if payload.type is not None:
        anno.type = payload.type
    if payload.rects is not None:
        anno.rects_json = json.dumps([r.model_dump() for r in payload.rects])
        
    await db.commit()
    await db.refresh(anno)
    return to_response(anno)


@router.delete("/{annotation_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_annotation(
    doc_id: str,
    annotation_id: str,
    db: AsyncSession = Depends(get_db)
):
    await ensure_document_exists(doc_id, db)
    stmt = select(AnnotationModel).where(
        AnnotationModel.id == annotation_id,
        AnnotationModel.doc_id == doc_id
    )
    result = await db.execute(stmt)
    anno = result.scalar_one_or_none()
    if not anno:
        raise HTTPException(status_code=404, detail="Annotation not found")
        
    await db.delete(anno)
    await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/batch", response_model=List[AnnotationResponse])
async def batch_sync_annotations(
    doc_id: str,
    payload: BatchAnnotationSync,
    db: AsyncSession = Depends(get_db)
):
    """
    Batch synchronize annotations for offline-first sync.
    Inserts or updates existing annotations by ID.
    """
    await ensure_document_exists(doc_id, db)
    saved_annos = []
    
    for item in payload.annotations:
        anno_id = item.id if item.id else str(uuid.uuid4())
        rects_json = json.dumps([r.model_dump() for r in item.rects])
        
        stmt = select(AnnotationModel).where(
            AnnotationModel.id == anno_id,
            AnnotationModel.doc_id == doc_id
        )
        existing = (await db.execute(stmt)).scalar_one_or_none()
        
        if existing:
            existing.type = item.type
            existing.page_number = item.page_number
            existing.color_hex = item.color_hex
            existing.rects_json = rects_json
            existing.selected_text = item.selected_text or ""
            existing.note_content = item.note_content or ""
            saved_annos.append(existing)
        else:
            new_anno = AnnotationModel(
                id=anno_id,
                doc_id=doc_id,
                type=item.type,
                page_number=item.page_number,
                color_hex=item.color_hex,
                rects_json=rects_json,
                selected_text=item.selected_text or "",
                note_content=item.note_content or ""
            )
            db.add(new_anno)
            saved_annos.append(new_anno)
            
    await db.commit()
    for a in saved_annos:
        await db.refresh(a)
        
    return [to_response(a) for a in saved_annos]

