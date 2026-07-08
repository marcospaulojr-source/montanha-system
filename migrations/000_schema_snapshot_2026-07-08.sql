--
-- PostgreSQL database dump
--

-- Dumped from database version 15.8
-- Dumped by pg_dump version 15.8

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: app_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_config (
    id integer DEFAULT 1 NOT NULL,
    gcal_client_id text DEFAULT ''::text,
    reserve_bancos jsonb DEFAULT '[]'::jsonb,
    CONSTRAINT single_row CHECK ((id = 1))
);


--
-- Name: clients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clients (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text DEFAULT 'Novo Cliente'::text NOT NULL,
    sub text DEFAULT 'Painel de Conteúdo'::text NOT NULL,
    accent text DEFAULT '#EF7B24'::text NOT NULL,
    logo text DEFAULT 'N'::text NOT NULL,
    logo_img text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    responsavel text DEFAULT ''::text NOT NULL,
    telefone text DEFAULT ''::text NOT NULL,
    email text DEFAULT ''::text NOT NULL,
    instagram text DEFAULT ''::text NOT NULL,
    razao_social text DEFAULT ''::text NOT NULL,
    cnpj text DEFAULT ''::text NOT NULL,
    endereco text DEFAULT ''::text NOT NULL,
    valor_mensal numeric DEFAULT 0 NOT NULL,
    dia_vencimento integer,
    data_inicio_contrato date,
    status text DEFAULT 'ativo'::text NOT NULL,
    observacoes text DEFAULT ''::text NOT NULL
);


--
-- Name: financeiro; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.financeiro (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tipo text NOT NULL,
    descricao text DEFAULT ''::text,
    cliente text DEFAULT ''::text,
    valor numeric(12,2) DEFAULT 0 NOT NULL,
    forma_pagamento text DEFAULT 'pix'::text NOT NULL,
    banco text DEFAULT ''::text,
    vencimento date,
    status text DEFAULT 'pendente'::text NOT NULL,
    data_pagamento date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    desconto numeric(12,2) DEFAULT 0,
    CONSTRAINT financeiro_status_check CHECK ((status = ANY (ARRAY['pendente'::text, 'pago'::text]))),
    CONSTRAINT financeiro_tipo_check CHECK ((tipo = ANY (ARRAY['entrada'::text, 'saida'::text])))
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    can_view_financeiro boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: propostas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.propostas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cliente text DEFAULT ''::text NOT NULL,
    cliente_email text DEFAULT ''::text NOT NULL,
    titulo text DEFAULT ''::text NOT NULL,
    data date,
    validade_dias integer DEFAULT 30 NOT NULL,
    servicos jsonb DEFAULT '[]'::jsonb NOT NULL,
    equipamentos jsonb DEFAULT '[]'::jsonb NOT NULL,
    investimento numeric DEFAULT 0 NOT NULL,
    observacoes text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: saldos_iniciais; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.saldos_iniciais (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    banco text NOT NULL,
    valor numeric(12,2) DEFAULT 0 NOT NULL,
    data date DEFAULT CURRENT_DATE NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: videos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.videos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id uuid NOT NULL,
    cliente text DEFAULT ''::text,
    titulo text DEFAULT ''::text NOT NULL,
    objetivo text DEFAULT 'redes_sociais'::text NOT NULL,
    estagio text DEFAULT 'agendado'::text NOT NULL,
    inicio date,
    entrega date,
    roteiro text DEFAULT ''::text,
    mods text DEFAULT ''::text,
    enviado boolean DEFAULT false NOT NULL,
    data_envio date,
    gcal_event_id text,
    historico jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    editor text DEFAULT ''::text,
    descricao_servico text DEFAULT ''::text
);


--
-- Name: app_config app_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_config
    ADD CONSTRAINT app_config_pkey PRIMARY KEY (id);


--
-- Name: clients clients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_pkey PRIMARY KEY (id);


--
-- Name: financeiro financeiro_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.financeiro
    ADD CONSTRAINT financeiro_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: propostas propostas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.propostas
    ADD CONSTRAINT propostas_pkey PRIMARY KEY (id);


--
-- Name: saldos_iniciais saldos_iniciais_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saldos_iniciais
    ADD CONSTRAINT saldos_iniciais_pkey PRIMARY KEY (id);


--
-- Name: videos videos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.videos
    ADD CONSTRAINT videos_pkey PRIMARY KEY (id);


--
-- Name: videos_client_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX videos_client_id_idx ON public.videos USING btree (client_id);


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: videos videos_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.videos
    ADD CONSTRAINT videos_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE CASCADE;


--
-- Name: app_config; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

--
-- Name: clients authenticated_all_clients; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_all_clients ON public.clients USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: app_config authenticated_all_config; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_all_config ON public.app_config USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: propostas authenticated_all_propostas; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_all_propostas ON public.propostas USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: videos authenticated_all_videos; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_all_videos ON public.videos USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: clients; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;

--
-- Name: financeiro; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.financeiro ENABLE ROW LEVEL SECURITY;

--
-- Name: financeiro financeiro_by_permission; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY financeiro_by_permission ON public.financeiro USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND profiles.can_view_financeiro)))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND profiles.can_view_financeiro))));


--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: propostas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.propostas ENABLE ROW LEVEL SECURITY;

--
-- Name: saldos_iniciais saldos_by_permission; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY saldos_by_permission ON public.saldos_iniciais USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND profiles.can_view_financeiro)))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND profiles.can_view_financeiro))));


--
-- Name: saldos_iniciais; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.saldos_iniciais ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles self_read_profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY self_read_profile ON public.profiles FOR SELECT USING ((auth.uid() = id));


--
-- Name: videos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.videos ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

