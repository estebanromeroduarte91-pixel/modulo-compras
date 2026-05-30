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
