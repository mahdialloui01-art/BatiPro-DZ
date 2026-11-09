import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from psycopg_pool import AsyncConnectionPool


@asynccontextmanager
async def lifespan(app: FastAPI):
    database_url = os.getenv("DATABASE_URL", "").strip()
    app.state.db_pool = None
    if database_url:
        pool = AsyncConnectionPool(conninfo=database_url, open=False, min_size=1, max_size=10)
        await pool.open(wait=True)
        app.state.db_pool = pool
    try:
        yield
    finally:
        if app.state.db_pool is not None:
            await app.state.db_pool.close()


app = FastAPI(
    title="BatiPro DZ API",
    version="0.1.0",
    description="Secure service layer for BatiPro DZ desktop and Android clients.",
    lifespan=lifespan,
)


@app.get("/health/live", tags=["health"])
async def live():
    return {"status": "alive"}


@app.get("/health/ready", tags=["health"])
async def ready():
    pool = getattr(app.state, "db_pool", None)
    if pool is None:
        raise HTTPException(status_code=503, detail="Database is not configured")
    try:
        async with pool.connection() as connection:
            await connection.execute("SELECT 1")
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Database is unavailable") from exc
    return {"status": "ready", "database": "connected"}
