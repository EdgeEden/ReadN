from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import HOST, PORT, CORS_ORIGINS
from app.database import init_db
from app.routers import documents, annotations


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: initialize database tables
    await init_db()
    yield
    # Shutdown logic if needed


app = FastAPI(
    title="ReadN Cloud Backend",
    description="High-performance PDF cloud storage, streaming, and annotation sync API",
    version="1.0.0",
    lifespan=lifespan
)

# Enable CORS for Web and Mobile clients
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Range", "Accept-Ranges", "Content-Length", "Content-Disposition"]
)

# Register routers
app.include_router(documents.router)
app.include_router(annotations.router)


@app.get("/api/health")
async def health_check():
    return {
        "status": "healthy",
        "service": "ReadN Backend API",
        "version": "1.0.0"
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host=HOST, port=PORT, reload=True)

