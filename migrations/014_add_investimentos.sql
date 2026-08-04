-- Rastreamento de investimentos (ex: cripto no Nubank), separado do
-- fluxo de caixa comum do financeiro. valor_atual é atualizado
-- manualmente pelo usuário; o rendimento é calculado no cliente
-- (valor_atual - valor_investido).
CREATE TABLE public.investimentos (
    id text PRIMARY KEY,
    ativo text DEFAULT ''::text NOT NULL,
    data date,
    quantidade numeric DEFAULT 0,
    valor_investido numeric DEFAULT 0,
    valor_atual numeric DEFAULT 0,
    conta text DEFAULT ''::text,
    observacoes text DEFAULT ''::text,
    created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE public.investimentos ENABLE ROW LEVEL SECURITY;

CREATE POLICY authenticated_all_investimentos ON public.investimentos
  USING ((auth.role() = 'authenticated'::text))
  WITH CHECK ((auth.role() = 'authenticated'::text));
