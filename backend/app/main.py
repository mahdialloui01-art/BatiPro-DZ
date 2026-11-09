import os
from contextlib import asynccontextmanager
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from uuid import UUID
import base64
import hashlib
import hmac
import json
import secrets

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


def _current_user(authorization: str | None = Header(default=None)):
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
        return {"user_id": payload["sub"], "organization_id": payload["org"]}
    except (ValueError, KeyError, TypeError, json.JSONDecodeError):
        raise HTTPException(status_code=401, detail="Invalid or expired access token")


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
async def create_product(body: ProductCreate, user=Depends(_current_user)):
    if body.tracking_mode == "piece" and body.piece_weight_kg is None:
        raise HTTPException(status_code=422, detail="piece_weight_kg is required for piece-tracked products")
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
async def adjust_stock(body: StockAdjustment, user=Depends(_current_user)):
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
async def create_supplier(body: ContactCreate, user=Depends(_current_user)):
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
async def create_customer(body: ContactCreate, user=Depends(_current_user)):
    async with _pool().connection() as connection:
        row = await connection.execute(
            "INSERT INTO customers (organization_id,name,phone,address) VALUES (%s,%s,%s,%s) RETURNING id",
            (user["organization_id"],body.name,body.phone,body.address))
        customer_id = (await row.fetchone())[0]
    return {"id":str(customer_id),"name":body.name}


@app.post("/purchases", status_code=status.HTTP_201_CREATED, tags=["purchases"])
async def create_purchase(body: PurchaseCreate, user=Depends(_current_user)):
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
                    """SELECT base_unit FROM products
                       WHERE id=%s AND organization_id=%s AND is_active FOR UPDATE""",
                    (line.product_id,user["organization_id"]))).fetchone()
                if product is None:
                    raise HTTPException(status_code=404, detail="A purchase product was not found")
                await connection.execute(
                    """INSERT INTO purchase_lines
                       (organization_id,purchase_invoice_id,product_id,entered_quantity,entered_unit,
                        base_quantity,unit_price,line_total,measured_weight_kg)
                       VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                    (user["organization_id"],invoice_id,line.product_id,line.entered_quantity,
                     line.entered_unit,line.base_quantity,line.unit_price,line.line_total,
                     line.measured_weight_kg))
                await connection.execute(
                    """INSERT INTO stock_movements
                       (organization_id,warehouse_id,product_id,movement_type,quantity_delta,
                        unit,source_type,source_id,idempotency_key)
                       VALUES (%s,%s,%s,'purchase',%s,%s,'purchase',%s,%s)""",
                    (user["organization_id"],body.warehouse_id,line.product_id,line.base_quantity,
                     product[0],invoice_id,"purchase:"+str(invoice_id)+":"+str(index)))
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
async def create_sale(body: SaleCreate, user=Depends(_current_user)):
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

