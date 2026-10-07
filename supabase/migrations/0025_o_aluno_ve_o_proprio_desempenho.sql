-- 0025 — meu_desempenho(): o aluno passa a poder ler o PROPRIO desempenho
--
-- Faltava isso, e a falta tinha consequencia: a area do aluno (app.html) nao
-- tinha de onde tirar nota, entao as notas estavam escritas na mao no
-- arquivo. Um aluno de verdade abria "Simulados" e via 84%, 58% e 76% que
-- nao eram dele -- eram do prototipo.
--
-- desempenho_aluno(uuid) ja existia, mas exige eh_admin(): serve para o
-- painel olhar um aluno, nao para o aluno olhar a si mesmo. Esta nao recebe
-- parametro de aluno NENHUM: le auth.uid() e ponto. Nao existe argumento
-- para trocar de aluno, entao nao existe a classe de bug onde o aluno manda
-- o uuid do colega.
--
-- 'com_detalhe' no resumo e o numero que impede a tela de prometer o que nao
-- tem: so as provas feitas no sistema novo gravam resposta por questao. As
-- 91.242 do legado tem apenas o percentual, porque era so isso que o sistema
-- antigo guardava em quiz_user. Com 'com_detalhe' a tela sabe quando pode
-- mostrar indice de erro por materia e quando tem de dizer que nao da.
-- (Esse detalhe EXISTE no antigo, em quiz_user_question_answer, 1,9 milhao de
-- linhas que nunca foram exportadas -- ver migracao/tabelas-que-nao-vieram.md.
-- Se um dia vierem, 'por_categoria' passa a cobrir o historico tambem, sem
-- mudar nada aqui.)

create or replace function public.meu_desempenho()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare v_eu uuid := auth.uid(); r jsonb;
begin
  if v_eu is null then
    raise exception 'precisa entrar' using errcode='42501';
  end if;

  select jsonb_build_object(
    'resumo', (
      select jsonb_build_object(
        'provas',      count(*),
        'melhor',      max(nota),
        'media',       round(avg(nota))::int,
        'ultima_em',   max(enviada_em),
        'tempo_seg',   sum(duracao_seg),
        'com_detalhe', count(*) filter (
          where exists (select 1 from public.respostas x where x.tentativa_id = t.id))
      ) from public.tentativas t
       where t.aluno_id = v_eu and t.enviada_em is not null),

    -- ultima nota de cada simulado, para a lista de simulados mostrar a nota
    -- do aluno em vez de uma nota inventada
    'por_simulado', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'simulado_id', u.simulado_id, 'nota', u.nota,
               'enviada_em', u.enviada_em, 'provas', u.provas)), '[]'::jsonb)
        from (select distinct on (t.simulado_id)
                     t.simulado_id, t.nota, t.enviada_em,
                     count(*) over (partition by t.simulado_id) as provas
                from public.tentativas t
               where t.aluno_id = v_eu and t.enviada_em is not null
               order by t.simulado_id, t.enviada_em desc) u),

    -- indice de erro por materia. Vem vazio para quem so tem historico do
    -- antigo, e e assim que tem de ser: vazio e honesto, numero inventado nao.
    'por_categoria', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'categoria_id', y.categoria_id, 'nome', y.nome,
               'respondidas', y.n, 'erradas', y.err,
               'erro_pct', round(100.0 * y.err / nullif(y.n,0))::int)
               order by y.err desc), '[]'::jsonb)
        from (select q.categoria_id, c.nome,
                     count(*) as n,
                     count(*) filter (where not rp.correta) as err
                from public.respostas rp
                join public.tentativas t on t.id = rp.tentativa_id
                join public.questoes   q on q.id = rp.questao_id
                left join public.categorias_questao c on c.id = q.categoria_id
               where t.aluno_id = v_eu
               group by q.categoria_id, c.nome) y),

    -- as certificacoes que o aluno acompanha, vindas do sistema antigo
    'trilhas', (
      select coalesce(jsonb_agg(tr.categoria_simulado_id order by tr.categoria_simulado_id), '[]'::jsonb)
        from public.trilhas_do_aluno tr where tr.aluno_id = v_eu),

    'ultimas', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', u.id, 'simulado_id', u.simulado_id, 'nota', u.nota,
               'enviada_em', u.enviada_em, 'duracao_seg', u.duracao_seg,
               'acertos', u.acertos, 'total', u.total, 'origem', u.origem)
               order by u.enviada_em desc), '[]'::jsonb)
        from (select t.* from public.tentativas t
               where t.aluno_id = v_eu and t.enviada_em is not null
               order by t.enviada_em desc limit 20) u)
  ) into r;

  return r;
end $fn$;

revoke execute on function public.meu_desempenho() from public, anon, authenticated;
grant  execute on function public.meu_desempenho() to authenticated;

-- Conferida trocando de papel, com a transacao abortada no fim:
--   anon ................................. barrado, 42501
--   authenticated sem "sub" no JWT ....... barrado, 42501
--   aluno com historico (id antigo 66040)  2 provas, melhor 30, media 25,
--                                          com_detalhe 0, por_categoria []
--   aluno sem nenhuma prova .............. zeros e nulos, sem invencao
-- Nao existe parametro de aluno: nao da para pedir o desempenho de outra
-- pessoa nem trocando o corpo da chamada.
