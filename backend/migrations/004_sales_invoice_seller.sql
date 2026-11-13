ALTER TABLE sales_invoices
    ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES users(id);

CREATE INDEX IF NOT EXISTS sales_invoices_created_by_idx
    ON sales_invoices (organization_id, created_by, invoice_date DESC);
