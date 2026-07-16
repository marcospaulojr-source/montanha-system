-- Habilita o Supabase Realtime (atualização automática) nas tabelas do app.
-- Idempotente: pula tabelas que já estejam na publicação.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['financeiro','videos','clients','saldos_iniciais','propostas','app_config']
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename=t
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
END $$;
