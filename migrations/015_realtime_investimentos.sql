-- Coloca a tabela investimentos (criada na 014) na publicação do Realtime, que a 003 habilitou
-- só nas tabelas que existiam na época. Idempotente.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='investimentos'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.investimentos;
  END IF;
END $$;
