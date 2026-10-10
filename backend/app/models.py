from datetime import datetime, timezone
from typing import List, Optional
from pydantic import BaseModel, ConfigDict
from sqlalchemy import Column, String, Integer, DateTime, ForeignKey, Text
from sqlalchemy.orm import declarative_base, relationship

Base = declarative_base()


def utc_now():
    return datetime.now(timezone.utc)


# SQLAlchemy Models
class DocumentModel(Base):
    __tablename__ = "documents"

    id = Column(String(36), primary_key=True, index=True)
    filename = Column(String(255), nullable=False)
    title = Column(String(255), nullable=False)
    file_size = Column(Integer, nullable=False)
    page_count = Column(Integer, default=0)
    has_text_layer = Column(Integer, default=1)  # 1 = True, 0 = False
    ocr_status = Column(String(20), default="none")  # "none" | "processing" | "completed" | "failed"
    checksum = Column(String(64), nullable=True)
    created_at = Column(DateTime(timezone=True), default=utc_now)
    updated_at = Column(DateTime(timezone=True), default=utc_now, onupdate=utc_now)

    annotations = relationship(
        "AnnotationModel",
        back_populates="document",
        cascade="all, delete-orphan",
        lazy="selectin"
    )


class AnnotationModel(Base):
    __tablename__ = "annotations"

    id = Column(String(36), primary_key=True, index=True)
    doc_id = Column(String(36), ForeignKey("documents.id", ondelete="CASCADE"), index=True, nullable=False)
    type = Column(String(20), default="highlight")  # "highlight" | "note"
    page_number = Column(Integer, nullable=False)    # 1-indexed
    color_hex = Column(String(10), default="#FFE066") # Hex color code
    rects_json = Column(Text, nullable=False)        # JSON string of bounding rectangles
    selected_text = Column(Text, default="")
    note_content = Column(Text, default="")
    created_at = Column(DateTime(timezone=True), default=utc_now)
    updated_at = Column(DateTime(timezone=True), default=utc_now, onupdate=utc_now)

    document = relationship("DocumentModel", back_populates="annotations")


# Pydantic Schemas
class Rect(BaseModel):
    x: float
    y: float
    width: float
    height: float


class AnnotationBase(BaseModel):
    id: Optional[str] = None
    doc_id: str
    type: str = "highlight"
    page_number: int
    color_hex: str = "#FFE066"
    rects: List[Rect]
    selected_text: Optional[str] = ""
    note_content: Optional[str] = ""


class AnnotationCreate(BaseModel):
    id: Optional[str] = None
    type: str = "highlight"
    page_number: int
    color_hex: str = "#FFE066"
    rects: List[Rect]
    selected_text: Optional[str] = ""
    note_content: Optional[str] = ""


class AnnotationUpdate(BaseModel):
    color_hex: Optional[str] = None
    note_content: Optional[str] = None
    selected_text: Optional[str] = None
    type: Optional[str] = None
    rects: Optional[List[Rect]] = None


class AnnotationResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    doc_id: str
    type: str
    page_number: int
    color_hex: str
    rects: List[Rect]
    selected_text: str
    note_content: str
    created_at: datetime
    updated_at: datetime


class BatchAnnotationSync(BaseModel):
    annotations: List[AnnotationCreate]


class DocumentResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    filename: str
    title: str
    file_size: int
    page_count: int
    has_text_layer: bool = True
    has_markdown: bool = False
    ocr_status: Optional[str] = "none"
    checksum: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    annotation_count: Optional[int] = 0


class DocumentUpdate(BaseModel):
    title: Optional[str] = None


class MarkdownResponse(BaseModel):
    doc_id: str
    has_markdown: bool
    markdown: str = ""
    page_count: int = 0


class MarkdownUpdateRequest(BaseModel):
    markdown: str


class OcrRequest(BaseModel):
    engine: str = "mineru"  # "mineru" (默认) | "paddleocr_vl"
    
    # MinerU API 配置
    mineru_token: Optional[str] = "REDACTED_MINERU_TOKEN"
    mineru_model_version: str = "vlm"  # "vlm" | "pipeline" | "MinerU-HTML"
    mineru_language: str = "auto"  # "auto" | "ch" | "en" | "ja" | "ko" 等
    enable_formula: bool = True
    enable_table: bool = True
    layout_model: str = "doclayout_yolo"
    oss_accelerate: bool = True  # 是否使用海外/全球 OSS 传输加速专线
    
    # 百度 PaddleOCR-VL API 配置 (兼容保留)
    api_token: Optional[str] = "REDACTED_BAIDU_TOKEN"
    api_url: Optional[str] = "https://paddleocr.aistudio-app.com/api/v2/ocr/jobs"
    model_name: Optional[str] = "PaddleOCR-VL-1.6"
    page_scope: str = "all"  # "all" | "current" | "custom"
    target_pages: Optional[List[int]] = None  # 1-indexed list of pages, e.g. [1, 2, 5]
    markdown_ignore_labels: Optional[List[str]] = [
        "header",
        "header_image",
        "footer",
        "footer_image",
        "number",
        "footnote",
        "aside_text"
    ]
    use_doc_orientation_classify: bool = False
    use_doc_unwarping: bool = False
    use_layout_detection: bool = True
    use_chart_recognition: bool = False
    use_seal_recognition: bool = True
    use_ocr_for_image_block: bool = False
    merge_tables: bool = True
    relevel_titles: bool = True
    layout_shape_mode: str = "auto"
    prompt_label: str = "ocr"
    repetition_penalty: float = 1.0
    temperature: float = 0.0
    top_p: float = 1.0
    min_pixels: int = 147384
    max_pixels: int = 2822400
    layout_nms: bool = True
    restructure_pages: bool = True


class OcrStatusResponse(BaseModel):
    doc_id: str
    status: str  # "none" | "processing" | "completed" | "failed"
    progress: float = 0.0  # 0.0 to 1.0
    current_page: int = 0
    total_pages: int = 0
    message: str = ""
    phase: Optional[str] = "idle"  # "preparing" | "uploading" | "processing" | "downloading" | "merging" | "completed"
    upload_speed_mb_s: Optional[float] = None
    upload_progress: Optional[float] = None
    error: Optional[str] = None


class OcrRevertRequest(BaseModel):
    page_scope: str = "current"  # "current" | "all" | "custom"
    target_pages: Optional[List[int]] = None  # 1-indexed list of pages to revert, e.g. [1, 3]




