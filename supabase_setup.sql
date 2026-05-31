-- ============================================================
-- TallerPro ERP — Supabase Schema: Productos + Inventario
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ============================================================

-- 1. TABLA PRINCIPAL DE PRODUCTOS
-- --------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.productos (
  id                    TEXT        PRIMARY KEY,          -- mismo uid que en localStorage
  empresa_id            TEXT        NOT NULL,             -- para multi-tenant (por ahora usa 'default')
  nombre                TEXT        NOT NULL,
  sku                   TEXT,
  unidad                TEXT        DEFAULT 'unidad',
  precio_compra         NUMERIC(12,2) DEFAULT 0,
  precio_venta          NUMERIC(12,2) DEFAULT 0,
  stock                 INTEGER     DEFAULT 0,
  stock_min             INTEGER     DEFAULT 0,
  categoria             TEXT,
  subcategoria          TEXT,
  enlace                TEXT,                             -- grupo/enlace interno ERP
  descripcion           TEXT,
  -- Campos WooCommerce
  woocommerce_product_id BIGINT,                          -- ID del producto en WooCommerce
  woo_sku               TEXT,                            -- SKU en WooCommerce (si difiere)
  woo_sync_enabled      BOOLEAN     DEFAULT false,        -- activar sincronización con WC
  woo_last_sync         TIMESTAMPTZ,                     -- última vez que se sincronizó
  -- Metadatos
  activo                BOOLEAN     DEFAULT true,
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW()
);

-- Índices útiles
CREATE INDEX IF NOT EXISTS idx_productos_empresa ON public.productos(empresa_id);
CREATE INDEX IF NOT EXISTS idx_productos_sku ON public.productos(sku) WHERE sku IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_productos_woo ON public.productos(woocommerce_product_id) WHERE woocommerce_product_id IS NOT NULL;

-- 2. TRIGGER: actualizar updated_at automáticamente
-- --------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_productos_updated_at
  BEFORE UPDATE ON public.productos
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 3. ROW LEVEL SECURITY (RLS)
-- --------------------------------------------------------
-- Habilitar RLS (cuando tengas Auth de Supabase activo)
ALTER TABLE public.productos ENABLE ROW LEVEL SECURITY;

-- Por ahora: política abierta para que puedas probar sin Auth
-- CUANDO TENGAS AUTH: reemplaza esta política por una que use empresa_id
CREATE POLICY "acceso_total_temporal"
  ON public.productos
  FOR ALL
  USING (true)
  WITH CHECK (true);

-- 4. TABLA DE LOG DE MOVIMIENTOS DE STOCK (opcional pero recomendado)
-- --------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.movimientos_stock (
  id            BIGSERIAL   PRIMARY KEY,
  empresa_id    TEXT        NOT NULL,
  producto_id   TEXT        NOT NULL REFERENCES public.productos(id) ON DELETE CASCADE,
  tipo          TEXT        NOT NULL CHECK (tipo IN ('venta','compra','ajuste','woocommerce','devolucion')),
  cantidad      INTEGER     NOT NULL,                     -- negativo = salida, positivo = entrada
  stock_antes   INTEGER     NOT NULL,
  stock_despues INTEGER     NOT NULL,
  referencia    TEXT,                                     -- ej: "Venta #123" o "Pedido WC #456"
  notas         TEXT,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mov_producto ON public.movimientos_stock(producto_id);
CREATE INDEX IF NOT EXISTS idx_mov_empresa ON public.movimientos_stock(empresa_id);

ALTER TABLE public.movimientos_stock ENABLE ROW LEVEL SECURITY;
CREATE POLICY "acceso_total_temporal_mov"
  ON public.movimientos_stock
  FOR ALL USING (true) WITH CHECK (true);

-- ============================================================
-- VERIFICACIÓN: corre esto después para confirmar que se creó
-- ============================================================
-- SELECT table_name FROM information_schema.tables
-- WHERE table_schema = 'public'
-- ORDER BY table_name;
