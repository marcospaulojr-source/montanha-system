-- Marca lançamentos criados automaticamente pelo "Lançar por voz" (sem tela de
-- confirmação), pra aparecerem destacados no financeiro até o usuário conferir
-- se a IA interpretou certo.
ALTER TABLE public.financeiro ADD COLUMN IF NOT EXISTS origem_voz boolean DEFAULT false;

UPDATE public.financeiro SET origem_voz=false WHERE origem_voz IS NULL;
