-- Adiciona categoria opcional ao lançamento (hoje só usada para marcar "imposto",
-- mas guardada como texto livre para permitir outras categorias no futuro).
ALTER TABLE public.financeiro ADD COLUMN IF NOT EXISTS categoria text DEFAULT NULL;
