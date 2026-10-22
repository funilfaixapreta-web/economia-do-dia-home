-- 0032 — tirar unaccent_simples() da criar_curso()
--
-- Repeti o erro da 0030 na migracao seguinte: chamei funcao que nao existe.
-- Desta vez sem aluno no caminho -- criar_curso() e nova, so admin, e nunca
-- tinha sido chamada -- mas quebraria na primeira vez que alguem criasse um
-- curso sem informar o id.
--
-- unaccent precisa da extensao homonima, que este projeto nao tem. translate()
-- e nucleo do Postgres e resolve para titulo em portugues.
--
-- O id do curso aparece na URL do aluno. Gerar "analise-tecnica" e nao
-- "an-lise-t-cnica" nao e preciosismo: e o endereco que vai para o Google.

create or replace function public.criar_curso(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare v_id text; v_ordem int;
begin
  if not public.eh_admin() then
    raise exception 'apenas administradores' using errcode='42501';
  end if;
  if nullif(btrim(coalesce(p->>'titulo','')),'') is null then
    return jsonb_build_object('ok',false,'motivo','sem-titulo');
  end if;

  v_id := nullif(btrim(coalesce(p->>'curso_id','')),'');
  if v_id is null then
    v_id := lower(translate(p->>'titulo',
              'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
              'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN'));
    v_id := trim(both '-' from regexp_replace(v_id, '[^a-z0-9]+', '-', 'g'));
    if v_id = '' then v_id := 'curso'; end if;
  end if;
  if exists (select 1 from public.cursos where id = v_id) then
    v_id := v_id||'-'||substr(replace(gen_random_uuid()::text,'-',''),1,5);
  end if;

  select coalesce(max(ordem),-1)+1 into v_ordem from public.cursos;
  insert into public.cursos (id, codigo, titulo, descricao, cor, ordem, ativo)
  values (v_id, nullif(p->>'codigo',''), btrim(p->>'titulo'),
          nullif(p->>'descricao',''), nullif(p->>'cor',''), v_ordem,
          coalesce((p->>'ativo')::boolean,false));
  return jsonb_build_object('ok',true,'curso_id',v_id);
end $fn$;

revoke execute on function public.criar_curso(jsonb) from public, anon, authenticated;
grant  execute on function public.criar_curso(jsonb) to authenticated;

-- Conferido: 'Análise Técnica Avançada ção' -> 'analise-tecnica-avancada-cao'
