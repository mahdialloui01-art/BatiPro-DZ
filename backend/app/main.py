import os
from contextlib import asynccontextmanager
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP
from uuid import UUID
import base64
import hashlib
import hmac
import json
import secrets
from typing import Any

from fastapi import Depends, FastAPI, Header, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
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


app = FastAPI(title="BatiPro DZ API", version="0.2.0",
              description="Authenticated service layer for BatiPro DZ Windows clients.", lifespan=lifespan)


def _pool():
    pool = getattr(app.state, "db_pool", None)
    if pool is None:
        raise HTTPException(status_code=503, detail="Database is not configured")
    return pool


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _password_hash(password: str) -> str:
    salt = secrets.token_bytes(16)
    derived = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 310_000)
    return "pbkdf2_sha256$310000$" + _b64(salt) + "$" + _b64(derived)


def _verify_password(password: str, encoded: str) -> bool:
    try:
        algorithm, rounds, salt_text, expected = encoded.split("$")
        if algorithm != "pbkdf2_sha256" or int(rounds) != 310_000:
            return False
        salt = base64.urlsafe_b64decode(salt_text + "=" * (-len(salt_text) % 4))
        actual = _b64(hashlib.pbkdf2_hmac("sha256", password.encode(), salt, int(rounds)))
        return hmac.compare_digest(actual, expected)
    except (ValueError, TypeError):
        return False


def _token_for(user_id: str, organization_id: str) -> str:
    secret = os.getenv("BATIPRO_TOKEN_SECRET", "")
    if len(secret) < 32:
        raise HTTPException(status_code=503, detail="Authentication is not configured")
    now = datetime.now(timezone.utc)
    header = _b64(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
    payload = _b64(json.dumps({
        "sub": user_id, "org": organization_id,
        "iat": int(now.timestamp()), "exp": int((now + timedelta(hours=12)).timestamp()),
    }, separators=(",", ":")).encode())
    signing_input = header + "." + payload
    signature = _b64(hmac.new(secret.encode(), signing_input.encode(), hashlib.sha256).digest())
    return signing_input + "." + signature


async def _current_user(authorization: str | None = Header(default=None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Authentication required")
    parts = authorization[7:].split(".")
    secret = os.getenv("BATIPRO_TOKEN_SECRET", "")
    if len(secret) < 32 or len(parts) != 3:
        raise HTTPException(status_code=401, detail="Invalid access token")
    signing_input = parts[0] + "." + parts[1]
    expected = _b64(hmac.new(secret.encode(), signing_input.encode(), hashlib.sha256).digest())
    if not hmac.compare_digest(expected, parts[2]):
        raise HTTPException(status_code=401, detail="Invalid access token")
    try:
        payload = json.loads(base64.urlsafe_b64decode(parts[1] + "=" * (-len(parts[1]) % 4)))
        if int(payload["exp"]) <= int(datetime.now(timezone.utc).timestamp()):
            raise ValueError("expired")
        UUID(payload["sub"])
        UUID(payload["org"])
        async with _pool().connection() as connection:
            membership = await (await connection.execute(
                """SELECT om.role FROM organization_members om
                   JOIN users u ON u.id=om.user_id
                   WHERE om.user_id=%s AND om.organization_id=%s AND u.is_active=TRUE""",
                (payload["sub"],payload["org"]))).fetchone()
        if membership is None:
            raise HTTPException(status_code=401, detail="Account access has been revoked")
        return {"user_id": payload["sub"], "organization_id": payload["org"], "role": membership[0]}
    except (ValueError, KeyError, TypeError, json.JSONDecodeError):
        raise HTTPException(status_code=401, detail="Invalid or expired access token")


def _writer(user=Depends(_current_user)):
    if user["role"] not in ("owner", "admin", "manager", "cashier"):
        raise HTTPException(status_code=403, detail="Read-only account")
    return user


class RegisterRequest(BaseModel):
    email: str = Field(min_length=5, max_length=254)
    password: str = Field(min_length=12, max_length=128)
    display_name: str = Field(min_length=2, max_length=120)
    organization_name: str = Field(min_length=2, max_length=160)
    bootstrap_secret: str = Field(min_length=1, max_length=256)


class LoginRequest(BaseModel):
    email: str = Field(min_length=5, max_length=254)
    password: str = Field(min_length=1, max_length=128)


class ProductCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    name: str = Field(min_length=1, max_length=180)
    category: str = Field(min_length=1, max_length=100)
    base_unit: str = Field(min_length=1, max_length=30)
    tracking_mode: str = Field(default="quantity", pattern="^(quantity|weight|piece)$")
    piece_weight_kg: Decimal | None = Field(default=None, gt=0)
    rebar_diameter_mm: Decimal | None = Field(default=None, gt=0)
    bar_length_m: Decimal | None = Field(default=None, gt=0)
    purchase_price: Decimal = Field(default=Decimal("0"), ge=0)
    sale_price: Decimal = Field(default=Decimal("0"), ge=0)
    minimum_stock: Decimal = Field(default=Decimal("0"), ge=0)


class StockAdjustment(BaseModel):
    product_id: UUID
    warehouse_id: UUID
    quantity_delta: Decimal
    unit: str = Field(min_length=1, max_length=30)
    reason: str = Field(min_length=2, max_length=180)
    idempotency_key: str = Field(min_length=8, max_length=120)


class ContactCreate(BaseModel):
    name: str = Field(min_length=2, max_length=180)
    phone: str | None = Field(default=None, max_length=40)
    address: str | None = Field(default=None, max_length=300)


class InvoiceLine(BaseModel):
    product_id: UUID
    entered_quantity: Decimal = Field(gt=0)
    entered_unit: str = Field(min_length=1, max_length=30)
    base_quantity: Decimal = Field(gt=0)
    unit_price: Decimal = Field(ge=0)
    line_total: Decimal = Field(ge=0)
    measured_weight_kg: Decimal | None = Field(default=None, gt=0)


class PurchaseCreate(BaseModel):
    warehouse_id: UUID
    supplier_id: UUID
    invoice_number: str = Field(min_length=1, max_length=80)
    invoice_date: date
    lines: list[InvoiceLine] = Field(min_length=1, max_length=500)
    discount: Decimal = Field(default=Decimal("0"), ge=0)
    paid: Decimal = Field(default=Decimal("0"), ge=0)
    notes: str | None = Field(default=None, max_length=2000)


class SaleLine(BaseModel):
    product_id: UUID
    quantity: Decimal = Field(gt=0)
    unit: str = Field(min_length=1, max_length=30)
    unit_price: Decimal = Field(ge=0)
    line_total: Decimal = Field(ge=0)


class SaleCreate(BaseModel):
    warehouse_id: UUID
    customer_id: UUID | None = None
    invoice_number: str = Field(min_length=1, max_length=80)
    lines: list[SaleLine] = Field(min_length=1, max_length=500)
    discount: Decimal = Field(default=Decimal("0"), ge=0)
    paid: Decimal = Field(default=Decimal("0"), ge=0)
    notes: str | None = Field(default=None, max_length=2000)



class InitialSnapshot(BaseModel):
    device_id: str = Field(min_length=8, max_length=120)
    idempotency_key: str = Field(min_length=8, max_length=120)
    products: list[dict[str, Any]] = Field(default_factory=list, max_length=2000)
    suppliers: list[dict[str, Any]] = Field(default_factory=list, max_length=1000)
    customers: list[dict[str, Any]] = Field(default_factory=list, max_length=1000)
    purchases: list[dict[str, Any]] = Field(default_factory=list, max_length=5000)
    sales: list[dict[str, Any]] = Field(default_factory=list, max_length=5000)


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


@app.post("/auth/register", status_code=status.HTTP_201_CREATED, tags=["authentication"])
async def register(body: RegisterRequest):
    configured = os.getenv("BATIPRO_BOOTSTRAP_SECRET", "")
    if len(configured) < 24 or not hmac.compare_digest(configured, body.bootstrap_secret):
        raise HTTPException(status_code=403, detail="Registration is not authorized")
    email = body.email.strip().lower()
    pool = _pool()
    try:
        async with pool.connection() as connection:
            async with connection.transaction():
                user_result = await connection.execute(
                    "INSERT INTO users (email, password_hash, display_name) VALUES (%s, %s, %s) RETURNING id",
                    (email, _password_hash(body.password), body.display_name.strip()))
                user_id = (await user_result.fetchone())[0]
                org_result = await connection.execute(
                    "INSERT INTO organizations (name) VALUES (%s) RETURNING id",
                    (body.organization_name.strip(),))
                organization_id = (await org_result.fetchone())[0]
                await connection.execute(
                    "INSERT INTO organization_members (organization_id, user_id, role) VALUES (%s, %s, 'owner')",
                    (organization_id, user_id))
                await connection.execute(
                    "INSERT INTO warehouses (organization_id, name) VALUES (%s, 'المخزن الرئيسي')",
                    (organization_id,))
    except Exception as exc:
        if "unique" in str(exc).lower():
            raise HTTPException(status_code=409, detail="Email already registered") from exc
        raise
    return {"access_token": _token_for(str(user_id), str(organization_id)),
            "token_type": "bearer", "expires_in": 43200,
            "organization_id": str(organization_id), "user_id": str(user_id)}


@app.post("/auth/login", tags=["authentication"])
async def login(body: LoginRequest):
    async with _pool().connection() as connection:
        row = await (await connection.execute(
            """SELECT u.id, u.password_hash, om.organization_id
               FROM users u JOIN organization_members om ON om.user_id = u.id
               WHERE lower(u.email) = %s AND u.is_active = TRUE
               ORDER BY om.created_at LIMIT 1""",
            (body.email.strip().lower(),))).fetchone()
    if row is None or not _verify_password(body.password, row[1]):
        raise HTTPException(status_code=401, detail="Email or password is incorrect")
    return {"access_token": _token_for(str(row[0]), str(row[2])),
            "token_type": "bearer", "expires_in": 43200,
            "organization_id": str(row[2]), "user_id": str(row[0])}


@app.get("/me", tags=["authentication"])
async def me(user=Depends(_current_user)):
    async with _pool().connection() as connection:
        row = await (await connection.execute(
            """SELECT u.email, u.display_name, om.role, o.name
               FROM users u JOIN organization_members om
                 ON om.user_id=u.id AND om.organization_id=%s
               JOIN organizations o ON o.id=om.organization_id
               WHERE u.id=%s AND u.is_active=TRUE""",
            (user["organization_id"], user["user_id"]))).fetchone()
    if row is None:
        raise HTTPException(status_code=401, detail="Account is not active")
    return {"email": row[0], "display_name": row[1], "role": row[2], "organization_name": row[3]}


@app.get("/warehouses", tags=["warehouses"])
async def warehouses(user=Depends(_current_user)):
    async with _pool().connection() as connection:
        rows = await (await connection.execute(
            "SELECT id,name,address FROM warehouses WHERE organization_id=%s AND is_active ORDER BY name",
            (user["organization_id"],))).fetchall()
    return [{"id": str(r[0]), "name": r[1], "address": r[2]} for r in rows]


@app.get("/products", tags=["products"])
async def list_products(user=Depends(_current_user)):
    async with _pool().connection() as connection:
        rows = await (await connection.execute(
            """SELECT p.id,p.name,c.name,p.base_unit,p.tracking_mode,p.piece_weight_kg,
                      p.rebar_diameter_mm,p.bar_length_m,p.purchase_price,p.sale_price,p.minimum_stock
               FROM products p LEFT JOIN product_categories c ON c.id=p.category_id
               WHERE p.organization_id=%s AND p.is_active ORDER BY p.name""",
            (user["organization_id"],))).fetchall()
    return [{"id":str(r[0]),"name":r[1],"category":r[2] or "غير مصنف","base_unit":r[3],
             "tracking_mode":r[4],"piece_weight_kg":str(r[5]) if r[5] is not None else None,
             "rebar_diameter_mm":str(r[6]) if r[6] is not None else None,
             "bar_length_m":str(r[7]) if r[7] is not None else None,
             "purchase_price":str(r[8]),"sale_price":str(r[9]),"minimum_stock":str(r[10])} for r in rows]


@app.post("/products", status_code=status.HTTP_201_CREATED, tags=["products"])
async def create_product(body: ProductCreate, user=Depends(_writer)):
    if body.tracking_mode == "piece" and body.piece_weight_kg is None and (
        body.rebar_diameter_mm is None or body.bar_length_m is None
    ):
        raise HTTPException(status_code=422, detail="Set piece weight or both rebar diameter and bar length")
    async with _pool().connection() as connection:
        async with connection.transaction():
            category = await connection.execute(
                """INSERT INTO product_categories (organization_id,name) VALUES (%s,%s)
                   ON CONFLICT (organization_id,name) DO UPDATE SET name=EXCLUDED.name RETURNING id""",
                (user["organization_id"], body.category))
            category_id = (await category.fetchone())[0]
            row = await connection.execute(
                """INSERT INTO products (organization_id,category_id,name,base_unit,tracking_mode,
                   piece_weight_kg,rebar_diameter_mm,bar_length_m,purchase_price,sale_price,minimum_stock)
                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id""",
                (user["organization_id"],category_id,body.name,body.base_unit,body.tracking_mode,
                 body.piece_weight_kg,body.rebar_diameter_mm,body.bar_length_m,
                 body.purchase_price,body.sale_price,body.minimum_stock))
            product_id = (await row.fetchone())[0]
    return {"id":str(product_id),"name":body.name,"category":body.category}


@app.get("/stock", tags=["inventory"])
async def stock(user=Depends(_current_user)):
    async with _pool().connection() as connection:
        rows = await (await connection.execute(
            """SELECT p.id,p.name,p.base_unit,w.id,w.name,COALESCE(SUM(sm.quantity_delta),0)
               FROM products p CROSS JOIN warehouses w
               LEFT JOIN stock_movements sm ON sm.product_id=p.id AND sm.warehouse_id=w.id
                    AND sm.organization_id=p.organization_id
               WHERE p.organization_id=%s AND w.organization_id=%s AND p.is_active AND w.is_active
               GROUP BY p.id,p.name,p.base_unit,w.id,w.name ORDER BY p.name,w.name""",
            (user["organization_id"],user["organization_id"]))).fetchall()
    return [{"product_id":str(r[0]),"name":r[1],"unit":r[2],"warehouse_id":str(r[3]),
             "warehouse":r[4],"quantity":str(r[5])} for r in rows]


@app.post("/stock/adjustments", status_code=status.HTTP_201_CREATED, tags=["inventory"])
async def adjust_stock(body: StockAdjustment, user=Depends(_writer)):
    if body.quantity_delta == 0:
        raise HTTPException(status_code=422, detail="quantity_delta cannot be zero")
    async with _pool().connection() as connection:
        async with connection.transaction():
            existing = await (await connection.execute(
                "SELECT id FROM stock_movements WHERE organization_id=%s AND idempotency_key=%s",
                (user["organization_id"],body.idempotency_key))).fetchone()
            if existing:
                return {"id":str(existing[0]),"duplicate":True}
            valid = await (await connection.execute(
                """SELECT 1 FROM products p JOIN warehouses w ON w.organization_id=p.organization_id
                   WHERE p.id=%s AND p.organization_id=%s AND w.id=%s AND w.is_active""",
                (body.product_id,user["organization_id"],body.warehouse_id))).fetchone()
            if valid is None:
                raise HTTPException(status_code=404, detail="Product or warehouse not found")
            if body.quantity_delta < 0:
                current = await (await connection.execute(
                    """SELECT COALESCE(SUM(quantity_delta),0) FROM stock_movements
                       WHERE organization_id=%s AND product_id=%s AND warehouse_id=%s""",
                    (user["organization_id"],body.product_id,body.warehouse_id))).fetchone()
                if Decimal(current[0]) + body.quantity_delta < 0:
                    raise HTTPException(status_code=409, detail="Insufficient stock")
            row = await connection.execute(
                """INSERT INTO stock_movements (organization_id,warehouse_id,product_id,movement_type,
                   quantity_delta,unit,source_type,idempotency_key)
                   VALUES (%s,%s,%s,'adjustment',%s,%s,'manual',%s) RETURNING id""",
                (user["organization_id"],body.warehouse_id,body.product_id,body.quantity_delta,
                 body.unit,body.idempotency_key))
            movement_id = (await row.fetchone())[0]
            await connection.execute(
                """INSERT INTO audit_logs (organization_id,user_id,action,entity_type,entity_id,metadata)
                   VALUES (%s,%s,'stock.adjustment','stock_movement',%s,%s::jsonb)""",
                (user["organization_id"],user["user_id"],movement_id,
                 json.dumps({"reason":body.reason,"quantity_delta":str(body.quantity_delta)})))
    return {"id":str(movement_id),"duplicate":False}

@app.get("/suppliers", tags=["contacts"])
async def list_suppliers(user=Depends(_current_user)):
    async with _pool().connection() as connection:
        rows = await (await connection.execute(
            "SELECT id,name,phone,address,opening_balance FROM suppliers WHERE organization_id=%s ORDER BY name",
            (user["organization_id"],))).fetchall()
    return [{"id":str(r[0]),"name":r[1],"phone":r[2],"address":r[3],"opening_balance":str(r[4])} for r in rows]


@app.post("/suppliers", status_code=status.HTTP_201_CREATED, tags=["contacts"])
async def create_supplier(body: ContactCreate, user=Depends(_writer)):
    async with _pool().connection() as connection:
        row = await connection.execute(
            "INSERT INTO suppliers (organization_id,name,phone,address) VALUES (%s,%s,%s,%s) RETURNING id",
            (user["organization_id"],body.name,body.phone,body.address))
        supplier_id = (await row.fetchone())[0]
    return {"id":str(supplier_id),"name":body.name}


@app.get("/customers", tags=["contacts"])
async def list_customers(user=Depends(_current_user)):
    async with _pool().connection() as connection:
        rows = await (await connection.execute(
            "SELECT id,name,phone,address,opening_balance FROM customers WHERE organization_id=%s ORDER BY name",
            (user["organization_id"],))).fetchall()
    return [{"id":str(r[0]),"name":r[1],"phone":r[2],"address":r[3],"opening_balance":str(r[4])} for r in rows]


@app.post("/customers", status_code=status.HTTP_201_CREATED, tags=["contacts"])
async def create_customer(body: ContactCreate, user=Depends(_writer)):
    async with _pool().connection() as connection:
        row = await connection.execute(
            "INSERT INTO customers (organization_id,name,phone,address) VALUES (%s,%s,%s,%s) RETURNING id",
            (user["organization_id"],body.name,body.phone,body.address))
        customer_id = (await row.fetchone())[0]
    return {"id":str(customer_id),"name":body.name}


@app.post("/purchases", status_code=status.HTTP_201_CREATED, tags=["purchases"])
async def create_purchase(body: PurchaseCreate, user=Depends(_writer)):
    for line in body.lines:
        expected_line_total = (line.entered_quantity * line.unit_price).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        if line.line_total != expected_line_total:
            raise HTTPException(status_code=422, detail="Purchase line total does not match quantity × unit price")
    subtotal = sum((line.line_total for line in body.lines), Decimal("0"))
    total = subtotal - body.discount
    if total < 0 or body.paid > total:
        raise HTTPException(status_code=422, detail="Discount or payment exceeds invoice total")
    pool = _pool()
    async with pool.connection() as connection:
        async with connection.transaction():
            valid = await (await connection.execute(
                """SELECT 1 FROM suppliers s JOIN warehouses w
                   ON w.organization_id=s.organization_id
                   WHERE s.id=%s AND s.organization_id=%s AND w.id=%s AND w.is_active""",
                (body.supplier_id,user["organization_id"],body.warehouse_id))).fetchone()
            if valid is None:
                raise HTTPException(status_code=404, detail="Supplier or warehouse not found")
            invoice_result = await connection.execute(
                """INSERT INTO purchase_invoices
                   (organization_id,warehouse_id,supplier_id,invoice_number,invoice_date,
                    subtotal,discount,total,paid,notes)
                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id""",
                (user["organization_id"],body.warehouse_id,body.supplier_id,body.invoice_number,
                 body.invoice_date,subtotal,body.discount,total,body.paid,body.notes))
            invoice_id = (await invoice_result.fetchone())[0]
            for index, line in enumerate(body.lines):
                product = await (await connection.execute(
                    """SELECT base_unit,tracking_mode,piece_weight_kg,rebar_diameter_mm,bar_length_m
                       FROM products WHERE id=%s AND organization_id=%s AND is_active FOR UPDATE""",
                    (line.product_id,user["organization_id"]))).fetchone()
                if product is None:
                    raise HTTPException(status_code=404, detail="A purchase product was not found")
                base_unit, tracking_mode, piece_weight, diameter, length = product
                entered_unit = line.entered_unit.strip().lower()
                measured_weight = None
                if tracking_mode == "piece" and entered_unit in ("kg", "ton"):
                    measured_weight = line.entered_quantity * (Decimal("1000") if entered_unit == "ton" else Decimal("1"))
                    if piece_weight is None and diameter is not None and length is not None:
                        piece_weight = (Decimal("3.141592653589793") / Decimal("4") *
                                        (Decimal(diameter) / Decimal("1000")) ** 2 *
                                        Decimal(length) * Decimal("7850"))
                    if piece_weight is None or piece_weight <= 0:
                        raise HTTPException(status_code=422, detail="Steel product has no valid piece weight")
                    expected_base = (measured_weight / Decimal(piece_weight)).quantize(Decimal("0.001"), rounding=ROUND_HALF_UP)
                elif entered_unit == str(base_unit).lower():
                    expected_base = line.entered_quantity
                elif entered_unit == "ton" and str(base_unit).lower() == "kg":
                    expected_base = line.entered_quantity * Decimal("1000")
                elif entered_unit == "kg" and str(base_unit).lower() == "ton":
                    expected_base = line.entered_quantity / Decimal("1000")
                else:
                    raise HTTPException(status_code=422, detail="Purchase unit is incompatible with product base unit")
                expected_base = expected_base.quantize(Decimal("0.001"), rounding=ROUND_HALF_UP)
                if abs(line.base_quantity - expected_base) > Decimal("0.001"):
                    raise HTTPException(status_code=422, detail="Base quantity does not match the unit conversion")
                if line.measured_weight_kg is not None and measured_weight is not None:
                    if abs(line.measured_weight_kg - measured_weight) > Decimal("0.001"):
                        raise HTTPException(status_code=422, detail="Measured weight does not match purchase quantity")
                await connection.execute(
                    """INSERT INTO purchase_lines
                       (organization_id,purchase_invoice_id,product_id,entered_quantity,entered_unit,
                        base_quantity,unit_price,line_total,measured_weight_kg)
                       VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                    (user["organization_id"],invoice_id,line.product_id,line.entered_quantity,
                     line.entered_unit,expected_base,line.unit_price,line.line_total,
                     measured_weight if measured_weight is not None else line.measured_weight_kg))
                await connection.execute(
                    """INSERT INTO stock_movements
                       (organization_id,warehouse_id,product_id,movement_type,quantity_delta,
                        unit,source_type,source_id,idempotency_key)
                       VALUES (%s,%s,%s,'purchase',%s,%s,'purchase',%s,%s)""",
                    (user["organization_id"],body.warehouse_id,line.product_id,expected_base,
                     base_unit,invoice_id,"purchase:"+str(invoice_id)+":"+str(index)))
            if body.paid > 0:
                await connection.execute(
                    """INSERT INTO payments
                       (organization_id,party_type,party_id,invoice_type,invoice_id,amount,method)
                       VALUES (%s,'supplier',%s,'purchase',%s,%s,'unspecified')""",
                    (user["organization_id"],body.supplier_id,invoice_id,body.paid))
            await connection.execute(
                """INSERT INTO audit_logs (organization_id,user_id,action,entity_type,entity_id,metadata)
                   VALUES (%s,%s,'purchase.posted','purchase_invoice',%s,%s::jsonb)""",
                (user["organization_id"],user["user_id"],invoice_id,
                 json.dumps({"invoice_number":body.invoice_number,"total":str(total)})))
    return {"id":str(invoice_id),"invoice_number":body.invoice_number,
            "subtotal":str(subtotal),"total":str(total),"paid":str(body.paid),
            "due":str(total-body.paid)}


@app.post("/sales", status_code=status.HTTP_201_CREATED, tags=["sales"])
async def create_sale(body: SaleCreate, user=Depends(_writer)):
    for line in body.lines:
        expected_line_total = (line.quantity * line.unit_price).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        if line.line_total != expected_line_total:
            raise HTTPException(status_code=422, detail="Sales line total does not match quantity × unit price")
    subtotal = sum((line.line_total for line in body.lines), Decimal("0"))
    total = subtotal - body.discount
    if total < 0 or body.paid > total:
        raise HTTPException(status_code=422, detail="Discount or payment exceeds invoice total")
    pool = _pool()
    async with pool.connection() as connection:
        async with connection.transaction():
            warehouse = await (await connection.execute(
                "SELECT 1 FROM warehouses WHERE id=%s AND organization_id=%s AND is_active",
                (body.warehouse_id,user["organization_id"]))).fetchone()
            if warehouse is None:
                raise HTTPException(status_code=404, detail="Warehouse not found")
            if body.customer_id is not None:
                customer = await (await connection.execute(
                    "SELECT 1 FROM customers WHERE id=%s AND organization_id=%s",
                    (body.customer_id,user["organization_id"]))).fetchone()
                if customer is None:
                    raise HTTPException(status_code=404, detail="Customer not found")
            invoice_result = await connection.execute(
                """INSERT INTO sales_invoices
                   (organization_id,warehouse_id,customer_id,invoice_number,subtotal,discount,total,paid,notes)
                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id""",
                (user["organization_id"],body.warehouse_id,body.customer_id,body.invoice_number,
                 subtotal,body.discount,total,body.paid,body.notes))
            invoice_id = (await invoice_result.fetchone())[0]
            for index, line in enumerate(body.lines):
                product = await (await connection.execute(
                    """SELECT base_unit FROM products
                       WHERE id=%s AND organization_id=%s AND is_active FOR UPDATE""",
                    (line.product_id,user["organization_id"]))).fetchone()
                if product is None:
                    raise HTTPException(status_code=404, detail="A sales product was not found")
                if line.unit.strip().lower() != str(product[0]).lower():
                    raise HTTPException(status_code=422, detail="Sales unit must match product base unit")
                current = await (await connection.execute(
                    """SELECT COALESCE(SUM(quantity_delta),0) FROM stock_movements
                       WHERE organization_id=%s AND warehouse_id=%s AND product_id=%s""",
                    (user["organization_id"],body.warehouse_id,line.product_id))).fetchone()
                if Decimal(current[0]) < line.quantity:
                    raise HTTPException(status_code=409, detail="Insufficient stock for "+str(line.product_id))
                await connection.execute(
                    """INSERT INTO sales_lines
                       (organization_id,sales_invoice_id,product_id,quantity,unit,unit_price,line_total)
                       VALUES (%s,%s,%s,%s,%s,%s,%s)""",
                    (user["organization_id"],invoice_id,line.product_id,line.quantity,
                     line.unit,line.unit_price,line.line_total))
                await connection.execute(
                    """INSERT INTO stock_movements
                       (organization_id,warehouse_id,product_id,movement_type,quantity_delta,
                        unit,source_type,source_id,idempotency_key)
                       VALUES (%s,%s,%s,'sale',%s,%s,'sale',%s,%s)""",
                    (user["organization_id"],body.warehouse_id,line.product_id,-line.quantity,
                     product[0],invoice_id,"sale:"+str(invoice_id)+":"+str(index)))
            if body.paid > 0 and body.customer_id is not None:
                await connection.execute(
                    """INSERT INTO payments
                       (organization_id,party_type,party_id,invoice_type,invoice_id,amount,method)
                       VALUES (%s,'customer',%s,'sale',%s,%s,'unspecified')""",
                    (user["organization_id"],body.customer_id,invoice_id,body.paid))
            await connection.execute(
                """INSERT INTO audit_logs (organization_id,user_id,action,entity_type,entity_id,metadata)
                   VALUES (%s,%s,'sale.posted','sales_invoice',%s,%s::jsonb)""",
                (user["organization_id"],user["user_id"],invoice_id,
                 json.dumps({"invoice_number":body.invoice_number,"total":str(total)})))
    return {"id":str(invoice_id),"invoice_number":body.invoice_number,
            "subtotal":str(subtotal),"total":str(total),"paid":str(body.paid),
            "due":str(total-body.paid)}

@app.post("/sync/initial-snapshot", tags=["synchronization"])
async def import_initial_snapshot(body: InitialSnapshot, user=Depends(_writer)):
    """One-time legacy import. Current stock is imported as opening stock;
    historical invoices are archived without replaying their stock movements."""
    payload = body.model_dump(mode="json")
    payload_hash = hashlib.sha256(json.dumps(payload,sort_keys=True,separators=(",",":"),ensure_ascii=False,default=str).encode()).hexdigest()
    org_id = user["organization_id"]
    pool = _pool()
    async with pool.connection() as connection:
        async with connection.transaction():
            prior_device = await (await connection.execute(
                """SELECT device_id FROM sync_requests
                   WHERE organization_id=%s AND idempotency_key='initial-snapshot-v1'
                     AND result_json IS NOT NULL LIMIT 1""",
                (org_id,))).fetchone()
            if prior_device is not None and prior_device[0] != body.device_id:
                raise HTTPException(status_code=409,detail="This organization already received its initial import from another device")
            inserted = await (await connection.execute(
                """INSERT INTO sync_requests (organization_id,device_id,idempotency_key,payload_hash)
                   VALUES (%s,%s,%s,%s) ON CONFLICT (organization_id,device_id,idempotency_key)
                   DO NOTHING RETURNING id""",
                (org_id,body.device_id,body.idempotency_key,payload_hash))).fetchone()
            if inserted is None:
                prior = await (await connection.execute(
                    """SELECT payload_hash,result_json FROM sync_requests
                       WHERE organization_id=%s AND device_id=%s AND idempotency_key=%s FOR UPDATE""",
                    (org_id,body.device_id,body.idempotency_key))).fetchone()
                if prior is None or prior[0] != payload_hash:
                    raise HTTPException(status_code=409,detail="Snapshot key was already used with different data")
                if prior[1] is not None:
                    return {**prior[1],"already_imported":True}
                raise HTTPException(status_code=409,detail="Snapshot is being processed; retry shortly")

            warehouse_row = await (await connection.execute(
                "SELECT id FROM warehouses WHERE organization_id=%s AND is_active ORDER BY created_at LIMIT 1",
                (org_id,))).fetchone()
            if warehouse_row is None:
                raise HTTPException(status_code=409,detail="No active warehouse is configured")
            warehouse_id = warehouse_row[0]

            product_ids: dict[str, UUID] = {}
            product_by_name: dict[tuple[str,str], UUID] = {}
            supplier_ids: dict[str, UUID] = {}
            customer_ids: dict[str, UUID] = {}
            counts = {"products":0,"suppliers":0,"customers":0,"purchases":0,"sales":0,"opening_stock_items":0}
            for item in body.products:
                local_id = str(item.get("local_id","")).strip()
                name = str(item.get("name","")).strip()
                category_name = str(item.get("category","مواد البناء")).strip() or "مواد البناء"
                unit = str(item.get("unit","وحدة")).strip() or "وحدة"
                if not local_id or not name:
                    raise HTTPException(status_code=422,detail="Every snapshot product needs local_id and name")
                category = await (await connection.execute(
                    """INSERT INTO product_categories (organization_id,name) VALUES (%s,%s)
                       ON CONFLICT (organization_id,name) DO UPDATE SET name=EXCLUDED.name RETURNING id""",
                    (org_id,category_name))).fetchone()
                piece_weight = item.get("piece_weight_kg")
                diameter = item.get("rebar_diameter_mm")
                length = item.get("bar_length_m")
                tracking = "piece" if piece_weight or (diameter and length) else "quantity"
                product = await (await connection.execute(
                    """INSERT INTO products (organization_id,category_id,name,base_unit,tracking_mode,
                       piece_weight_kg,rebar_diameter_mm,bar_length_m,purchase_price,sale_price,minimum_stock)
                       VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id""",
                    (org_id,category[0],name,unit,tracking,piece_weight,diameter,length,
                     item.get("purchase_price",0),item.get("sale_price",0),item.get("minimum_stock",0)))).fetchone()
                product_ids[local_id] = product[0]
                product_by_name[(name.strip().casefold(),category_name.casefold())] = product[0]
                counts["products"] += 1
                quantity = Decimal(str(item.get("quantity",0)))
                if quantity < 0:
                    raise HTTPException(status_code=422,detail="Opening stock cannot be negative")
                if quantity > 0:
                    await connection.execute(
                        """INSERT INTO stock_movements
                           (organization_id,warehouse_id,product_id,movement_type,quantity_delta,
                            unit,source_type,idempotency_key)
                           VALUES (%s,%s,%s,'opening',%s,%s,'initial_snapshot',%s)""",
                        (org_id,warehouse_id,product[0],quantity,unit,
                         "snapshot:"+body.device_id+":stock:"+local_id))
                    counts["opening_stock_items"] += 1

            async def ensure_contact(kind: str, local_id: str, name: str, phone=None, address=None):
                table = "suppliers" if kind == "supplier" else "customers"
                mapping = supplier_ids if kind == "supplier" else customer_ids
                key = local_id or name.strip().casefold()
                if key in mapping:
                    return mapping[key]
                clean_name = name.strip() or ("مورد غير محدد" if kind=="supplier" else "زبون غير محدد")
                existing = await (await connection.execute(
                    f"SELECT id FROM {table} WHERE organization_id=%s AND lower(name)=lower(%s) ORDER BY created_at LIMIT 1",
                    (org_id,clean_name))).fetchone()
                if existing is not None:
                    mapping[key] = existing[0]
                    return existing[0]
                row = await (await connection.execute(
                    f"INSERT INTO {table} (organization_id,name,phone,address) VALUES (%s,%s,%s,%s) RETURNING id",
                    (org_id,clean_name,phone,address))).fetchone()
                mapping[key] = row[0]
                counts[kind+"s"] += 1
                return row[0]

            for item in body.suppliers:
                await ensure_contact("supplier",str(item.get("local_id","")),str(item.get("name","")),item.get("phone"),item.get("address"))
            for item in body.customers:
                await ensure_contact("customer",str(item.get("local_id","")),str(item.get("name","")),item.get("phone"),item.get("address"))

            async def resolve_product(local_id: str, name: str, category: str, unit: str):
                if local_id and local_id in product_ids:
                    return product_ids[local_id]
                key=(name.strip().casefold(),category.strip().casefold())
                if key in product_by_name:
                    return product_by_name[key]
                if not name.strip():
                    raise HTTPException(status_code=422,detail="Historical invoice line has no product name")
                cat = await (await connection.execute(
                    """INSERT INTO product_categories (organization_id,name) VALUES (%s,%s)
                       ON CONFLICT (organization_id,name) DO UPDATE SET name=EXCLUDED.name RETURNING id""",
                    (org_id,category.strip() or "مواد البناء"))).fetchone()
                row = await (await connection.execute(
                    """INSERT INTO products (organization_id,category_id,name,base_unit)
                       VALUES (%s,%s,%s,%s) RETURNING id""",
                    (org_id,cat[0],name.strip(),unit.strip() or "وحدة"))).fetchone()
                product_by_name[key]=row[0]
                return row[0]

            for index,item in enumerate(body.purchases):
                supplier_name=str(item.get("supplier","مورد غير محدد")).strip() or "مورد غير محدد"
                supplier_id=await ensure_contact("supplier","",supplier_name)
                local_product=str(item.get("product_local_id",""))
                product_name=str(item.get("product","")).strip()
                category=str(item.get("inventory_category",item.get("category","مواد البناء")))
                unit=str(item.get("stock_unit",item.get("input_unit","وحدة")))
                product_id=await resolve_product(local_product,product_name,category,unit)
                local_invoice=str(item.get("local_id",index))
                invoice_number=("MIG-PUR-"+local_invoice)[:80]
                entered=Decimal(str(item.get("input_quantity",item.get("quantity",0))))
                base=Decimal(str(item.get("quantity",entered)))
                price=Decimal(str(item.get("unit_price",item.get("stock_unit_price",0))))
                total=Decimal(str(item.get("total",entered*price)))
                paid=Decimal(str(item.get("paid",0)))
                discount=Decimal(str(item.get("discount",0)))
                invoice_total=max(Decimal("0"),total-discount)
                if entered<=0 or base<=0 or paid<0 or paid>invoice_total:
                    raise HTTPException(status_code=422,detail="Invalid historical purchase quantities or payment")
                date_text=str(item.get("date",""))[:10]
                invoice_date=date.fromisoformat(date_text) if len(date_text)==10 else date.today()
                invoice=await (await connection.execute(
                    """INSERT INTO purchase_invoices
                       (organization_id,warehouse_id,supplier_id,invoice_number,invoice_date,subtotal,discount,total,paid,notes)
                       VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id""",
                    (org_id,warehouse_id,supplier_id,invoice_number,invoice_date,total,discount,invoice_total,paid,
                     "Imported legacy invoice; stock is represented by opening snapshot."))).fetchone()
                await connection.execute(
                    """INSERT INTO purchase_lines
                       (organization_id,purchase_invoice_id,product_id,entered_quantity,entered_unit,base_quantity,unit_price,line_total,measured_weight_kg)
                       VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                    (org_id,invoice[0],product_id,entered,str(item.get("input_unit",unit)),base,price,total,item.get("weight_kg")))
                if paid>0:
                    await connection.execute(
                        """INSERT INTO payments (organization_id,party_type,party_id,invoice_type,invoice_id,amount,method)
                           VALUES (%s,'supplier',%s,'purchase',%s,%s,'legacy_import')""",
                        (org_id,supplier_id,invoice[0],paid))
                counts["purchases"]+=1

            for index,item in enumerate(body.sales):
                client_name=str(item.get("client","زبون نقدي")).strip() or "زبون نقدي"
                customer_id=None if client_name=="زبون نقدي" else await ensure_contact("customer","",client_name)
                local_invoice=str(item.get("local_id",index))
                invoice_number=("MIG-SAL-"+local_invoice)[:80]
                lines=item.get("items",[])
                subtotal=sum((Decimal(str(line.get("total",Decimal(str(line.get("quantity",0)))*Decimal(str(line.get("price",0)))))) for line in lines),Decimal("0"))
                total=Decimal(str(item.get("total",subtotal)))
                paid=Decimal(str(item.get("paid",0)))
                if not lines or total<0 or paid<0 or paid>total:
                    raise HTTPException(status_code=422,detail="Invalid historical sales invoice")
                sales_date_text=str(item.get("date",""))
                try:
                    sales_date=datetime.fromisoformat(sales_date_text.replace("Z","+00:00")) if sales_date_text else datetime.now(timezone.utc)
                except ValueError:
                    raise HTTPException(status_code=422,detail="Invalid historical sales invoice date")
                invoice=await (await connection.execute(
                    """INSERT INTO sales_invoices
                       (organization_id,warehouse_id,customer_id,invoice_number,invoice_date,subtotal,total,paid,notes)
                       VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id""",
                    (org_id,warehouse_id,customer_id,invoice_number,sales_date,subtotal,total,paid,
                     "Imported legacy invoice; stock is represented by opening snapshot."))).fetchone()
                for line in lines:
                    local_product=str(line.get("productId",""))
                    product_name=str(line.get("name","")).strip()
                    product_id=await resolve_product(local_product,product_name,"مواد البناء",str(line.get("unit","وحدة")))
                    quantity=Decimal(str(line.get("quantity",0)))
                    price=Decimal(str(line.get("price",0)))
                    line_total=Decimal(str(line.get("total",quantity*price)))
                    if quantity<=0 or price<0 or line_total<0:
                        raise HTTPException(status_code=422,detail="Invalid historical sales line")
                    await connection.execute(
                        """INSERT INTO sales_lines (organization_id,sales_invoice_id,product_id,quantity,unit,unit_price,line_total)
                           VALUES (%s,%s,%s,%s,%s,%s,%s)""",
                        (org_id,invoice[0],product_id,quantity,str(line.get("unit","وحدة")),price,line_total))
                if paid>0 and customer_id is not None:
                    await connection.execute(
                        """INSERT INTO payments (organization_id,party_type,party_id,invoice_type,invoice_id,amount,method)
                           VALUES (%s,'customer',%s,'sale',%s,%s,'legacy_import')""",
                        (org_id,customer_id,invoice[0],paid))
                counts["sales"]+=1

            result={"status":"imported","counts":counts,"device_id":body.device_id}
            await connection.execute(
                """UPDATE sync_requests SET result_json=%s::jsonb
                   WHERE organization_id=%s AND device_id=%s AND idempotency_key=%s""",
                (json.dumps(result),org_id,body.device_id,body.idempotency_key))
            return result

