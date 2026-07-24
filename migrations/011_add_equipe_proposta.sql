-- Lista de integrantes da equipe alocados na proposta (ex: "Diretor de
-- imagens", "Cinegrafista", "Ajudante").
ALTER TABLE public.propostas ADD COLUMN IF NOT EXISTS equipe jsonb DEFAULT '[]'::jsonb NOT NULL;
