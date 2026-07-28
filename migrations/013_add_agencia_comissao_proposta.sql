-- Comissão de agência intermediária (ex: Fábrica de Ideias) + custo de nota
-- fiscal, embutidos no valor final da proposta via gross-up:
--   valor_final = liquido / (1 - comissao_pct - nota_pct)
-- Ambos os percentuais incidem sobre o valor final, não sobre o líquido,
-- de forma que o valor que sobra pro produtor seja exatamente o líquido.
ALTER TABLE public.propostas ADD COLUMN IF NOT EXISTS agencia_ativa boolean DEFAULT false NOT NULL;
ALTER TABLE public.propostas ADD COLUMN IF NOT EXISTS agencia_comissao_perc numeric DEFAULT 15;
ALTER TABLE public.propostas ADD COLUMN IF NOT EXISTS agencia_nf_perc numeric DEFAULT 6;
