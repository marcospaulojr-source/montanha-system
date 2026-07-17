-- Adiciona a hora do corte do saldo inicial/ajuste de saldo, para permitir
-- comparar data+hora (e não só a data) ao decidir se um lançamento já estava
-- refletido no saldo informado ou se deve somar em cima dele.
ALTER TABLE public.saldos_iniciais ADD COLUMN IF NOT EXISTS hora text DEFAULT NULL;
