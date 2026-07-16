-- Adiciona a hora do lançamento (opcional), exibida junto com a data na lista.
ALTER TABLE public.financeiro ADD COLUMN IF NOT EXISTS hora text DEFAULT NULL;
