CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'DZD',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    display_name TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS organization_members (
    organization_id UUID NOT NULL REFERENCES organizations(id),
    user_id UUID NOT NULL REFERENCES users(id),
    role TEXT NOT NULL CHECK (role IN ('owner', 'admin', 'manager', 'cashier', 'viewer')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (organization_id, user_id)
);

CREATE TABLE IF NOT EXISTS warehouses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    name TEXT NOT NULL,
    address TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (organization_id, name),
    UNIQUE (id, organization_id)
);

CREATE TABLE IF NOT EXISTS product_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    name TEXT NOT NULL,
    parent_id UUID REFERENCES product_categories(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (organization_id, name),
    UNIQUE (id, organization_id)
);

CREATE TABLE IF NOT EXISTS products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    category_id UUID,
    sku TEXT,
    name TEXT NOT NULL,
    base_unit TEXT NOT NULL,
    tracking_mode TEXT NOT NULL DEFAULT 'quantity'
        CHECK (tracking_mode IN ('quantity', 'weight', 'piece')),
    piece_weight_kg NUMERIC(18, 6),
    rebar_diameter_mm NUMERIC(8, 3),
    bar_length_m NUMERIC(8, 3),
    purchase_price NUMERIC(18, 2) NOT NULL DEFAULT 0 CHECK (purchase_price >= 0),
    sale_price NUMERIC(18, 2) NOT NULL DEFAULT 0 CHECK (sale_price >= 0),
    minimum_stock NUMERIC(18, 3) NOT NULL DEFAULT 0 CHECK (minimum_stock >= 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (category_id, organization_id)
        REFERENCES product_categories(id, organization_id),
    UNIQUE (organization_id, sku),
    UNIQUE (id, organization_id),
    CHECK (piece_weight_kg IS NULL OR piece_weight_kg > 0),
    CHECK (rebar_diameter_mm IS NULL OR rebar_diameter_mm > 0),
    CHECK (bar_length_m IS NULL OR bar_length_m > 0)
);

CREATE TABLE IF NOT EXISTS suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    name TEXT NOT NULL,
    phone TEXT,
    address TEXT,
    opening_balance NUMERIC(18, 2) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (id, organization_id)
);

CREATE TABLE IF NOT EXISTS customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    name TEXT NOT NULL,
    phone TEXT,
    address TEXT,
    opening_balance NUMERIC(18, 2) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (id, organization_id)
);

CREATE TABLE IF NOT EXISTS purchase_invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    warehouse_id UUID NOT NULL,
    supplier_id UUID NOT NULL,
    invoice_number TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'posted'
        CHECK (status IN ('draft', 'posted', 'cancelled')),
    invoice_date DATE NOT NULL DEFAULT CURRENT_DATE,
    subtotal NUMERIC(18, 2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
    discount NUMERIC(18, 2) NOT NULL DEFAULT 0 CHECK (discount >= 0),
    total NUMERIC(18, 2) NOT NULL DEFAULT 0 CHECK (total >= 0),
    paid NUMERIC(18, 2) NOT NULL DEFAULT 0 CHECK (paid >= 0 AND paid <= total),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (warehouse_id, organization_id)
        REFERENCES warehouses(id, organization_id),
    FOREIGN KEY (supplier_id, organization_id)
        REFERENCES suppliers(id, organization_id),
    UNIQUE (organization_id, invoice_number),
    UNIQUE (id, organization_id)
);

CREATE TABLE IF NOT EXISTS purchase_lines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    purchase_invoice_id UUID NOT NULL,
    product_id UUID NOT NULL,
    entered_quantity NUMERIC(18, 3) NOT NULL CHECK (entered_quantity > 0),
    entered_unit TEXT NOT NULL,
    base_quantity NUMERIC(18, 3) NOT NULL CHECK (base_quantity > 0),
    unit_price NUMERIC(18, 4) NOT NULL CHECK (unit_price >= 0),
    line_total NUMERIC(18, 2) NOT NULL CHECK (line_total >= 0),
    measured_weight_kg NUMERIC(18, 3),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (purchase_invoice_id, organization_id)
        REFERENCES purchase_invoices(id, organization_id),
    FOREIGN KEY (product_id, organization_id)
        REFERENCES products(id, organization_id)
);

CREATE TABLE IF NOT EXISTS sales_invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    warehouse_id UUID NOT NULL,
    customer_id UUID,
    invoice_number TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'posted'
        CHECK (status IN ('draft', 'posted', 'cancelled')),
    invoice_date TIMESTAMPTZ NOT NULL DEFAULT now(),
    subtotal NUMERIC(18, 2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
    discount NUMERIC(18, 2) NOT NULL DEFAULT 0 CHECK (discount >= 0),
    total NUMERIC(18, 2) NOT NULL DEFAULT 0 CHECK (total >= 0),
    paid NUMERIC(18, 2) NOT NULL DEFAULT 0 CHECK (paid >= 0 AND paid <= total),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (warehouse_id, organization_id)
        REFERENCES warehouses(id, organization_id),
    FOREIGN KEY (customer_id, organization_id)
        REFERENCES customers(id, organization_id),
    UNIQUE (organization_id, invoice_number),
    UNIQUE (id, organization_id)
);

CREATE TABLE IF NOT EXISTS sales_lines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    sales_invoice_id UUID NOT NULL,
    product_id UUID NOT NULL,
    quantity NUMERIC(18, 3) NOT NULL CHECK (quantity > 0),
    unit TEXT NOT NULL,
    unit_price NUMERIC(18, 4) NOT NULL CHECK (unit_price >= 0),
    line_total NUMERIC(18, 2) NOT NULL CHECK (line_total >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (sales_invoice_id, organization_id)
        REFERENCES sales_invoices(id, organization_id),
    FOREIGN KEY (product_id, organization_id)
        REFERENCES products(id, organization_id)
);

CREATE TABLE IF NOT EXISTS stock_movements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    warehouse_id UUID NOT NULL,
    product_id UUID NOT NULL,
    movement_type TEXT NOT NULL CHECK (movement_type IN
        ('opening', 'purchase', 'sale', 'purchase_return', 'sale_return', 'adjustment', 'transfer_in', 'transfer_out')),
    quantity_delta NUMERIC(18, 3) NOT NULL CHECK (quantity_delta <> 0),
    unit TEXT NOT NULL,
    source_type TEXT,
    source_id UUID,
    idempotency_key TEXT NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (warehouse_id, organization_id)
        REFERENCES warehouses(id, organization_id),
    FOREIGN KEY (product_id, organization_id)
        REFERENCES products(id, organization_id),
    UNIQUE (organization_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_stock_movements_product_date
    ON stock_movements (organization_id, product_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_movements_warehouse_product
    ON stock_movements (warehouse_id, product_id);

CREATE TABLE IF NOT EXISTS payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    party_type TEXT NOT NULL CHECK (party_type IN ('supplier', 'customer')),
    party_id UUID NOT NULL,
    invoice_type TEXT CHECK (invoice_type IN ('purchase', 'sale')),
    invoice_id UUID,
    amount NUMERIC(18, 2) NOT NULL CHECK (amount > 0),
    method TEXT NOT NULL,
    reference TEXT,
    paid_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payments_party_date
    ON payments (organization_id, party_type, party_id, paid_at DESC);

CREATE TABLE IF NOT EXISTS sync_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    device_id TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    payload_hash TEXT NOT NULL,
    result_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (organization_id, device_id, idempotency_key)
);

CREATE TABLE IF NOT EXISTS audit_logs (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES organizations(id),
    user_id UUID REFERENCES users(id),
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id UUID,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_org_date
    ON audit_logs (organization_id, created_at DESC);

INSERT INTO schema_migrations (version)
VALUES ('001_initial_schema')
ON CONFLICT (version) DO NOTHING;
