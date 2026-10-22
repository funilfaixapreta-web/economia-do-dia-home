-- 0028 — o painel passa a enxergar o video que ESTA PUBLICADO
--
-- A tela "Videos das aulas" nasceu lendo so o localStorage do navegador, que
-- e o rascunho do painel. Resultado: mostrava as aulas de demonstracao do
-- prototipo e nao tinha como saber o que esta no ar -- duas maquinas
-- mostrariam listas diferentes, e nenhuma seria o banco. Com 314 aulas
-- publicadas, a tela dizia 7.
--
-- Pelo PostgREST nao da para resolver: video_url, video_embed e video_id NAO
-- estao no grant de coluna de aulas (anon e authenticated so leem id, ref,
-- modulo_id, titulo, descricao, duracao_min, ordem, ativo). Isso e de
-- proposito e continua: link de video nao pode sair numa listagem, senao a
-- cobranca da ver_aula() nao vale nada.
--
-- Entao a leitura vem por aqui, com eh_admin() por dentro -- mesmo padrao de
-- questoes_admin(), usuarios_admin() e pedidos_admin().
--
-- 'host' sai pronto do banco de proposito: a tela precisa dizer "veed.io", e
-- extrair isso em JS em tres lugares diferentes so cria divergencia entre o
-- que o painel mostra e o que o aluno recebe.

create or replace function public.aulas_admin()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare r jsonb;
begin
  if not public.eh_admin() then
    raise exception 'apenas administradores' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(x order by x->>'curso', (x->>'ordem_mod')::int, (x->>'ordem')::int), '[]'::jsonb)
    into r
    from (
      select jsonb_build_object(
        'aula_id',    a.id,
        'ref',        a.ref,
        'titulo',     a.titulo,
        'duracao',    a.duracao_min,
        'ativo',      a.ativo,
        'ordem',      coalesce(a.ordem,0),
        'curso_id',   c.id,
        'curso',      c.titulo,
        'modulo',     m.titulo,
        'ordem_mod',  coalesce(m.ordem,0),
        'video_url',   a.video_url,
        'video_embed', a.video_embed,
        'video_id',    a.video_id,
        'host', nullif(regexp_replace(
                  coalesce(
                    substring(a.video_embed from 'src=["'']https?://([^/"''?]+)'),
                    substring(a.video_url   from 'https?://([^/"''?]+)')
                  ), '^www\.', ''), '')
      ) as x
      from public.aulas a
      join public.modulos m on m.id = a.modulo_id
      join public.cursos  c on c.id = m.curso_id
    ) z;

  return r;
end $fn$;

revoke execute on function public.aulas_admin() from public, anon, authenticated;
grant  execute on function public.aulas_admin() to authenticated;

-- Conferida trocando de papel: aluno comum barrado (42501), admin recebe as
-- 314 aulas. O retrato do banco no dia:
--   314 aulas, 4 cursos, 42 modulos, 100% com video, todas ativas
--   todas em veed.io, todas por incorporacao
--   314 ids de video DISTINTOS -- nenhuma aula apontando para o video de
--     outra, que seria o erro invisivel desse tipo de migracao
--   os mesmos parametros nas 314 (watermark=0&color=&sharing=0&title=0)
--   zero embed sem iframe, zero http, zero script, zero sem allowfullscreen
