from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException
from app.config import HOST, PORT, CORS_ORIGINS, STATIC_DIR, APP_VERSION
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
    version=APP_VERSION,
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

# Anti-caching middleware for frontend entry points and service workers
@app.middleware("http")
async def add_cache_control_headers(request: Request, call_next):
    response = await call_next(request)
    path = request.url.path
    if (
        path in ("/", "/index.html", "/version.json", "/flutter_bootstrap.js", "/flutter_service_worker.js")
        or path.endswith(".html")
        or "version.json" in path
    ):
        response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
        response.headers["Pragma"] = "no-cache"
        response.headers["Expires"] = "0"
    return response


# Register routers
app.include_router(documents.router)
app.include_router(annotations.router)


@app.get("/api/health")
async def health_check():
    return {
        "status": "healthy",
        "service": "ReadN Backend API",
        "version": APP_VERSION
    }


@app.get("/version.json")
async def get_version_json():
    version_file = STATIC_DIR / "version.json"
    if version_file.exists():
        resp = FileResponse(str(version_file), media_type="application/json")
    else:
        resp = JSONResponse({
            "app_name": "frontend",
            "version": APP_VERSION,
            "build_number": "1",
            "package_name": "frontend"
        })
    resp.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    resp.headers["Pragma"] = "no-cache"
    resp.headers["Expires"] = "0"
    return resp


# Mount static files if web build exists
if STATIC_DIR.exists() and (STATIC_DIR / "index.html").exists():
    @app.exception_handler(StarletteHTTPException)
    async def custom_http_exception_handler(request: Request, exc: StarletteHTTPException):
        if exc.status_code == 404 and not request.url.path.startswith("/api/"):
            index_file = STATIC_DIR / "index.html"
            if index_file.exists():
                resp = FileResponse(str(index_file))
                resp.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
                resp.headers["Pragma"] = "no-cache"
                resp.headers["Expires"] = "0"
                return resp
        return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})

    app.mount("/", StaticFiles(directory=str(STATIC_DIR), html=True), name="static")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host=HOST, port=PORT, reload=True)

