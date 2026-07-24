-- Permite definir o investimento da proposta como um valor fixo digitado
-- direto, sem precisar preencher quantidade/valor unitário de cada item.
-- Quando preenchido, esse valor manda e ignora o cálculo por itens.
ALTER TABLE public.propostas ADD COLUMN IF NOT EXISTS investimento_manual numeric;
