-- ===========================================================================
-- Transformacao do que falta: quiz_user, subscription_log, user_quiz_category
--
-- Pre-requisito: os tres CSVs ja carregados nas tabelas de recepcao
-- _imp_quiz_user, _imp_subscription_log e _imp_user_quiz_category pelo
-- Table Editor do Supabase (Import data from CSV).
--
-- As tabelas de recepcao tem TODAS as colunas em text de proposito: CSV do
-- MySQL traz data como 'YYYY-MM-DD HH:MM:SS', o export veio com "Replace NULL
-- with: NULL" (campo vazio chega como a PALAVRA NULL) e elapsed_time pode ser
-- segundos ou HH:MM:SS. A conversao acontece aqui, onde da para conferir.
--
-- Cada _imp_ tem id como chave primaria. Isso e proposital: um reenvio do
-- mesmo arquivo FALHA em vez de duplicar silenciosamente. Se uma carga parar
-- no meio, limpe antes de tentar de novo, pelo SQL Editor do painel:
--   truncate public._imp_quiz_user;
-- (eu nao consigo rodar truncate nem delete nesta sessao.)
--
-- Tudo aqui pode ser rodado de novo sem duplicar:
--   tentativas             -> ref_antigo com indice unico
--   matriculas_historico   -> id_antigo e a chave primaria
--   trilhas_do_aluno       -> chave primaria (aluno_id, categoria)
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- PASSO 0 — CONFERIR A CARGA ANTES DE TRANSFORMAR.
-- Pega upload que parou no meio e upload duplicado. Nao siga se algum
-- "confere" vier false.
-- ---------------------------------------------------------------------------
select 'quiz_user' as tabela, count(*) as carregadas, 91242 as esperado,
       count(*) = 91242 as confere from public._imp_quiz_user
union all
select 'subscription_log', count(*), 2625, count(*) = 2625 from public._imp_subscription_log
union all
select 'user_quiz_category', count(*), 50433, count(*) = 50433 from public._imp_user_quiz_category;

-- helper: o CSV traz nulo como a palavra NULL, em qualquer caixa, e \N
create or replace function public._vazio(t text) returns text
language sql immutable as $fn$
  select case
    when t is null then null
    when btrim(t) = '' then null
    when upper(btrim(t)) in ('NULL','\N','NIL','\\N') then null
    else btrim(t)
  end;
$fn$;

-- ---------------------------------------------------------------------------
-- 1) HISTORICO DE PROVA  ->  tentativas (origem='legado')
--
-- O antigo guarda hit_percentage e elapsed_time, nao acertos nem total: a
-- nota vem completa e acertos/total ficam nulos. Nao ha como derivar acertos
-- sem saber quantas questoes a prova tinha naquele dia.
--
-- iniciada_em recebe o created_at junto com enviada_em: o antigo registra um
-- instante so, e nao da para saber se era o inicio ou a entrega. O tempo real
-- fica em duracao_seg.
-- ---------------------------------------------------------------------------
insert into public.tentativas
  (aluno_id, simulado_id, iniciada_em, enviada_em, nota, duracao_seg, origem, ref_antigo)
select m.aluno_id,
       'legacy-'||i.quiz_id,
       public._vazio(i.created_at)::timestamptz,
       public._vazio(i.created_at)::timestamptz,
       round(public._vazio(i.hit_percentage)::numeric)::int,
       case
         when public._vazio(i.elapsed_time) ~ '^[0-9]+$'
           then public._vazio(i.elapsed_time)::int
         when public._vazio(i.elapsed_time) ~ '^[0-9]+:[0-9]{2}:[0-9]{2}$'
           then extract(epoch from public._vazio(i.elapsed_time)::interval)::int
         else null
       end,
       'legado',
       i.id
  from public._imp_quiz_user i
  join public._mapa_aluno m on m.id_antigo = public._vazio(i.user_id)
  join public.simulados  s on s.id = 'legacy-'||public._vazio(i.quiz_id)
 where public._vazio(i.deleted_at) is null
   and public._vazio(i.created_at) is not null
   and public._vazio(i.hit_percentage) is not null
on conflict (ref_antigo) where ref_antigo is not null do nothing;

-- ---------------------------------------------------------------------------
-- 2) LOG DE ASSINATURA  ->  matriculas_historico
--    Historico puro. aluno_id fica nulo quando o id antigo nao e conhecido,
--    e id_aluno_antigo guarda o numero para nao perder a referencia.
-- ---------------------------------------------------------------------------
insert into public.matriculas_historico
  (id_antigo, assinatura_antiga, aluno_id, id_aluno_antigo, plano_id,
   expira_em, ativa_no_antigo, registrado_em)
select i.id,
       public._vazio(i.subscription_id),
       m.aluno_id,
       public._vazio(i.user_id),
       case when public._vazio(i.plan_id) is not null
            then 'legacy-'||public._vazio(i.plan_id) end,
       public._vazio(i.expiration_at)::timestamptz,
       public._vazio(i.is_active) in ('1','true','t'),
       public._vazio(i.created_at)::timestamptz
  from public._imp_subscription_log i
  left join public._mapa_aluno m on m.id_antigo = public._vazio(i.user_id)
 where public._vazio(i.deleted_at) is null
on conflict (id_antigo) do nothing;

-- ---------------------------------------------------------------------------
-- 3) TRILHAS DO ALUNO  ->  trilhas_do_aluno
--    O mapa de categoria vai literal aqui, e nao via _legacy_map, para esta
--    importacao nao depender de uma tabela que vai ser apagada.
-- ---------------------------------------------------------------------------
insert into public.trilhas_do_aluno (aluno_id, categoria_simulado_id, origem)
select distinct m.aluno_id, z.novo, 'legado'
  from public._imp_user_quiz_category i
  join public._mapa_aluno m on m.id_antigo = public._vazio(i.user_id)
  join (values ('1','cpa-20'),('2','cea'),('5','cpa-10'),('6','ancord'),
               ('8','cnpi-cb'),('9','cnpi-cg1'),('10','cnpi-ct1'),('11','cfg')
       ) as z(antigo, novo) on z.antigo = public._vazio(i.quiz_category_id)
 where public._vazio(i.deleted_at) is null
on conflict (aluno_id, categoria_simulado_id) do nothing;
