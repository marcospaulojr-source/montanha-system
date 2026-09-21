# Documentação técnica — Montanha System

> Documento gerado para permitir a migração do desenvolvimento deste projeto para o Claude Code (ou qualquer outro ambiente/dev novo assumindo o projeto do zero). Reflete o estado do código em 2026-09-13, analisado diretamente a partir dos arquivos-fonte, migrations SQL e histórico do git — não é uma cópia de documentação pré-existente (o projeto não tinha nenhuma).

## Sumário

1. [Visão geral](#1-visão-geral)
2. [Arquitetura geral](#2-arquitetura-geral)
3. [Estrutura de pastas e arquivos](#3-estrutura-de-pastas-e-arquivos)
4. [Banco de dados](#4-banco-de-dados)
5. [Autenticação e controle de acesso](#5-autenticação-e-controle-de-acesso)
6. [Módulos funcionais](#6-módulos-funcionais)
7. [Dependências externas](#7-dependências-externas)
8. [Variáveis de ambiente e configuração](#8-variáveis-de-ambiente-e-configuração)
9. [Decisões de arquitetura e motivos](#9-decisões-de-arquitetura-e-motivos)
10. [Pontos de atenção, limitações e melhorias pendentes](#10-pontos-de-atenção-limitações-e-melhorias-pendentes)

---

## 1. Visão geral

**Montanha System** (nome do repositório: `montanha-system`) é o sistema interno de gestão da Montanha Filmes (produtora de vídeo). É ao mesmo tempo:

- Um **CRM/pipeline de produção** para acompanhar vídeos em produção para múltiplos clientes, do agendamento até a publicação (visão "Kanban" + calendário editorial).
- Um **sistema financeiro** (entradas/saídas, saldo por conta bancária, separação entre gasto pessoal e da empresa, impostos, investimentos).
- Um **gerador de propostas comerciais** (orçamentos) para os clientes da produtora, com cálculo automático de valores, PDF e envio por e-mail.

É um sistema de uso interno, para poucos usuários de confiança (a própria equipe da Montanha Filmes), não um produto SaaS multi-tenant para terceiros.

**Repositório:** `https://github.com/marcospaulojr-source/montanha-system` (branch única `main`).

---

## 2. Arquitetura geral

### 2.1. Resumo em uma frase

Uma **SPA "vanilla" sem build step**, num único arquivo HTML de ~2.765 linhas (~266 KB), que fala diretamente com um projeto **Supabase** (Postgres + Auth + Realtime) via SDK JS, mais um **Cloudflare Worker** isolado que serve de proxy seguro para a API da Anthropic (Claude) em duas features de IA (leitura de extrato bancário por foto e "lançar por voz").

```
┌─────────────────────────────┐        ┌──────────────────────────────┐
│  Navegador (index.html)     │        │  Cloudflare Worker            │
│  HTML + CSS + JS (vanilla)  │──POST─▶│  montanha-analisar-extrato    │──▶ Anthropic API
│  servido por nginx (Docker) │        │  (worker.js, sem estado)      │    (claude-sonnet-5)
└──────────────┬───────────────┘        └──────────────────────────────┘
               │ supabase-js (REST/PostgREST + Realtime + Auth)
               ▼
     ┌───────────────────────┐
     │  Supabase Cloud        │  Postgres + RLS + Auth + Realtime
     │  projeto "montanha-    │  (compartilhado com cifras-app por
     │  system"                │   prefixo de tabela, ver memória)
     └───────────────────────┘
```

Não existe backend próprio (API REST/GraphQL escrita pela equipe) — a aplicação é "BaaS-first": o client fala direto com o Postgres via PostgREST (SDK do Supabase), e toda a lógica de negócio (cálculos, validações, orquestração) roda no navegador, em JavaScript.

### 2.2. Linguagens, frameworks e bibliotecas

| Camada | Tecnologia |
|---|---|
| Frontend | HTML5 + CSS3 (custom properties para tema claro/escuro) + JavaScript ES6+ puro (sem framework — sem React/Vue/Angular, sem JSX, sem módulos ES importados de arquivos separados) |
| Gráficos | Chart.js 4 (via CDN) |
| Backend de dados | Supabase (Postgres 15 + PostgREST + Realtime + Auth), plano Cloud |
| IA / extração de dados | Anthropic API (`claude-sonnet-5`), chamada só pelo Cloudflare Worker |
| Proxy de IA | Cloudflare Workers (JavaScript, runtime V8 isolado, sem Node.js) |
| Hospedagem do frontend | Imagem Docker `nginx:alpine` servindo arquivos estáticos, implantada via EasyPanel |
| PWA | Web App Manifest + Service Worker nativo (sem Workbox) |
| Calendário externo | Google Calendar API + Google Identity Services (OAuth2 implícito no navegador) |

Não há `package.json`, `node_modules`, bundler (Webpack/Vite/esbuild), transpiler (Babel/TypeScript), linter ou test runner no projeto principal. Todas as bibliotecas de terceiros do frontend são carregadas via `<script src="https://cdn...">` direto no `<head>` do `index.html`:

```html
<script src="https://accounts.google.com/gsi/client" async defer></script>
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>
```

Repare que as versões estão fixadas só na **major** (`@2`, `@4`) — o jsDelivr resolve a última minor/patch compatível a cada carregamento de página, sem lockfile. Isso é discutido na seção de limitações.

---

## 3. Estrutura de pastas e arquivos

```
montanha system/
├── index.html                    # TODO o frontend: HTML + CSS + ~180 funções JS (SPA inteira)
├── manifest.json                  # Web App Manifest (PWA instalável)
├── sw.js                          # Service Worker (cache do "app shell", estratégia network-first)
├── icon-192.png, icon-512.png     # Ícones do PWA
├── Dockerfile                     # Build da imagem nginx:alpine que serve os arquivos estáticos
├── nginx.conf                     # Config do nginx: headers de segurança + no-cache em arquivos "vivos"
├── cloudflare-worker/
│   ├── worker.js                  # Worker: recebe imagem/texto, monta prompt, chama Anthropic, devolve JSON
│   ├── wrangler.toml              # Config de deploy do worker (nome: montanha-analisar-extrato)
│   └── .wrangler/                 # Cache local do wrangler CLI (gitignored)
├── migrations/                    # Histórico MANUAL de alterações de schema (não é uma ferramenta real de migration)
│   ├── 000_schema_snapshot_2026-07-08.sql   # Dump completo do schema nessa data (baseline)
│   ├── 001_add_bancos_config.sql
│   ├── 002_add_hora_financeiro.sql
│   ├── 003_enable_realtime.sql
│   ├── 004_add_hora_saldos_iniciais.sql
│   ├── 005_add_categoria_financeiro.sql
│   ├── 006_add_natureza_financeiro.sql
│   ├── 007_add_origem_voz_financeiro.sql
│   ├── 008_add_itens_proposta.sql
│   ├── 009_add_status_proposta.sql
│   ├── 010_add_investimento_manual_proposta.sql
│   ├── 011_add_equipe_proposta.sql
│   ├── 012_add_hora_agendado_videos.sql
│   ├── 013_add_agencia_comissao_proposta.sql
│   ├── 014_add_investimentos.sql
│   └── README.md                  # Explica que é só um histórico, aplicado manualmente no Supabase
├── projetos-externos/              # (gitignored) OUTRO projeto solto na mesma pasta local — "ecomerce instrumentos" —
│                                    #   NÃO faz parte do Montanha System, não confundir ao migrar
├── .claude/                        # Config local do Claude Code (settings.local.json com permissões de Bash)
├── .gitignore
└── montanha system.code-workspace  # Workspace do VSCode (sem settings especiais)
```

### O que faz cada módulo dentro de `index.html`

Como não há separação em arquivos, a "modularização" existe apenas como convenção de nomenclatura e agrupamento de funções dentro do único `<script>` (linha 386 a 2763 do arquivo). Os principais blocos, na ordem em que aparecem:

1. **Constantes de domínio** (linhas ~1–165): estágios do pipeline (`STAGES`), cores por estágio, formas de pagamento, lista padrão de bancos, cor por cliente/banco (hash determinístico), chave/URL do Supabase, logo em base64.
2. **Conversores DB ↔ objeto JS** (`dbToVideo`/`videoToDb`, `dbToFin`/`finToDb`, `dbToProp`/`propToDb`, `dbToInv`/`invToDb`): fazem a ponte entre `snake_case` (Postgres) e `camelCase` (JS), repetidas manualmente para cada entidade.
3. **`fetchAll()`**: busca de uma vez todas as tabelas do Supabase e monta o objeto global `store` (estado único da aplicação, mantido em memória, sem Redux/Zustand/etc — é um objeto global mutável).
4. **Renderização** (`render()`, `renderFin()`, `renderPropostas()`, `renderCal()`, `renderProdCharts()`, `renderFinCharts()`, etc.): funções que leem `store` e reescrevem `innerHTML` das seções da página. Não há virtual DOM nem diffing — cada `render()` reconstrói o HTML inteiro da seção afetada.
5. **Ações do usuário** (`addVideo`, `saveFin`, `addProposta`, `gerarPropostaPDF`, etc.): funções chamadas via `onclick="..."` inline no HTML gerado, que alteram `store` localmente, re-renderizam a UI **e só depois** disparam a chamada assíncrona ao Supabase (padrão "otimista": a tela já muda antes da confirmação do servidor).
6. **Integrações externas**: importação de extrato (CSV/OFX/foto via IA), lançamento por voz (Web Speech API + IA), Google Calendar (link manual ou API OAuth), backup local (File System Access API / download de JSON), exportação `.ics`.
7. **Autenticação** (final do arquivo): login/logout/esqueci-senha via Supabase Auth, carregamento de permissões, `boot()` (sequência de inicialização) e `setupRealtime()` (assinatura de mudanças ao vivo).

---

## 4. Banco de dados

Motor: **PostgreSQL 15** (Supabase Cloud). Não há um schema "versionado" formalmente (sem Supabase CLI/migrations reais) — o estado atual é a soma do snapshot `000` + as 14 migrations SQL aplicadas manualmente em sequência. As tabelas abaixo já refletem o schema **final** (snapshot + todas as migrations aplicadas).

Projeto Supabase: `montanha-system` (ref `vyulrlonjbajaikdgixd`, região `us-east-2`) — **este projeto Postgres é compartilhado** com o `cifras-app` (tabelas com prefixo `cifras_`), por limite de 2 projetos gratuitos por conta Supabase.

### 4.1. Diagrama de relacionamento (lógico)

```
auth.users (gerenciado pelo Supabase Auth)
    │ 1:1 (ON DELETE CASCADE)
    ▼
profiles (id = auth.users.id)

clients (id)
    │ 1:N (ON DELETE CASCADE via client_id)
    ▼
videos (client_id → clients.id)

financeiro           ─┐
saldos_iniciais       │  sem FK formal — "banco"/"cliente" são strings livres,
propostas             │  resolvidas por nome contra clients.name / app_config.bancos
investimentos         │  no lado da aplicação (ver seção 9)
videos.cliente        │
propostas.cliente     ─┘

app_config  (tabela singleton, sempre 1 linha, id fixo = 1)
```

O único relacionamento com FK real de negócio é `videos.client_id → clients.id`. Todas as outras ligações "conceituais" (um lançamento financeiro pertence a um cliente, uma proposta é de um cliente, uma conta bancária existe numa lista configurável) são feitas por **texto livre comparado por nome**, não por chave estrangeira — ver limitações.

### 4.2. Tabela `clients`

Cada linha é um cliente da produtora (tenant "lógico" dentro do mesmo login — não é um usuário, é quem recebe os vídeos/propostas).

| Coluna | Tipo | Default | Notas |
|---|---|---|---|
| `id` | uuid | `gen_random_uuid()` | PK |
| `name` | text | `'Novo Cliente'` | Nome exibido, usado como chave de "match" por nome em várias telas |
| `sub` | text | `'Painel de Conteúdo'` | Subtítulo abaixo do nome na sidebar |
| `accent` | text | `'#EF7B24'` | Cor de marca — reskinha a interface inteira quando o cliente está selecionado |
| `logo` | text | `'N'` | Inicial usada como avatar quando não há foto |
| `logo_img` | text | `NULL` | Logo como **data URL base64** direto na coluna (não usa Supabase Storage) |
| `created_at` | timestamptz | `now()` | |
| `responsavel` | text | `''` | Nome do contato/responsável do lado do cliente |
| `telefone` | text | `''` | |
| `email` | text | `''` | |
| `instagram` | text | `''` | |
| `razao_social` | text | `''` | |
| `cnpj` | text | `''` | |
| `endereco` | text | `''` | |
| `valor_mensal` | numeric | `0` | Valor de contrato mensal recorrente (informativo, não gera lançamento automático) |
| `dia_vencimento` | integer | `NULL` | Dia do mês de vencimento do contrato |
| `data_inicio_contrato` | date | `NULL` | |
| `status` | text | `'ativo'` | `ativo` \| `inativo` |
| `observacoes` | text | `''` | |

RLS: `authenticated_all_clients` — qualquer usuário autenticado tem `SELECT/INSERT/UPDATE/DELETE` livre.

### 4.3. Tabela `videos`

Cada linha é uma **tarefa/peça de conteúdo** em produção para um cliente (o pipeline Kanban).

| Coluna | Tipo | Default | Notas |
|---|---|---|---|
| `id` | uuid | `gen_random_uuid()` | PK |
| `client_id` | uuid | — | **FK → `clients.id` ON DELETE CASCADE**, indexado (`videos_client_id_idx`) |
| `cliente` | text | `''` | Nome do cliente **desnormalizado** (texto livre, pode divergir do dono real) |
| `titulo` | text | `''` NOT NULL | |
| `objetivo` | text | `'redes_sociais'` | `autoridade` \| `captacao` \| `redes_sociais` \| `institucional` \| `reuniao` |
| `estagio` | text | `'agendado'` | Estágio do funil (ver §6.3) |
| `inicio` | date | `NULL` | Data de início da produção |
| `entrega` | date | `NULL` | Data de entrega prevista — usada no calendário e nos alertas de prazo |
| `hora_agendado` | text | `''` | *(migration 012)* Horário, só relevante quando `estagio='agendado'` |
| `roteiro` | text | `''` | |
| `mods` | text | `''` | Texto das modificações pedidas pelo cliente |
| `enviado` | boolean | `false` | Marca se já foi enviado ao cliente |
| `data_envio` | date | `NULL` | |
| `gcal_event_id` | text | `NULL` | ID do evento no Google Calendar, se criado via API |
| `historico` | jsonb | `'[]'` | **Log append-only** de transições: `[{estagio, data, hora}, ...]` |
| `created_at` | timestamptz | `now()` | |
| `editor` | text | `''` | Nome do editor/responsável pela produção (usado nos filtros) |
| `descricao_servico` | text | `''` | |

RLS: `authenticated_all_videos` — acesso total para qualquer autenticado.

### 4.4. Tabela `financeiro`

Cada linha é um **lançamento** (entrada ou saída de dinheiro), pessoal ou da empresa.

| Coluna | Tipo | Default | Notas |
|---|---|---|---|
| `id` | uuid | `gen_random_uuid()` | PK |
| `tipo` | text | — NOT NULL | **CHECK** `IN ('entrada','saida')` |
| `descricao` | text | `''` | |
| `cliente` | text | `''` | Texto livre, não FK |
| `valor` | numeric(12,2) | `0` NOT NULL | Valor bruto |
| `desconto` | numeric(12,2) | `0` | Desconto "na fonte"; valor líquido = `valor - desconto` |
| `forma_pagamento` | text | `'pix'` NOT NULL | `pix`\|`boleto`\|`cartao_debito`\|`cartao_credito`\|`transferencia`\|`dinheiro`\|`outro`\|`cartao` (valor legado, mantido só para não quebrar dados antigos) |
| `banco` | text | `''` | Nome da conta — comparado contra a lista dinâmica em `app_config.bancos`, sem FK |
| `vencimento` | date | `NULL` | Data de vencimento/movimento previsto |
| `status` | text | `'pendente'` NOT NULL | **CHECK** `IN ('pendente','pago')` |
| `data_pagamento` | date | `NULL` | Data em que **efetivamente** foi pago/recebido — é o campo usado em todos os cálculos de saldo e relatórios de período |
| `created_at` | timestamptz | `now()` | |
| `hora` | text | `NULL` | *(migration 002)* Horário do lançamento |
| `categoria` | text | `NULL` | *(migration 005)* Hoje só usa `'imposto'` ou vazio; campo livre pensado para expansão futura |
| `natureza` | text | `'empresa'` | *(migration 006)* `'empresa'` \| `'pessoal'` — separa fluxo de caixa pessoal do da empresa dentro das MESMAS contas |
| `origem_voz` | boolean | `false` | *(migration 007)* Marca lançamentos criados pelo fluxo de voz sem confirmação prévia, para revisão |

RLS: `financeiro_by_permission` — só permite acesso (`USING`/`WITH CHECK`) se existir uma linha em `profiles` para `auth.uid()` com `can_view_financeiro = true`. Ou seja, é o único módulo com controle de acesso por perfil dentro do mesmo login "authenticated".

### 4.5. Tabela `saldos_iniciais`

Mecanismo de **"corte de saldo"** por conta — não é um saldo único e global, é um histórico de pontos de referência.

| Coluna | Tipo | Default | Notas |
|---|---|---|---|
| `id` | uuid | `gen_random_uuid()` | PK |
| `banco` | text | — NOT NULL | Nome da conta |
| `valor` | numeric(12,2) | `0` NOT NULL | Saldo conhecido/real naquele momento |
| `data` | date | `CURRENT_DATE` NOT NULL | |
| `created_at` | timestamptz | `now()` | |
| `hora` | text | `NULL` | *(migration 004)* Junto com `data`, forma o "instante do corte" — usado para decidir se um lançamento é anterior ou posterior ao corte |

RLS: `saldos_by_permission` — mesma regra de `can_view_financeiro` do financeiro.

**Regra de negócio (implementada no client, não no banco):** o saldo atual de uma conta = soma de todos os `saldos_iniciais.valor` daquela conta (normalmente só 1 linha ativa por conta, pois toda vez que o saldo é reajustado a linha antiga é deletada e uma nova é inserida) **+** soma de todos os lançamentos de `financeiro` com `status='pago'` daquela conta cujo `data_pagamento + hora >= data + hora` do corte mais recente daquela conta. Tudo que aconteceu **antes** do corte vira histórico "neutro" (não é somado de novo).

### 4.6. Tabela `profiles`

Extensão da tabela `auth.users` do Supabase, usada só para controle de permissão do módulo financeiro.

| Coluna | Tipo | Default | Notas |
|---|---|---|---|
| `id` | uuid | — | PK, **FK → `auth.users.id` ON DELETE CASCADE** |
| `can_view_financeiro` | boolean | `false` NOT NULL | Flag de permissão |
| `created_at` | timestamptz | `now()` | |

RLS: `self_read_profile` — política de **apenas SELECT**, e só do próprio registro (`auth.uid() = id`). **Não existe policy de INSERT/UPDATE** — a criação de perfis e a concessão da flag `can_view_financeiro` só podem ser feitas manualmente via SQL direto no Supabase (não há UI no app para isso).

### 4.7. Tabela `propostas`

Cada linha é uma proposta comercial/orçamento.

| Coluna | Tipo | Default | Notas |
|---|---|---|---|
| `id` | uuid | `gen_random_uuid()` | PK |
| `cliente` | text | `''` NOT NULL | Texto livre |
| `cliente_email` | text | `''` NOT NULL | Usado para o botão "Enviar por e-mail" (`mailto:`) |
| `titulo` | text | `''` NOT NULL | |
| `data` | date | `NULL` | |
| `validade_dias` | integer | `30` NOT NULL | |
| `servicos` | jsonb | `'[]'` NOT NULL | Array de `{desc, qtd, unidade, valor}` |
| `equipamentos` | jsonb | `'[]'` NOT NULL | Mesma estrutura de `servicos` |
| `investimento` | numeric | `0` NOT NULL | Valor total **calculado**, persistido para listar rápido sem recalcular |
| `observacoes` | text | `''` NOT NULL | |
| `created_at` | timestamptz | `now()` | |
| `numero` | text | `''` NOT NULL | *(migration 008)* Número sequencial gerado no client (`Nº DDMMYYNNNNN`) |
| `escopo` | jsonb | `'[]'` NOT NULL | *(migration 008)* Checklist "o que está incluso" — array de strings |
| `desconto` | numeric | `0` NOT NULL | *(migration 008)* Percentual sobre o subtotal |
| `imposto` | numeric | `0` NOT NULL | *(migration 008)* Percentual sobre o valor já descontado |
| `prazo` | text | `''` NOT NULL | *(migration 008)* Texto livre (ex: "Entrega digital em até 24h") |
| `pagamento` | text | `''` NOT NULL | *(migration 008)* Condições de pagamento (texto livre) |
| `status` | text | `'rascunho'` NOT NULL | *(migration 009)* `rascunho`\|`enviada`\|`aceita`\|`recusada` |
| `investimento_manual` | numeric | `NULL` | *(migration 010)* Se preenchido, **substitui** todo o cálculo automático por itens |
| `equipe` | jsonb | `'[]'` NOT NULL | *(migration 011)* Array de strings, ex: `["Diretor de imagens","Cinegrafista"]` |
| `agencia_ativa` | boolean | `false` NOT NULL | *(migration 013)* Ativa comissão de agência intermediária |
| `agencia_comissao_perc` | numeric | `15` | *(migration 013)* % de comissão da agência |
| `agencia_nf_perc` | numeric | `6` | *(migration 013)* % de custo de nota fiscal |

RLS: `authenticated_all_propostas` — acesso total para qualquer autenticado.

**Migration 008** também fez um `UPDATE` de retrocompatibilidade: propostas antigas com `servicos`/`equipamentos` como array de strings simples (`["Gravação","Edição"]`) foram convertidas para o novo formato de objetos (`{desc, qtd:1, valor:0}`).

**Cálculo do valor final (gross-up de agência)** — regra de negócio documentada explicitamente no comentário da migration 013 e implementada em `calcAgenciaGrossUp()` no client:

```
valor_final = líquido / (1 − comissão% − nota_fiscal%)
```

de forma que, depois da agência descontar sua comissão e o custo de nota fiscal **sobre o valor final cobrado do cliente**, o que sobra para o produtor seja exatamente o valor líquido calculado antes da comissão.

### 4.8. Tabela `investimentos`

*(migration 014)* Rastreamento manual de posições de investimento (ex: cripto), fora do fluxo de caixa comum.

| Coluna | Tipo | Default | Notas |
|---|---|---|---|
| `id` | **text** | — | PK — atenção: é `text`, não `uuid` (as outras tabelas usam uuid); recebe um UUID gerado no client mas tipado como string |
| `ativo` | text | `''` NOT NULL | Ex: `BTC`, `ETH` |
| `data` | date | `NULL` | Data da aplicação |
| `quantidade` | numeric | `0` | |
| `valor_investido` | numeric | `0` | |
| `valor_atual` | numeric | `0` | **Atualizado manualmente pelo usuário** — não há cotação automática |
| `conta` | text | `''` | Banco/corretora onde está a posição |
| `observacoes` | text | `''` | |
| `created_at` | timestamptz | `now()` | |

RLS: `authenticated_all_investimentos` — acesso total para qualquer autenticado.

### 4.9. Tabela `app_config`

Tabela **singleton** (sempre 1 linha, `id` travado em `1` via `CHECK (id = 1)`), usada como "configurações globais" da instância.

| Coluna | Tipo | Default | Notas |
|---|---|---|---|
| `id` | integer | `1` NOT NULL | PK, `CHECK (id = 1)` |
| `gcal_client_id` | text | `''` | Google OAuth Client ID para integração de calendário |
| `reserve_bancos` | jsonb | `'[]'` | Subconjunto de `bancos` marcado como conta-reserva/caixinha |
| `bancos` | jsonb | `'[]'` | *(migration 001)* Lista completa de nomes de contas bancárias disponíveis no sistema |

RLS: `authenticated_all_config` — acesso total para qualquer autenticado.

### 4.10. Realtime

*(migration 003)* Habilitado via `ALTER PUBLICATION supabase_realtime ADD TABLE ...` para: `financeiro`, `videos`, `clients`, `saldos_iniciais`, `propostas`, `app_config`. **`investimentos` não foi incluída** (criada depois, na migration 014 — ver limitações). O client se inscreve em todas essas tabelas num único canal (`montanha-realtime`) e, a cada evento (`INSERT`/`UPDATE`/`DELETE` em qualquer uma), agenda um `fetchAll()` completo com debounce de 400ms — não há atualização incremental por linha.

### 4.11. Regras de negócio embutidas no banco (resumo)

O Postgres, propositalmente, tem muito pouca lógica embutida — quase tudo está no client. O que existe de fato no banco:

- `CHECK (tipo IN ('entrada','saida'))` e `CHECK (status IN ('pendente','pago'))` em `financeiro`.
- `CHECK (id = 1)` em `app_config` (garante singleton).
- `ON DELETE CASCADE` em `videos.client_id → clients.id` e `profiles.id → auth.users.id`.
- RLS como única camada de autorização (não há Row Level Security combinada com policies mais finas por linha, exceto o padrão "authenticated vê tudo" + a exceção do financeiro).
- Nenhuma trigger, function/stored procedure ou view customizada.

---

## 5. Autenticação e controle de acesso

- **Mecanismo:** Supabase Auth, e-mail + senha (`sb.auth.signInWithPassword`). **Não há tela de cadastro/self-signup no app** — os usuários (só a equipe da Montanha Filmes) precisam ser criados manualmente no Supabase (Dashboard ou Admin API).
- **Recuperação de senha:** `sb.auth.resetPasswordForEmail(email)` — dispara e-mail nativo do Supabase com link de redefinição.
- **Sessão:** persistida pelo próprio SDK (`localStorage`, comportamento padrão do `supabase-js`). Ao carregar a página, o app chama `sb.auth.getSession()`; se houver sessão válida, pula a tela de login e chama `boot()` direto.
- **Logout:** `sb.auth.signOut()` seguido de `location.reload()` (recarrega a página inteira, não só o estado JS).
- **Autorização de dados:** feita inteiramente via **Row Level Security** no Postgres:
  - Qualquer usuário autenticado (`auth.role() = 'authenticated'`) tem acesso total a `clients`, `videos`, `propostas`, `app_config`, `investimentos`.
  - `financeiro` e `saldos_iniciais` exigem, além de estar autenticado, uma linha em `profiles` com `can_view_financeiro = true` para aquele `auth.uid()`.
  - No client, `loadPermissions()` lê essa flag no boot e usa para **esconder** (não só bloquear) o botão "Financeiro" do menu lateral quando `false` — mas a proteção real é a RLS, não o CSS/JS (um usuário mal-intencionado logado não veria a aba, mas a API do Supabase já barraria a query mesmo que ele tentasse via console).
- **Concessão de acesso ao financeiro:** como não há policy de `INSERT`/`UPDATE` em `profiles` nem UI no app, dar a um usuário acesso ao módulo financeiro exige rodar manualmente um `INSERT`/`UPDATE` SQL em `profiles` no Supabase Studio.
- **Chave pública do Supabase:** `SUPABASE_ANON_KEY` está hardcoded no `index.html` (client-side). Isso é o comportamento **esperado** do Supabase — a anon key é pública por design e a segurança real vem das RLS policies — mas reforça que toda a segurança de dados depende de as policies estarem corretas.

---

## 6. Módulos funcionais

### 6.1. Módulo financeiro (pessoal + empresa)

**Conceitos-chave**

- `financeiro`: cada linha é um lançamento (entrada ou saída), com status `pago` ou `pendente`.
- `saldosIniciais`: "cortes" de saldo por conta (ver §4.5) — mecanismo central para não precisar reconciliar retroativamente todo o histórico sempre que o saldo real diverge do calculado.
- `natureza` (`empresa`/`pessoal`): mesma conta bancária física é usada tanto para gastos da empresa quanto pessoais do dono — o campo só marca, visualmente e nos relatórios, qual é qual. Válido apenas a partir de `NATUREZA_INICIO = '2026-07-21'` (constante no client) para não distorcer retroativamente relatórios de dados antigos que não tinham esse campo.
- `RESERVE_BANCOS`: subconjunto de contas (ex: "caixinhas" do Nubank) tratado à parte do "saldo operacional" nos relatórios, embora ainda componha o "saldo total" combinado exibido no topo.

**Fluxo A — lançamento manual**

1. `addFinanceiro()` cria o registro com defaults (tipo conforme a aba/filtro atual, banco padrão, data/hora de agora) e **já insere** no Supabase antes mesmo do usuário preencher os detalhes (evita perder o registro se o navegador travar no meio).
2. Modal (`openFin`) para editar todos os campos.
3. `saveFin()`: **valida** que, se `status='pago'`, precisa haver um banco selecionado (sem isso o valor não entraria no saldo de conta nenhuma — bloqueia com `alert`); grava um snapshot para undo; grava a mudança local e depois no Supabase.
4. Se o usuário fechar o modal de um lançamento **novo** sem salvar, `descartarModalDraft()` deleta o registro "rascunho" criado no passo 1 (evita lançamentos fantasmas vazios).

**Fluxo B — importação de extrato via arquivo (CSV/OFX)**

1. Usuário escolhe a conta de origem e sobe um `.ofx`/`.qfx` ou `.csv` exportado do banco.
2. Parsing **100% determinístico, sem IA** (`parseExtratoOFX` via regex sobre blocos `<STMTTRN>`; `parseExtratoCSV` com parser CSV manual e heurísticas de cabeçalho, incluindo tratamento especial para fatura de cartão de crédito onde o sinal do valor é invertido).
3. `prepararRevisao()`: expande pares de reserva (`expandReservaPairs` — um resgate de caixinha gera automaticamente o lançamento espelho na conta principal), remove duplicatas dentro do próprio arquivo (`dedupBatch`) e sinaliza como possível duplicata (desmarcando da seleção) qualquer linha que bata com um lançamento já existente por data+tipo+valor (`marcarDuplicatas`).
4. Tela de revisão editável linha a linha (`renderRevisaoExtrato`) antes de confirmar.
5. `confirmarImportExtrato()` insere em lote só os itens marcados.

**Fluxo C — importação de extrato por foto (IA)**

1. Mesmo modal, mas o usuário sobe uma ou mais imagens (ou cola com Ctrl+V).
2. Cada imagem é convertida para base64 e enviada via `POST` ao Cloudflare Worker (`EXTRATO_WORKER_URL`).
3. O Worker monta um prompt detalhado (`imagePrompt` em `cloudflare-worker/worker.js`) — trata especificamente o layout típico de apps bancários (data como cabeçalho de grupo separado do horário de cada lançamento), resolve "Hoje"/"Ontem" contra a data enviada, infere forma de pagamento, categoria (`imposto`) e natureza (com heurística extra se o nome da conta contiver "PF"/"PJ") — e chama a Anthropic API (`claude-sonnet-5`).
4. Os valores retornados pela IA para campos "livres" (banco, cliente) são **normalizados no client** contra as listas reais (`normCliente`, `normFormaPagamento`, etc.) — nunca aceita um valor que a IA tenha alucinado fora do vocabulário conhecido.
5. Segue para a mesma tela de revisão do fluxo B.

**Fluxo D — lançar por voz**

1. Web Speech API do navegador (`SpeechRecognition`, português) transcreve a fala continuamente.
2. Ao parar de falar, o texto final é mandado ao mesmo Worker, agora em modo texto (`textPrompt`), com a lista de contas e clientes reais como "vocabulário guiado" para a IA corrigir erros de transcrição/homófono.
3. **Diferença crítica:** aqui **não há tela de confirmação prévia** — assim que a IA responde, o lançamento é gravado direto na tabela, marcado com `origem_voz = true`.
4. Lançamentos com essa flag aparecem destacados em roxo na lista ("🎤 Entrada por comando de voz — conferir") até que o usuário abra e salve manualmente (o que zera a flag).

**Fluxo E — ajuste de saldo**

- "Saldo inicial" define de uma vez o saldo de todas as contas (substitui toda a tabela `saldos_iniciais`) — usado normalmente uma vez, ao configurar o sistema.
- "Ajustar saldo de uma conta" ajusta o corte de **uma** conta específica, sem mexer nas outras — usado no dia a dia para corrigir divergência.
- "Movimentar reserva" registra transferência de/para uma conta-reserva, criando automaticamente o lançamento espelho no destino escolhido.

**Relatórios e recursos adicionais**

- Saldo por banco, totais por período (semana/mês/ano), divisão mensal (12 meses), separação pessoal×empresa, total de impostos.
- Gráficos (Chart.js): entradas/saídas por mês, receita por cliente, entrada/saída por conta-reserva, impostos por mês, pessoal×empresa por mês.
- Seleção múltipla com edição em lote (trocar banco/natureza de vários lançamentos de uma vez) e exclusão em lote.
- **Undo**: pilha de até 20 snapshots completos da tabela `financeiro` mantida **só em memória** (perdida ao recarregar a página), permitindo desfazer a última ação sincronizando a diferença de volta ao Supabase.
- Modo "ocultar valores" (privacidade visual, ex: em reunião) — preferência de sessão, não persistida.
- Aviso fixo de "backup do dia ainda não feito" baseado em `localStorage`.

### 6.2. Módulo de propostas comerciais

**Fluxo do início ao fim**

1. `addProposta()` cria a proposta com catálogo padrão pré-preenchido (`DEFAULT_SERVICOS`/`DEFAULT_EQUIPAMENTOS`, refletindo o catálogo típico da Montanha Filmes), número sequencial automático (`nextPropostaNumero()`: formato `Nº DDMMYYNNNNN`, achando o maior sufixo de 5 dígitos já usado) e status inicial `rascunho`.
2. A edição acontece sobre um **draft em memória** (`propDraft`, cópia profunda do objeto) — nada é gravado em `store.propostas` até o usuário clicar em salvar. `propDraftIsDirty()` compara o draft contra o snapshot original para perguntar antes de descartar alterações não salvas ao fechar.
3. Campos editáveis: cliente, e-mail do cliente, título, data, validade em dias, checklist de escopo (itens arrastáveis via drag-and-drop), lista de serviços e de equipamentos (cada item com descrição/quantidade/unidade/valor unitário, também arrastáveis), equipe alocada, desconto (%) e imposto (%), comissão de agência intermediária opcional (dois percentuais), prazo de entrega, forma de pagamento, observações internas, e um campo de **valor manual** que, se preenchido, ignora todo o cálculo por itens.
4. **Cálculo do total** (`calcProp`, função pura):
   - Sem valor manual: `subtotal = Σ(qtd × valor unitário)` de serviços + equipamentos → desconta `desconto%` → aplica `imposto%` sobre o valor já descontado → resulta em `líquido`.
   - Com valor manual: `líquido = investimentoManual`, ignorando itens/desconto/imposto.
   - Se a comissão de agência está ativa, aplica o **gross-up** descrito em §4.7 (`calcAgenciaGrossUp`). Se `comissão% + nota_fiscal% ≥ 100%`, o cálculo é sinalizado como inválido e a UI mostra aviso, caindo de volta para o valor líquido sem gross-up.
5. Ações disponíveis sobre uma proposta:
   - **Salvar** (`saveProp`): grava o draft de volta em `store.propostas` + `UPDATE` no Supabase.
   - **Salvar como nova** (`salvarPropComoNova`): duplica o draft como proposta nova (novo id/número, status resetado) — funciona como "usar de modelo".
   - **Gerar PDF** (`gerarPropostaPDF`): monta um documento HTML **independente e completo** (com CSS/tipografia próprios, tema editorial escuro/laranja) numa nova aba do navegador e dispara `window.print()`. **Não gera um arquivo PDF binário de verdade** — depende do usuário escolher "Salvar como PDF" no diálogo de impressão do navegador. Tenta se auto-ajustar para caber em uma única página A4 (área historicamente frágil — ver histórico de commits e limitações).
   - **Enviar por e-mail** (`enviarPropostaEmail`): **não envia e-mail de verdade** — monta um link `mailto:` com assunto/corpo pré-preenchidos e abre o cliente de e-mail padrão do usuário; o próprio corpo do e-mail lembra o usuário de anexar manualmente o PDF (não há anexo automático).
   - **Excluir**.
6. Listagem agrupada por cliente (pastas expansíveis), com status colorido, valor total e atalhos rápidos para gerar PDF/e-mail sem abrir a proposta inteira.

### 6.3. Pipeline de produção de vídeo (controle de entradas e saídas de serviço)

Este é o módulo de acompanhamento de cada peça de conteúdo em produção — um Kanban com funil fixo de estágios:

```
agendado → captação → edição → enviado_para_aprovação ⇄ modificações_solicitadas → aprovado → publicado → (arquivamento automático) finalizado
```

**Fluxo do início ao fim**

1. **Entrada no funil:** `addVideo()` cria a tarefa vinculada ao cliente atualmente selecionado, estágio inicial `agendado`, datas de início/entrega padrão = hoje, e já grava o primeiro evento em `historico` — um **log append-only** de todas as transições de estágio (`{estagio, data, hora}`), usado para calcular tempo médio por etapa, verificar prazos e desenhar a linha do tempo visual em cada card.
2. **Edição de detalhes** (`openV`/`saveV`): cliente, editor responsável, título, descrição do serviço, objetivo (categoriza o tipo de conteúdo — autoridade, captação, redes sociais, institucional, reunião), datas, roteiro, campo de modificações (só visível no estágio `modificacoes`), flag "enviado para o cliente" + data de envio.
3. **Movimentação entre estágios**, de duas formas:
   - Drag-and-drop no board Kanban (`bindDrag`) — dispara `logStage()` (só grava novo evento se o estágio realmente mudou) e sincroniza com o Supabase.
   - Atalhos no estágio `envio_aprovacao`: **"Aprovar"** (vai para `aprovacao`) ou **"Pedir ajuste"** (pede o texto do que foi solicitado via `prompt()`, salva em `mods` e volta para `modificacoes` — criando o ciclo de retrabalho até aprovação).
4. **Arquivamento automático** (`autoArchivePublicados()`, rodado a cada `boot()`): qualquer vídeo em `aprovacao` ou `publicado` cujo último evento **naquele estágio** seja de um mês-calendário anterior ao atual é movido automaticamente para o estágio sintético `finalizado` (fora do board Kanban, só visível na aba "Arquivadas", agrupado por cliente). Ou seja, há uma "carência" de um mês antes de a tarefa sair do quadro ativo.
5. **Integração com Google Agenda**: cada tarefa pode virar evento com a data de entrega, de duas formas — link direto sem autenticação (`gcalUrl`, abre um popup do Google Calendar para confirmação manual) **ou**, se um Google OAuth Client ID estiver configurado (em "Marca & configurações"), criação/exclusão automática via API real (`gcalCreateEvent`/`gcalDeleteEvent`, usando Google Identity Services para obter um access token OAuth2 implícito no navegador, escopo `calendar.events`). O calendário interno também pode **puxar** (somente leitura) os eventos reais do Google Calendar do mês visível e sobrepor visualmente.
6. **Visualizações derivadas do mesmo dado**: dashboard (contadores, próxima entrega, alertas de prazo em risco/atrasado), board Kanban, calendário mensal, gráficos de indicadores (tempo médio por etapa, "avanços" — quantas tarefas chegaram a `publicado` no mês — vs. "perdas" — quantas caíram em `modificacoes` no mês —, e distribuição atual por estágio).
7. **Multi-tenant por cliente, não por usuário**: cada cliente tem uma marca própria (nome, cor, logo) que reskinha a interface quando selecionado. Existe também uma visão consolidada "Todos os clientes" (`ALL_ID`) que agrega tudo para dashboard/board/calendário, mas sem operações de escrita específicas (não dá para criar tarefa nesse modo).
8. **Exportações**: `.ics` (iCalendar, todas as entregas com data) e JSON (dados completos de um cliente, ou backup geral).

### 6.4. Outros módulos

- **CRM de clientes** (`renderClientesCRM`/`openClienteInfo`): ficha de cada cliente com dados de contato, contrato (valor mensal, dia de vencimento, data de início), status ativo/inativo e observações — sem lógica de faturamento automático (é só cadastro).
- **Dashboard "Resumo geral"**: tabela comparando todos os clientes lado a lado (tarefas em produção, modificações pendentes, próxima entrega).
- **Backup**:
  - Exportação manual de um cliente (JSON) ou de tudo (`store` inteiro, JSON).
  - Backup automático diário opcional em uma pasta local escolhida pelo usuário via **File System Access API** (`showDirectoryPicker`, só Chrome/Edge desktop) — o handle da pasta é persistido em IndexedDB (`idbSet`/`idbGet`); se a permissão expirar silenciosamente entre sessões, o app detecta e mostra o aviso de backup pendente.
- **PWA**: `manifest.json` + `sw.js` tornam o app instalável, com cache "network-first com fallback" do app shell (index.html, manifest, ícones) — funciona offline apenas para reabrir a última tela carregada, não para operar sem rede (todo dado real vem do Supabase).
- **Tema claro/escuro**: via CSS custom properties + `data-theme` no `<html>`, seguindo preferência do SO por padrão ou escolha manual persistida em `localStorage`.

---

## 7. Dependências externas

Não há gerenciador de pacotes nem lockfile. Tudo é carregado por CDN ou é código próprio.

| Dependência | Onde | Versão fixada | Função |
|---|---|---|---|
| `@supabase/supabase-js` | jsDelivr, `index.html` | `@2` (major apenas) | Cliente Supabase: Auth, banco (PostgREST) e Realtime |
| `chart.js` | jsDelivr, `index.html` | `@4` (major apenas) | Todos os gráficos de barra do dashboard/financeiro |
| Google Identity Services | `accounts.google.com/gsi/client` | Sempre a última (sem versionamento) | OAuth2 implícito para Google Calendar |
| Google Fonts — Inter | `fonts.googleapis.com`, `index.html` | pesos 400/500/600/700/800 | Tipografia principal do app |
| Google Fonts — IBM Plex Mono + Space Grotesk | `fonts.googleapis.com`, carregado só na janela de impressão de proposta | pesos variados | Tipografia do PDF/impressão de proposta |
| Anthropic API | `api.anthropic.com/v1/messages`, chamada só pelo Worker | modelo `claude-sonnet-5`, `anthropic-version: 2023-06-01` | Extração de lançamentos financeiros de imagem/texto |
| Cloudflare Workers (runtime) | `cloudflare-worker/wrangler.toml` | `compatibility_date = "2026-07-01"` | Hospeda o proxy de IA |
| nginx | `Dockerfile`, imagem `nginx:alpine` | tag `alpine` (sem pin de versão do nginx em si) | Serve os arquivos estáticos em produção |

Sem testes automatizados, sem linter, sem TypeScript, sem bundler.

---

## 8. Variáveis de ambiente e configuração

Não existe arquivo `.env` no projeto (esperado para um app client-only sem build step). A configuração está espalhada em três lugares:

### 8.1. Constantes hardcoded no `index.html` (não são secretas)

| Nome (no código) | Para que serve |
|---|---|
| `SUPABASE_URL` | URL do projeto Supabase Cloud usado como backend |
| `SUPABASE_ANON_KEY` | Chave pública/anônima do Supabase — protegida pelas RLS policies, não é secreta por natureza |
| `EXTRATO_WORKER_URL` | URL pública do Cloudflare Worker de análise de extrato/voz |

Como não há etapa de build, essas três não podem hoje ser "injetadas" via variável de ambiente real — estão escritas direto no código-fonte. Ao migrar para uma stack com bundler, esse é o momento natural de externalizá-las via env vars de build.

### 8.2. Secret do Cloudflare Worker (nunca commitado, configurado via `wrangler secret put` ou dashboard Cloudflare)

| Nome | Para que serve |
|---|---|
| `ANTHROPIC_API_KEY` | Chave da API da Anthropic, usada exclusivamente pelo Worker para chamar `api.anthropic.com/v1/messages`. Se ausente, o Worker responde erro 500 (`worker.js` verifica isso explicitamente). |

### 8.3. Configuração runtime, editável pela própria UI, armazenada na tabela `app_config`

| Campo | Para que serve |
|---|---|
| `gcal_client_id` | Google OAuth Client ID — habilita criação/exclusão automática de eventos no Google Calendar; sem ele, cai no fallback de link manual |
| `bancos` | Lista de nomes de contas bancárias disponíveis no sistema |
| `reserve_bancos` | Subconjunto de `bancos` marcado como conta-reserva/caixinha |

### 8.4. Credenciais de usuário / acesso

- Login/senha de cada usuário: criados manualmente no Supabase Auth (Dashboard ou Admin API) — **não há tela de cadastro no app**.
- Acesso ao módulo financeiro: exige, além do login, uma linha em `profiles` com `can_view_financeiro = true` para o `id` daquele usuário — **feito manualmente via SQL**, sem UI.

### 8.5. Deploy do frontend estático

O `Dockerfile` não requer nenhuma env var de build/runtime — só copia arquivos estáticos para dentro da imagem `nginx:alpine`. O que fica fora do controle do código é a configuração do host **EasyPanel** (URL de produção, credenciais de deploy) — não documentada no repositório.

---

## 9. Decisões de arquitetura e motivos

- **SPA vanilla em arquivo único, sem build step:** provável escolha de simplicidade e velocidade de iteração para um sistema interno de uma micro-agência (não um produto com equipe grande) — qualquer alteração é "editar o arquivo e reimplantar o Docker", sem pipeline. Trade-off crescente: o arquivo já passou de 2.700 linhas / 266 KB, tornando leitura e edição cada vez mais custosas (inclusive para produzir esta própria documentação, foi necessário reprocessar o arquivo para conseguir lê-lo em partes).
- **Supabase como backend único (BaaS):** evita manter servidor próprio; Postgres real com RLS dá controle de acesso "de graça" sem escrever uma API. O projeto foi migrado de um Postgres self-hosted (Contabo + EasyPanel) para o Supabase Cloud depois que a conta Contabo foi cancelada — decisão pragmática para reduzir pontos de falha de infraestrutura própria (ver memória de projeto correlata).
- **Cloudflare Worker como o menor backend possível:** a única razão de existir um backend "de verdade" é esconder a `ANTHROPIC_API_KEY`, que não pode ir para o client. Em vez de um backend completo, foi criado o menor proxy possível — sem estado, sem banco, só repassando um prompt.
- **Saldo calculado por "cortes" (`saldos_iniciais`) em vez de edição direta de um saldo global:** permite corrigir divergência entre saldo real e calculado sem reconciliar lançamento por lançamento — só "trava" o passado e deixa o futuro contável de novo a partir daquele ponto. É uma forma simplificada de reconciliação bancária.
- **`natureza` (pessoal/empresa) como campo por lançamento, não como livros/contas separados:** reflete a realidade de uma pequena empresa/MEI, onde o dono usa as mesmas contas bancárias para pessoa física e jurídica — em vez de forçar uma separação contábil real, o sistema só filtra visualmente, com uma data de corte fixa (`NATUREZA_INICIO`) para não distorcer retroativamente relatórios de dados anteriores à existência do campo.
- **PDF via impressão do navegador, não via biblioteca:** evita dependência de uma lib pesada (jsPDF, Puppeteer/headless Chrome, etc.) — abre uma janela com HTML/CSS de impressão dedicado e deixa o navegador (que já gera PDF nativamente) fazer o trabalho. Trade-off: depende do usuário saber "Salvar como PDF" na caixa de impressão, e o ajuste de layout para caber em uma página é feito medindo alturas via JS — historicamente fonte de bugs, visível em várias correções sucessivas no histórico do git.
- **`historico` como JSON append-only dentro da própria linha de `videos`**, em vez de uma tabela de eventos separada: simplifica o schema (sem JOIN para montar a timeline de uma tarefa), ao custo de não conseguir consultar/agregar o histórico eficientemente via SQL puro (precisaria de funções jsonb).
- **Quase nenhuma regra de negócio no banco:** o Postgres só garante RLS e alguns `CHECK`s simples; todo cálculo (saldo, proposta, prazos, arquivamento automático) roda em JavaScript no navegador de quem estiver logado. Aceitável para uma ferramenta interna de poucos usuários de confiança, mas significa que a integridade "semântica" dos dados depende inteiramente do client JS estar correto.

---

## 10. Pontos de atenção, limitações e melhorias pendentes

1. **Arquivo único gigante (`index.html`, ~266 KB / 2.765 linhas):** mistura HTML, CSS e ~180 funções JS num único escopo global, sem módulos, sem classes, sem separação de responsabilidades em arquivos. É o principal candidato a refatoração ao migrar para o Claude Code — mesmo mantendo "vanilla", já valeria separar em múltiplos arquivos JS por domínio (financeiro, propostas, pipeline, auth, etc).
2. **Sem testes automatizados** de nenhum tipo — toda verificação hoje é manual no navegador.
3. **Sem TypeScript/tipagem** e conversão manual repetida `camelCase ↔ snake_case` em pares de funções (`xToDb`/`dbToX`) para cada entidade — risco real de um campo novo ser esquecido de um dos lados numa mudança futura, sem nenhum aviso em tempo de compilação.
4. **"Migrations" não são migrations de verdade:** é uma pasta de SQL numerado, aplicado manualmente e sem ferramenta (nem `supabase migration` do Supabase CLI) garantindo que ambientes fiquem sincronizados. Não há como recriar o banco do zero com um único comando — seria preciso rodar os 15 arquivos em sequência manualmente.
5. **Tabela `investimentos` não está na publicação Realtime** (foi criada na migration 014, depois da 003 que habilitou realtime nas outras 6 tabelas, e ninguém a adicionou depois) — mudanças feitas em uma aba só aparecem em outra após recarregar a página, diferente do resto do sistema.
6. **Controle de acesso ao financeiro (`profiles.can_view_financeiro`) não tem UI de administração** — só pode ser concedido/revogado via SQL manual direto no Supabase. Fácil de passar despercebido por quem for assumir o projeto sem ler o schema.
7. **CORS totalmente aberto (`*`) no Cloudflare Worker**, sem autenticação, allowlist de origem ou rate limiting — qualquer pessoa que descubra a URL pública do Worker pode consumir a cota da `ANTHROPIC_API_KEY` configurada nele. Vale considerar um token compartilhado, verificação de origem, ou Cloudflare Access/rate limiting antes de expor esse endpoint por mais tempo.
8. **PDF de proposta depende do diálogo de impressão do navegador**, não é gerado nativamente — o ajuste de layout para caber em uma página A4 teve várias correções sucessivas visíveis no histórico do git, sugerindo que ainda é uma área frágil (ex.: propostas com muitos itens podem cortar mal ou duplicar rodapé).
9. **Envio de proposta por e-mail é só um link `mailto:`** — sem envio real (SMTP/API de e-mail) nem anexo automático do PDF; depende inteiramente do usuário lembrar de anexar manualmente o arquivo já salvo.
10. **Sem paginação em nenhuma listagem:** `fetchAll()` traz todas as linhas de todas as tabelas de uma vez, sempre — no boot inicial e a cada evento do Realtime (mesmo que apenas uma linha tenha mudado, debounced em 400ms). Tende a escalar mal conforme o histórico financeiro crescer ao longo dos anos.
11. **Backup depende de ação humana ou da File System Access API** (suportada só em Chrome/Edge desktop) — não há backup automático server-side agendado; sem o usuário configurar a pasta local ou lembrar de exportar manualmente, a única rede de segurança são os backups nativos do próprio Supabase Cloud (se o plano contratado os incluir).
12. **No momento desta análise havia alterações não commitadas em `index.html`** (`git status` reportou `modified: index.html`) — antes de migrar, vale decidir se essas mudanças locais devem ser commitadas ou descartadas, para não perder trabalho em andamento nem confundir o que é "produção" com o que é "local".
13. **A pasta `projetos-externos/` dentro do diretório local** contém outro projeto solto (`ecomerce instrumentos`), sem relação com o Montanha System — está no `.gitignore` (não é versionado), mas convive fisicamente na mesma pasta; não confundir com parte do sistema ao migrar.
14. **Hospedagem de produção do frontend não confirmada nesta análise:** o Dockerfile indica deploy via EasyPanel, mas não há garantia de que essa instância específica de EasyPanel ainda esteja ativa (existe histórico de uma instância EasyPanel/Contabo diferente, usada por outro serviço deste mesmo usuário, que foi cancelada) — confirmar com o usuário a URL de produção atual e as credenciais de deploy antes de assumir que dá para publicar direto.
15. **Sem validação de tamanho/quantidade de imagem** antes de enviar ao Worker/Anthropic no fluxo de importar extrato por foto — o usuário pode enviar várias imagens grandes em sequência sem qualquer feedback de custo ou limite.
16. **Concorrência otimista sem tratamento de conflito:** se dois usuários editarem o mesmo registro ao mesmo tempo, o último `UPDATE` que chegar ao Supabase vence silenciosamente — não há verificação de versão/timestamp otimista em nenhuma tabela.
17. **Logos de cliente ficam como data URL base64 direto na coluna `clients.logo_img`**, sem uso do Supabase Storage — infla o tamanho das linhas e das respostas de `fetchAll()` proporcionalmente ao número/tamanho de logos cadastradas.

---

*Fim do documento. Gerado por leitura direta de `index.html`, `cloudflare-worker/worker.js`, `migrations/*.sql`, `Dockerfile`, `nginx.conf`, `manifest.json`, `sw.js` e histórico do `git log` do repositório `montanha-system`.*
