-- ===========================================================================
-- Economia do Dia · fecha o gabarito e passa a prova a ser feita pelo banco
-- ---------------------------------------------------------------------------
-- O PROBLEMA
-- As politicas de RLS liberavam a LINHA inteira da questao e da alternativa
-- para o aluno que tem aquela questao na prova. Linha inteira inclui
-- alternativas.correta e questoes.comentario — ou seja, o gabarito ficava a um
-- F12 de distancia ANTES de o aluno entregar a prova. Simulado com gabarito
-- visivel nao vale nada.
--
-- A CORRECAO
-- RLS filtra LINHA, nao COLUNA. Quem filtra coluna e o privilegio de coluna.
-- Entao o aluno perde o direito de ler essas duas colunas direto pela API, e
-- passa a receber a prova (sem gabarito) e a correcao (com gabarito, so depois
-- de entregue) por funcoes SECURITY DEFINER:
--
--   montar_simulado(sim)              -> sorteia e devolve a prova SEM gabarito
--   enviar_tentativa(tent, respostas) -> corrige no servidor e devolve o result
--   gabarito_tentativa(tent)          -> revisao comentada, so apos entregar
--
-- Aplicada no projeto ernqeokvkytwdlmjupwm em 14/08/2026.
-- ===========================================================================

-- ------------------------------------------------------ 1. tranca as colunas
-- "grant select on tabela" da a tabela toda. Para tirar so duas colunas e
-- preciso revogar tudo e devolver a lista explicita.
revoke select on public.alternativas from anon, authenticated;
grant  select (id, questao_id, texto, ordem, ativo)
  on public.alternativas to anon, authenticated;

revoke select on public.questoes from anon, authenticated;
grant  select (id, categoria_id, enunciado, audio_url, audio_embed,
               regra_acesso, ativo, ref, criada_em)
  on public.questoes to anon, authenticated;

-- ------------------------------------------------------ 2. comecar a prova
-- Sorteia as questoes conforme a composicao do simulado, abre a tentativa e
-- devolve a prova SEM gabarito. As questoes sorteadas ficam gravadas em
-- respostas (ainda em branco): e isso que prende a prova daquele aluno e faz
-- a politica questao_em_prova enxergar so as questoes dele.
create or replace function public.montar_simulado(p_sim text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_aluno uuid := auth.uid();
  v_sim   public.simulados%rowtype;
  v_tent  uuid;
  v_qtd   int;
begin
  select * into v_sim from public.simulados where id = p_sim and ativo;
  if not found then
    return jsonb_build_object('ok',false,'motivo','simulado-nao-encontrado');
  end if;

  if v_sim.regra_acesso in ('cadastrados','assinantes') and v_aluno is null then
    return jsonb_build_object('ok',false,'motivo','precisa-entrar');
  end if;

  if v_sim.regra_acesso = 'assinantes' and not public.eh_admin()
     and not exists (select 1 from public.matriculas m
                      where m.aluno_id = v_aluno and m.ativa
                        and (m.expira_em is null or m.expira_em > now())) then
    return jsonb_build_object('ok',false,'motivo','so-assinantes');
  end if;

  -- prova precisa de dono: e o que permite corrigir e guardar o desempenho
  if v_aluno is null then
    return jsonb_build_object('ok',false,'motivo','precisa-entrar');
  end if;

  insert into public.tentativas (aluno_id, simulado_id)
  values (v_aluno, p_sim) returning id into v_tent;

  -- sorteio por categoria, respeitando a quantidade pedida na composicao
  insert into public.respostas (tentativa_id, questao_id)
  select v_tent, q.id
    from public.composicoes c
    cross join lateral (
      select id from public.questoes
       where categoria_id = c.categoria_id and ativo
       order by random() limit c.quantidade
    ) q
   where c.simulado_id = p_sim and c.ativo;

  select count(*) into v_qtd from public.respostas where tentativa_id = v_tent;
  if v_qtd = 0 then
    delete from public.tentativas where id = v_tent;
    return jsonb_build_object('ok',false,'motivo','sem-questoes');
  end if;

  update public.tentativas set total = v_qtd where id = v_tent;

  return jsonb_build_object(
    'ok', true,
    'tentativa', v_tent,
    'nome', v_sim.nome,
    'tempo_limite', v_sim.tempo_limite,
    'corte', v_sim.corte,
    'total', v_qtd,
    'questoes', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', q.id,
               'enunciado', q.enunciado,
               'audio_embed', q.audio_embed,
               -- repare: nem "correta", nem "comentario"
               'alternativas', (
                 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'texto',a.texto)
                                           order by a.ordem),'[]'::jsonb)
                   from public.alternativas a
                  where a.questao_id = q.id and a.ativo)
             )),'[]'::jsonb)
        from public.respostas r join public.questoes q on q.id = r.questao_id
       where r.tentativa_id = v_tent)
  );
end $$;

-- ------------------------------------------------------ 3. entregar a prova
-- Corrige no servidor. O aluno manda so o que escolheu; quem sabe a resposta
-- certa e o banco.
create or replace function public.enviar_tentativa(p_tentativa uuid, p_respostas jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_aluno uuid := auth.uid();
  v_t     public.tentativas%rowtype;
  v_ac    int;
  v_tot   int;
  v_nota  int;
begin
  select * into v_t from public.tentativas where id = p_tentativa;
  if not found or v_t.aluno_id is distinct from v_aluno then
    return jsonb_build_object('ok',false,'motivo','tentativa-nao-e-sua');
  end if;
  if v_t.enviada_em is not null then
    return jsonb_build_object('ok',false,'motivo','ja-entregue');
  end if;

  -- grava so o que pertence a esta tentativa; questao de fora e ignorada
  update public.respostas r
     set alternativa_id = e.alternativa_id,
         correta = coalesce((select a.correta from public.alternativas a
                              where a.id = e.alternativa_id
                                and a.questao_id = r.questao_id), false)
    from (select (x->>'questao_id')::uuid   as questao_id,
                 nullif(x->>'alternativa_id','')::uuid as alternativa_id
            from jsonb_array_elements(coalesce(p_respostas,'[]'::jsonb)) x) e
   where r.tentativa_id = p_tentativa and r.questao_id = e.questao_id;

  -- quem ficou em branco conta como erro, nao como pendencia
  update public.respostas set correta = false
   where tentativa_id = p_tentativa and correta is null;

  select count(*) filter (where correta), count(*)
    into v_ac, v_tot
    from public.respostas where tentativa_id = p_tentativa;

  v_nota := case when v_tot > 0 then round(v_ac * 100.0 / v_tot) else 0 end;

  update public.tentativas
     set enviada_em = now(), acertos = v_ac, total = v_tot, nota = v_nota
   where id = p_tentativa;

  return public.gabarito_tentativa(p_tentativa);
end $$;

-- ------------------------------------------------------ 4. rever a prova
-- Gabarito comentado. So sai de tentativa ja entregue, e so para o dono
-- (ou para o admin).
create or replace function public.gabarito_tentativa(p_tentativa uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_t public.tentativas%rowtype;
begin
  select * into v_t from public.tentativas where id = p_tentativa;
  if not found then
    return jsonb_build_object('ok',false,'motivo','tentativa-nao-encontrada');
  end if;
  if v_t.aluno_id is distinct from auth.uid() and not public.eh_admin() then
    return jsonb_build_object('ok',false,'motivo','tentativa-nao-e-sua');
  end if;
  if v_t.enviada_em is null then
    return jsonb_build_object('ok',false,'motivo','ainda-nao-entregue');
  end if;

  return jsonb_build_object(
    'ok', true,
    'tentativa', v_t.id,
    'acertos', v_t.acertos, 'total', v_t.total, 'nota', v_t.nota,
    'aprovado', v_t.nota >= coalesce((select corte from public.simulados
                                       where id = v_t.simulado_id), 70),
    'questoes', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', q.id,
               'enunciado', q.enunciado,
               'comentario', q.comentario,
               'audio_embed', q.audio_embed,
               'marcada', r.alternativa_id,
               'acertou', coalesce(r.correta,false),
               'alternativas', (
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'id',a.id,'texto',a.texto,'correta',a.correta)
                          order by a.ordem),'[]'::jsonb)
                   from public.alternativas a
                  where a.questao_id = q.id and a.ativo)
             )),'[]'::jsonb)
        from public.respostas r join public.questoes q on q.id = r.questao_id
       where r.tentativa_id = p_tentativa)
  );
end $$;

-- funcao nova nasce com EXECUTE para PUBLIC (e anon herda de PUBLIC): as tres
-- precisam ser fechadas na mao, senao qualquer visitante chama pela API REST
revoke execute on function public.montar_simulado(text)         from public, anon, authenticated;
revoke execute on function public.enviar_tentativa(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.gabarito_tentativa(uuid)      from public, anon, authenticated;
grant  execute on function public.montar_simulado(text)         to authenticated;
grant  execute on function public.enviar_tentativa(uuid, jsonb) to authenticated;
grant  execute on function public.gabarito_tentativa(uuid)      to authenticated;
