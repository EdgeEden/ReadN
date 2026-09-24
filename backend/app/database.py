from typing import AsyncGenerator
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from app.config import DATABASE_URL
from app.models import Base

engine = create_async_engine(
    DATABASE_URL,
    echo=False,
    future=True,
    connect_args={"check_same_thread": False} if "sqlite" in DATABASE_URL else {}
)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
    autocommit=False
)


async def init_db() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        
        # Safe migration for existing SQLite databases
        if "sqlite" in DATABASE_URL:
            from sqlalchemy import text
            try:
                await conn.execute(text("ALTER TABLE documents ADD COLUMN has_text_layer INTEGER DEFAULT 1"))
            except Exception:
                pass
            try:
                await conn.execute(text("ALTER TABLE documents ADD COLUMN ocr_status VARCHAR(20) DEFAULT 'none'"))
            except Exception:
                pass


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()

