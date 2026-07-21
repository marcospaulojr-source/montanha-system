-- Adiciona a "natureza" do lançamento (empresa ou pessoal), pra permitir separar
-- entradas/saídas pessoais das da empresa mesmo estando tudo no mesmo saldo.
-- Default 'empresa' pra não alterar o comportamento de nenhum lançamento já
-- existente nem dos relatórios/saldos atuais — é só uma marcação extra.
ALTER TABLE public.financeiro ADD COLUMN IF NOT EXISTS natureza text DEFAULT 'empresa';

UPDATE public.financeiro SET natureza='empresa' WHERE natureza IS NULL;
