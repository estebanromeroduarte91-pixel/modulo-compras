-- Ejecutar en Supabase → SQL Editor

-- 1. Perfiles de usuarios (staff)
CREATE TABLE IF NOT EXISTS user_profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  empresa_id UUID NOT NULL,
  nombre TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'tecnico' CHECK (role IN ('admin', 'tecnico', 'vendedor')),
  activo BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Invitaciones pendientes
CREATE TABLE IF NOT EXISTS pending_invites (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  empresa_id UUID NOT NULL,
  email TEXT NOT NULL,
  nombre TEXT NOT NULL DEFAULT '',
  role TEXT NOT NULL DEFAULT 'tecnico',
  token TEXT NOT NULL UNIQUE,
  used BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Permisos (RLS) — permitir acceso a usuarios autenticados
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_all" ON user_profiles FOR ALL TO authenticated USING (true) WITH CHECK (true);

ALTER TABLE pending_invites ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_all" ON pending_invites FOR ALL TO authenticated USING (true) WITH CHECK (true);
-- También permitir lectura anónima de invitaciones (para que el usuario pueda ver su invitación antes de registrarse)
CREATE POLICY "anon_read" ON pending_invites FOR SELECT TO anon USING (true);

-- 4. Permitir que usuarios de staff lean su empresa (ejecutar en Supabase → SQL Editor)
-- (Si la tabla empresas ya tiene RLS, agregar esta policy)
ALTER TABLE empresas ENABLE ROW LEVEL SECURITY;
-- Eliminar policy anterior si existe
DROP POLICY IF EXISTS "owner_all" ON empresas;
DROP POLICY IF EXISTS "staff_read" ON empresas;
-- Propietario puede hacer todo
CREATE POLICY "owner_all" ON empresas FOR ALL TO authenticated USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());
-- Staff puede leer su empresa
CREATE POLICY "staff_read" ON empresas FOR SELECT TO authenticated
  USING (id IN (SELECT empresa_id FROM user_profiles WHERE id = auth.uid()));
