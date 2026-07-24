-- Propostas passam a ter itens de serviço/equipamento com quantidade e valor
-- unitário (antes eram só listas de texto), além de escopo (checklist "o que
-- está incluso"), número da proposta, desconto/imposto em % e condições de
-- prazo/pagamento. O total (investimento) passa a ser calculado a partir dos
-- itens, mas continua sendo salvo pronto pra facilitar listagens.
ALTER TABLE public.propostas ADD COLUMN IF NOT EXISTS numero text DEFAULT '' NOT NULL;
ALTER TABLE public.propostas ADD COLUMN IF NOT EXISTS escopo jsonb DEFAULT '[]'::jsonb NOT NULL;
ALTER TABLE public.propostas ADD COLUMN IF NOT EXISTS desconto numeric DEFAULT 0 NOT NULL;
ALTER TABLE public.propostas ADD COLUMN IF NOT EXISTS imposto numeric DEFAULT 0 NOT NULL;
ALTER TABLE public.propostas ADD COLUMN IF NOT EXISTS prazo text DEFAULT '' NOT NULL;
ALTER TABLE public.propostas ADD COLUMN IF NOT EXISTS pagamento text DEFAULT '' NOT NULL;

-- Propostas antigas têm servicos/equipamentos como array de texto simples
-- (ex: ["Gravação","Edição"]). Converte pra array de objetos {desc,qtd,valor}
-- mantendo o texto e valor 0, pra não quebrar a tela nova.
UPDATE public.propostas
SET servicos = (
  SELECT jsonb_agg(jsonb_build_object('desc', elem, 'qtd', 1, 'valor', 0))
  FROM jsonb_array_elements_text(servicos) AS elem
)
WHERE jsonb_typeof(servicos) = 'array'
  AND jsonb_array_length(servicos) > 0
  AND jsonb_typeof(servicos->0) = 'string';

UPDATE public.propostas
SET equipamentos = (
  SELECT jsonb_agg(jsonb_build_object('desc', elem, 'qtd', 1, 'valor', 0))
  FROM jsonb_array_elements_text(equipamentos) AS elem
)
WHERE jsonb_typeof(equipamentos) = 'array'
  AND jsonb_array_length(equipamentos) > 0
  AND jsonb_typeof(equipamentos->0) = 'string';
