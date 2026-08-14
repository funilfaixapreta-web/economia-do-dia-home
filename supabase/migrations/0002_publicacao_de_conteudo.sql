-- ===========================================================================
-- Economia do Dia · publicacao de conteudo pelo painel
-- ---------------------------------------------------------------------------
-- Ate aqui o painel (adm.html) editava tudo no localStorage do navegador: o
-- material existia so na maquina de quem editou e nunca chegava ao aluno.
--
-- Esta migracao abre o caminho de publicacao:
--   1. campos que faltavam  -> video por LINK e por INCORPORACAO nas aulas
--   2. "ref"                -> chave estavel vinda do painel, para republicar
--                              sem duplicar nada
--   3. publicar_conteudo()  -> recebe o pacote inteiro num jsonb so e grava
--                              cursos, modulos, aulas, categorias, questoes,
--                              alternativas, simulados e composicoes de uma
--                              vez, dentro de UMA transacao e so para admin
--
-- Aplicada no projeto ernqeokvkytwdlmjupwm em 14/08/2026.
-- ===========================================================================

-- ---------------------------------------------------------------- 1. campos
alter table public.cursos
  add column if not exists cor text;

alter table public.modulos
  add column if not exists ref text;

alter table public.aulas
  add column if not exists ref         text,
  add column if not exists descricao   text,
  add column if not exists video_url   text,   -- YouTube, Vimeo ou .mpg direto
  add column if not exists video_embed text;   -- iframe colado pelo painel

alter table public.questoes
  add column if not exists ref          text,
  add column if not exists audio_embed  text,
  add column if not exists regra_acesso text default 'livre';

alter table public.alternativas
  add column if not exists ativo boolean default true;

alter table public.simulados
  add column if not exists slug text;

-- ---------------------------------------------------------------- 2. indices
-- ATENCAO: indice PARCIAL (where ref is not null) nao serve aqui. O Postgres
-- so infere o indice em "on conflict (ref)" se o predicado for repetido na
-- clausula, e o upsert quebra com 42P10. Indice total resolve, e varios NULL
-- continuam permitidos porque NULLs sao distintos por padrao.
create unique index if not exists modulos_ref_uk    on public.modulos(ref);
create unique index if not exists aulas_ref_uk      on public.aulas(ref);
create unique index if not exists questoes_ref_uk   on public.questoes(ref);
create unique index if not exists simulados_slug_uk on public.simulados(slug);

-- uma alternativa por posicao dentro da questao: deixa o upsert ser estavel
create unique index if not exists alternativas_questao_ordem_uk
  on public.alternativas(questao_id, ordem);

-- ------------------------------------------------------------- 3. publicacao
create or replace function public.publicar_conteudo(p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c jsonb; m jsonb; a jsonb; q jsonb; alt jsonb; s jsonb; comp jsonb; cat jsonb;
  v_mod_id uuid; v_q_id uuid; v_n int;
  n_cursos int:=0; n_mods int:=0; n_aulas int:=0;
  n_cats int:=0; n_quest int:=0; n_alts int:=0; n_sims int:=0; n_comp int:=0;
begin
  if not public.eh_admin() then
    raise exception 'apenas administradores podem publicar conteudo'
      using errcode='42501';
  end if;

  ---------------------------------------------------------------- cursos
  for c in select * from jsonb_array_elements(coalesce(p_dados->'cursos','[]'::jsonb)) loop
    insert into public.cursos (id, codigo, titulo, descricao, cor, ordem, ativo)
    values (c->>'id', c->>'codigo', coalesce(c->>'titulo','(sem titulo)'),
            c->>'descricao', c->>'cor',
            coalesce((c->>'ordem')::int,0), coalesce((c->>'ativo')::boolean,true))
    on conflict (id) do update set
      codigo=excluded.codigo, titulo=excluded.titulo, descricao=excluded.descricao,
      cor=excluded.cor, ordem=excluded.ordem, ativo=excluded.ativo;
    n_cursos:=n_cursos+1;

    -------------------------------------------------------------- modulos
    for m in select * from jsonb_array_elements(coalesce(c->'modulos','[]'::jsonb)) loop
      insert into public.modulos (ref, curso_id, titulo, ordem)
      values (m->>'ref', c->>'id', coalesce(m->>'titulo','(sem titulo)'),
              coalesce((m->>'ordem')::int,0))
      on conflict (ref) do update set
        curso_id=excluded.curso_id, titulo=excluded.titulo, ordem=excluded.ordem
      returning id into v_mod_id;
      n_mods:=n_mods+1;

      ------------------------------------------------------------ aulas
      for a in select * from jsonb_array_elements(coalesce(m->'aulas','[]'::jsonb)) loop
        insert into public.aulas (ref, modulo_id, titulo, descricao, duracao_min,
                                  video_id, video_url, video_embed, material_url,
                                  ordem, ativo)
        values (a->>'ref', v_mod_id, coalesce(a->>'titulo','(sem titulo)'),
                a->>'descricao', nullif(a->>'duracao_min','')::int,
                a->>'video_id', a->>'video_url', a->>'video_embed',
                a->>'material_url', coalesce((a->>'ordem')::int,0),
                coalesce((a->>'ativo')::boolean,true))
        on conflict (ref) do update set
          modulo_id=excluded.modulo_id, titulo=excluded.titulo,
          descricao=excluded.descricao, duracao_min=excluded.duracao_min,
          video_id=excluded.video_id, video_url=excluded.video_url,
          video_embed=excluded.video_embed, material_url=excluded.material_url,
          ordem=excluded.ordem, ativo=excluded.ativo;
        n_aulas:=n_aulas+1;
      end loop;
    end loop;
  end loop;

  ---------------------------------------------------- categorias de questao
  for cat in select * from jsonb_array_elements(coalesce(p_dados->'categorias','[]'::jsonb)) loop
    insert into public.categorias_questao (id, nome, ativo)
    values (cat->>'id', coalesce(cat->>'nome','(sem nome)'),
            coalesce((cat->>'ativo')::boolean,true))
    on conflict (id) do update set nome=excluded.nome, ativo=excluded.ativo;
    n_cats:=n_cats+1;
  end loop;

  --------------------------------------------------------------- questoes
  for q in select * from jsonb_array_elements(coalesce(p_dados->'questoes','[]'::jsonb)) loop
    insert into public.questoes (ref, categoria_id, enunciado, comentario,
                                 audio_url, audio_embed, regra_acesso, ativo)
    values (q->>'ref', nullif(q->>'categoria_id',''),
            coalesce(q->>'enunciado','(sem enunciado)'), q->>'comentario',
            q->>'audio_url', q->>'audio_embed',
            case when q->>'regra_acesso' in ('livre','cadastrados','assinantes')
                 then q->>'regra_acesso' else 'livre' end,
            coalesce((q->>'ativo')::boolean,true))
    on conflict (ref) do update set
      categoria_id=excluded.categoria_id, enunciado=excluded.enunciado,
      comentario=excluded.comentario, audio_url=excluded.audio_url,
      audio_embed=excluded.audio_embed, regra_acesso=excluded.regra_acesso,
      ativo=excluded.ativo
    returning id into v_q_id;
    n_quest:=n_quest+1;

    v_n:=0;
    for alt in select * from jsonb_array_elements(coalesce(q->'alternativas','[]'::jsonb)) loop
      insert into public.alternativas (questao_id, ordem, texto, correta, ativo)
      values (v_q_id, v_n, coalesce(alt->>'texto',''),
              coalesce((alt->>'correta')::boolean,false),
              coalesce((alt->>'ativo')::boolean,true))
      on conflict (questao_id, ordem) do update set
        texto=excluded.texto, correta=excluded.correta, ativo=excluded.ativo;
      v_n:=v_n+1; n_alts:=n_alts+1;
    end loop;

    -- sobrou alternativa de uma versao anterior? limpa, menos as ja respondidas
    delete from public.alternativas x
     where x.questao_id=v_q_id and x.ordem>=v_n
       and not exists (select 1 from public.respostas r where r.alternativa_id=x.id);
  end loop;

  -------------------------------------------------------------- simulados
  for s in select * from jsonb_array_elements(coalesce(p_dados->'simulados','[]'::jsonb)) loop
    insert into public.simulados (id, nome, slug, descricao, tempo_limite, corte,
                                  regra_acesso, ativo)
    values (s->>'id', coalesce(s->>'nome','(sem nome)'), nullif(s->>'slug',''),
            s->>'descricao', coalesce((s->>'tempo_limite')::int,60),
            coalesce((s->>'corte')::int,70),
            case when s->>'regra_acesso' in ('livre','cadastrados','assinantes')
                 then s->>'regra_acesso' else 'livre' end,
            coalesce((s->>'ativo')::boolean,true))
    on conflict (id) do update set
      nome=excluded.nome, slug=excluded.slug, descricao=excluded.descricao,
      tempo_limite=excluded.tempo_limite, corte=excluded.corte,
      regra_acesso=excluded.regra_acesso, ativo=excluded.ativo;
    n_sims:=n_sims+1;

    -- a composicao e substituida por inteiro: e a lista que o painel mostra
    delete from public.composicoes where simulado_id = s->>'id';
    for comp in select * from jsonb_array_elements(coalesce(s->'composicao','[]'::jsonb)) loop
      -- categoria inexistente e ignorada em silencio em vez de derrubar tudo
      if coalesce((comp->>'quantidade')::int,0) > 0
         and exists (select 1 from public.categorias_questao k where k.id = comp->>'categoria_id') then
        insert into public.composicoes (simulado_id, categoria_id, quantidade, ativo)
        values (s->>'id', comp->>'categoria_id', (comp->>'quantidade')::int,
                coalesce((comp->>'ativo')::boolean,true))
        on conflict (simulado_id, categoria_id) do update set
          quantidade=excluded.quantidade, ativo=excluded.ativo;
        n_comp:=n_comp+1;
      end if;
    end loop;
  end loop;

  return jsonb_build_object('ok',true,'cursos',n_cursos,'modulos',n_mods,
    'aulas',n_aulas,'categorias',n_cats,'questoes',n_quest,'alternativas',n_alts,
    'simulados',n_sims,'composicoes',n_comp);
end $$;

-- funcao nova nasce com EXECUTE para PUBLIC, e anon herda de PUBLIC: revogar
-- de todo mundo antes e o unico jeito de fechar de verdade
revoke execute on function public.publicar_conteudo(jsonb) from public, anon, authenticated;
grant  execute on function public.publicar_conteudo(jsonb) to authenticated;
