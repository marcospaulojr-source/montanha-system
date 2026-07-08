# Migrations

Este projeto não usa uma ferramenta formal de migrations — as mudanças de schema no Supabase (Postgres) são aplicadas diretamente via SQL, direto no servidor. Esta pasta existe só para manter um **histórico** dessas mudanças, caso seja necessário reconstruir o banco do zero um dia.

- `000_schema_snapshot_2026-07-08.sql` — retrato completo do schema das tabelas da aplicação (`clients`, `videos`, `financeiro`, `saldos_iniciais`, `propostas`, `profiles`, `app_config`), incluindo colunas e políticas de RLS, tirado em 08/07/2026.

A partir daqui, toda vez que um novo script SQL for aplicado no banco (nova coluna, nova tabela, nova política), ele deve ser salvo aqui como um arquivo numerado (`001_descricao.sql`, `002_descricao.sql`, ...) antes ou logo depois de ser executado.
