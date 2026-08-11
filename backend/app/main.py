from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.api.v1.router import router as v1_router
from app.core.database import dispose_engine
from app.core.errors import DomainError
from app.core.security import get_jwt_validator


@asynccontextmanager
async def lifespan(_: FastAPI):
    yield
    await get_jwt_validator().aclose()
    await dispose_engine()


app = FastAPI(
    title="Sa7tot API",
    version="0.1.0",
    description="Remote-only financial backend foundation for Sa7tot.",
    lifespan=lifespan,
)
app.include_router(v1_router)


@app.get("/health", tags=["health"])
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.exception_handler(DomainError)
async def domain_error_handler(_: Request, exc: DomainError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": {"code": exc.code, "detail": exc.detail}},
    )
