-- Status da proposta: acompanha se ainda é rascunho, já foi enviada pro
-- cliente, foi aceita ou recusada.
ALTER TABLE public.propostas ADD COLUMN IF NOT EXISTS status text DEFAULT 'rascunho' NOT NULL;
