-- PLA Dashboard initial schema (reference; applied via Migration_v1)

CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS import_jobs (
  id TEXT PRIMARY KEY,
  source_kind TEXT NOT NULL,
  file_name TEXT NOT NULL,
  file_path_bookmark BLOB,
  file_checksum TEXT,
  imported_at TEXT NOT NULL,
  status TEXT NOT NULL,
  total_rows INTEGER DEFAULT 0,
  valid_rows INTEGER DEFAULT 0,
  invalid_rows INTEGER DEFAULT 0,
  warning_rows INTEGER DEFAULT 0,
  schema_version INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS products (
  product_id TEXT PRIMARY KEY,
  title TEXT,
  canonical_link TEXT,
  image_url TEXT,
  custom_label_0 TEXT,
  custom_label_1 TEXT,
  custom_label_2 TEXT,
  custom_label_3 TEXT,
  custom_label_4 TEXT,
  lsin TEXT,
  first_seen_at TEXT,
  last_seen_at TEXT,
  updated_from_import_id TEXT
);

CREATE TABLE IF NOT EXISTS merchant_items (
  import_id TEXT NOT NULL,
  item_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  variant_id TEXT,
  title TEXT,
  canonical_link TEXT,
  image_url TEXT,
  custom_label_0 TEXT,
  custom_label_1 TEXT,
  custom_label_2 TEXT,
  custom_label_3 TEXT,
  custom_label_4 TEXT,
  PRIMARY KEY (import_id, item_id)
);

CREATE TABLE IF NOT EXISTS sales_daily (
  date TEXT NOT NULL,
  lsin TEXT NOT NULL,
  product_id TEXT,
  gross_sales_cents INTEGER NOT NULL,
  import_id TEXT NOT NULL,
  PRIMARY KEY (date, lsin, import_id)
);

CREATE TABLE IF NOT EXISTS ads_product_daily (
  date TEXT NOT NULL,
  item_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  variant_id TEXT,
  campaign TEXT NOT NULL,
  currency_code TEXT NOT NULL,
  cost_micros INTEGER NOT NULL,
  impressions INTEGER NOT NULL,
  clicks INTEGER NOT NULL,
  conversions REAL NOT NULL,
  conversion_value_cents INTEGER NOT NULL,
  import_id TEXT NOT NULL,
  PRIMARY KEY (date, item_id, campaign, currency_code, import_id)
);

CREATE TABLE IF NOT EXISTS product_weekly_metrics (
  product_id TEXT NOT NULL,
  week_start TEXT NOT NULL,
  cost_cents INTEGER NOT NULL,
  impressions INTEGER NOT NULL,
  clicks INTEGER NOT NULL,
  conversions REAL NOT NULL,
  conversion_value_cents INTEGER NOT NULL,
  gross_sales_cents INTEGER NOT NULL,
  roi REAL,
  cpa_cents INTEGER,
  cpc_cents INTEGER,
  cvr REAL,
  aos REAL,
  warning_label TEXT,
  PRIMARY KEY (product_id, week_start)
);

CREATE VIRTUAL TABLE IF NOT EXISTS product_search USING fts5(
  product_id,
  title,
  canonical_link,
  custom_label_0,
  custom_label_1,
  custom_label_2,
  custom_label_3,
  custom_label_4
);

CREATE INDEX IF NOT EXISTS idx_products_lsin ON products(lsin);
CREATE INDEX IF NOT EXISTS idx_products_label0 ON products(custom_label_0);
CREATE INDEX IF NOT EXISTS idx_products_label1 ON products(custom_label_1);
CREATE INDEX IF NOT EXISTS idx_products_label2 ON products(custom_label_2);
CREATE INDEX IF NOT EXISTS idx_products_label3 ON products(custom_label_3);
CREATE INDEX IF NOT EXISTS idx_products_label4 ON products(custom_label_4);
CREATE INDEX IF NOT EXISTS idx_merchant_product ON merchant_items(product_id);
CREATE INDEX IF NOT EXISTS idx_merchant_item ON merchant_items(item_id);
CREATE INDEX IF NOT EXISTS idx_sales_product_date ON sales_daily(product_id, date);
CREATE INDEX IF NOT EXISTS idx_sales_lsin_date ON sales_daily(lsin, date);
CREATE INDEX IF NOT EXISTS idx_ads_product_date ON ads_product_daily(product_id, date);
CREATE INDEX IF NOT EXISTS idx_ads_item_date ON ads_product_daily(item_id, date);
CREATE INDEX IF NOT EXISTS idx_ads_campaign_date ON ads_product_daily(campaign, date);
CREATE INDEX IF NOT EXISTS idx_weekly_week_cost ON product_weekly_metrics(week_start, cost_cents DESC);
CREATE INDEX IF NOT EXISTS idx_weekly_week_roi ON product_weekly_metrics(week_start, roi DESC);
CREATE INDEX IF NOT EXISTS idx_weekly_product ON product_weekly_metrics(product_id);
