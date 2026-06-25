-- ============================================================
-- TallerPro ERP — Políticas de Storage para bucket erp-assets
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- Ejecutar CADA VEZ que el bucket se recree o las políticas se pierdan
-- ============================================================

-- 1. Crear el bucket si no existe (poner public = true para URLs públicas)
INSERT INTO storage.buckets (id, name, public)
VALUES ('erp-assets', 'erp-assets', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- 2. Eliminar políticas anteriores para aplicar limpias
DROP POLICY IF EXISTS "erp-assets-insert-anon"  ON storage.objects;
DROP POLICY IF EXISTS "erp-assets-select-anon"  ON storage.objects;
DROP POLICY IF EXISTS "erp-assets-update-anon"  ON storage.objects;
DROP POLICY IF EXISTS "erp-assets-delete-anon"  ON storage.objects;

-- 3. Permitir subida de fotos desde el iPhone (usuario anónimo, sin login)
CREATE POLICY "erp-assets-insert-anon"
ON storage.objects FOR INSERT
TO anon
WITH CHECK (bucket_id = 'erp-assets');

-- 4. Permitir lectura pública de fotos (para mostrarlas en el ERP)
CREATE POLICY "erp-assets-select-anon"
ON storage.objects FOR SELECT
TO anon
USING (bucket_id = 'erp-assets');

-- 5. Permitir al usuario autenticado subir y leer (desde el ERP con sesión)
CREATE POLICY "erp-assets-insert-auth"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'erp-assets');

CREATE POLICY "erp-assets-select-auth"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'erp-assets');

-- 6. Permitir que usuarios anónimos guarden fotos en erp_data
--    (necesario para que foto-orden.html pueda escribir la URL de la foto)
DROP POLICY IF EXISTS "erp-data-upsert-anon" ON public.erp_data;
DROP POLICY IF EXISTS "erp-data-insert-anon" ON public.erp_data;

CREATE POLICY "erp-data-upsert-anon"
ON public.erp_data FOR UPDATE TO anon
USING (true)
WITH CHECK (true);

CREATE POLICY "erp-data-insert-anon"
ON public.erp_data FOR INSERT TO anon
WITH CHECK (true);

-- ============================================================
-- Verificar que quedó bien:
-- SELECT * FROM storage.buckets WHERE id = 'erp-assets';
-- SELECT policyname, cmd, roles FROM pg_policies WHERE tablename = 'objects' AND schemaname = 'storage';
-- ============================================================
