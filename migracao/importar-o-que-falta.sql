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
--
--   truncate public._imp_quiz_user;
--
-- CUIDADO: truncate nao tem volta e o SQL Editor nao pede confirmacao. Antes
-- de rodar, confira que o nome da tabela comeca com _imp_. Ele serve SO para
-- as tres tabelas de recepcao, que sao descartaveis. Nunca em tentativas,
-- matriculas_historico, trilhas_do_aluno ou qualquer tabela de destino -- nessas
-- o dado nao tem de onde voltar. (Eu nao consigo rodar truncate nem delete
-- nesta sessao, e nao e por acidente.)
--
-- Tudo aqui pode ser rodado de novo sem duplicar:
--   tentativas             -> ref_antigo com indice unico
--   matriculas_historico   -> id_antigo e a chave primaria
--   trilhas_do_aluno       -> chave primaria (aluno_id, categoria)
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Nota para quem for rodar consultas no phpMyAdmin: nao cole duas de uma vez.
-- Depois de uma consulta no information_schema, ele executa a seguinte NESSE
-- banco, e a segunda falha com "#1109 Unknown table 'x' in information_schema".
-- Rode uma por vez.
--
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
--
-- elapsed_time ESTA EM MINUTOS, nao em segundos. Conferido no MySQL: int(4),
-- minimo 0, maximo 180, media 15,6, zero nulos. Media de 15,6 segundos seria
-- impossivel para um simulado de 10 a 60 questoes, e um maximo cravado em 180
-- e teto de cronometro de 3 horas. Dai o *60.
--
-- Sem isso, a conversao gravaria 180 SEGUNDOS numa prova que durou 3 HORAS --
-- e seria um erro silencioso, porque segundos e minutos tem a mesma aparencia
-- numa coluna inteira. Nenhuma validacao de formato pegaria.
--
-- elapsed_time = 0 virou nulo, e nao zero. O valor e arredondado para minuto
-- inteiro, entao 0 significa "menos de um minuto", o que mistura prova aberta
-- e fechada na hora com prova respondida em 45 segundos. Gravar 0 segundos
-- afirmaria uma duracao que nao aconteceu. E nada se perde: como a origem nao
-- tem nenhum nulo, toda linha com origem='legado' e duracao_seg nulo e
-- exatamente uma linha que tinha 0 la.
-- ---------------------------------------------------------------------------
insert into public.tentativas
  (aluno_id, simulado_id, iniciada_em, enviada_em, nota, duracao_seg, origem, ref_antigo)
select m.aluno_id,
       'legacy-'||i.quiz_id,
       public._vazio(i.created_at)::timestamptz,
       public._vazio(i.created_at)::timestamptz,
       round(public._vazio(i.hit_percentage)::numeric)::int,
       case when public._vazio(i.elapsed_time) ~ '^[0-9]+$'
            then nullif(public._vazio(i.elapsed_time)::int, 0) * 60
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

-- ===========================================================================
-- PASSO 2 — CONFERENCIA DEPOIS DA TRANSFORMACAO
--
-- Numeros medidos no sistema antigo, no momento do export. Se algum nao
-- bater, o motivo esta na coluna "onde olhar".
-- ===========================================================================
select 'provas importadas'              as item,
       (select count(*) from public.tentativas where origem='legado')::text as achado,
       'ate 91.242'                     as esperado,
       'menos as de aluno sem id mapeado e as de simulado inexistente' as onde_olhar
union all
select 'provas sem tempo (era 0 no antigo)',
       (select count(*) from public.tentativas where origem='legado' and duracao_seg is null)::text,
       '1.605',
       'se der 1.604 ou 1.606, suspeite de elapsed_time alterado no antigo depois do export, antes de suspeitar da conversao'
union all
select 'alunos distintos com historico',
       (select count(distinct aluno_id) from public.tentativas where origem='legado')::text,
       '~3.718',
       'e quantos tem has_quiz=1 no user_csv. Muito acima disso = id casado errado'
union all
select 'log de assinatura',
       (select count(*) from public.matriculas_historico)::text,
       '2.625',
       'id_antigo e a chave primaria, entao nao ha duplicata possivel'
union all
select 'log sem aluno conhecido',
       (select count(*) from public.matriculas_historico where aluno_id is null)::text,
       'poucas',
       'sao os 125 alunos que faltavam no user_list; id_aluno_antigo guarda a referencia'
union all
select 'trilhas',
       (select count(*) from public.trilhas_do_aluno)::text,
       'ate 50.433',
       'menos as de aluno sem id mapeado; a chave primaria tambem dedup aluno+trilha repetida'
union all
select 'trilhas por categoria',
       (select string_agg(categoria_simulado_id||'='||n, ' ' order by n desc)
          from (select categoria_simulado_id, count(*) as n
                  from public.trilhas_do_aluno group by 1) t)::text,
       'cpa-10 17.960 cpa-20 17.213 cea 5.195 ancord 3.239 cnpi-cb 2.306 cnpi-cg1 2.011 cnpi-ct1 1.876 cfg 633',
       'exato para ESTE arquivo (soma 50.433). Numa reimportacao futura vale a regra: cada categoria >= o numero de 02/10, soma das diferencas = vinculos criados depois. Desvio grande em UMA categoria = mapa de quiz_category_id errado';

-- ---------------------------------------------------------------------------
-- Referencia por categoria, e por que ela e uma REGRA e nao uma lista fixa.
--
-- A quebra abaixo foi medida em 02/10 e soma 50.424. O arquivo exportado tem
-- 50.433, porque inclui 9 vinculos criados depois dessa data. Logo a
-- conferencia sai ATE 9 linhas acima, espalhadas pelas trilhas onde esses 9
-- cairam -- e isso e esperado, nao defeito.
--
--   trilha      id antigo   em 02/10   novas   ESPERADO NO ARQUIVO
--   cpa-10          5         17.960       0        17.960
--   cpa-20          1         17.213       0        17.213
--   cea             2          5.195       0         5.195
--   ancord          6          3.239       0         3.239
--   cnpi-cb         8          2.303       3         2.306
--   cnpi-cg1        9          2.009       2         2.011
--   cnpi-ct1       10          1.872       4         1.876
--   cfg            11            633       0           633
--                                                   -------
--                                                    50.433  = linhas do arquivo
--
-- Os 9 vinculos novos caíram todos em CNPI (cb 3, cg1 2, ct1 4). A coluna
-- ESPERADO e exata para este arquivo: use-a para conferir linha a linha.
--
-- Como ler: cada categoria tem de ficar MAIOR OU IGUAL ao numero acima, e a
-- soma de todas as diferencas tem de ser igual ao numero de vinculos criados
-- depois de 02/10. Assim um mapa de quiz_category_id errado continua
-- aparecendo (desvio grande concentrado numa categoria) sem que o crescimento
-- normal do sistema antigo dispare alarme falso.
--
-- Quem repetir esta importacao no futuro: refaca a quebra no antigo em vez de
-- confiar nos numeros acima, porque eles envelhecem a cada cadastro novo.
-- ---------------------------------------------------------------------------

-- Depois que isto fechar, estas podem ser apagadas pelo SQL Editor do painel:
--   truncate public._imp_quiz_user;
--   truncate public._imp_subscription_log;
--   truncate public._imp_user_quiz_category;
--   drop table public._imp_quiz_user, public._imp_subscription_log, public._imp_user_quiz_category;
-- e, so depois, as da migracao 0015 (_legacy_raw, _legacy_map, _legacy_urls).
