-- Adiciona a lista editável de contas bancárias em app_config.
-- reserve_bancos já existia na tabela (sem uso até agora); "bancos" guarda
-- a lista completa de contas, e reserve_bancos guarda o subconjunto marcado
-- como reserva/caixinha. O app faz merge com os valores padrão se estiver vazio.

ALTER TABLE public.app_config ADD COLUMN IF NOT EXISTS bancos jsonb DEFAULT '[]'::jsonb;

UPDATE public.app_config
SET bancos = '["Nubank PF","Nubank Caixinha Roxa","Nubank Caixinha","Caixa PJ","Caixa PF","Caixa Poupança"]'::jsonb
WHERE id = 1 AND (bancos IS NULL OR bancos = '[]'::jsonb);

UPDATE public.app_config
SET reserve_bancos = '["Nubank Caixinha Roxa","Nubank Caixinha"]'::jsonb
WHERE id = 1 AND (reserve_bancos IS NULL OR reserve_bancos = '[]'::jsonb);
