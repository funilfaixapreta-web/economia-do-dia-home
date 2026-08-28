/* ============================================================================
   Economia do Dia · 0010 · a categoria do simulado passa a existir no banco
   ----------------------------------------------------------------------------
   A tela de criar simulado sempre teve o campo "Categoria" (CFG, CNPI-CB...).
   Ele nunca saiu do navegador: publicar_conteudo() nao mandava, e a tabela
   simulados nao tinha onde guardar. Quem preenchia estava preenchendo nada.

   Isso importa porque e por essa categoria que o aluno escolhe o simulado
   pelo curso -- foi justamente o que a reuniao do dia 26 pediu.

   Duas decisoes aqui:

   1. Tabela propria (categorias_simulado) em vez de um texto solto em
      simulados. Assim renomear "CFG" para outra coisa e uma linha, nao um
      update em todos os simulados; e a chave estrangeira impede categoria
      escrita errada.

   2. Na publicacao a categoria e resolvida por subconsulta:

          (select k.id from public.categorias_simulado k
            where k.id = s->>'categoria_id')

      e nao pelo valor cru. Se o painel mandar uma categoria que ainda nao
      existe, o campo fica nulo em vez de a chave estrangeira derrubar a
      publicacao inteira -- 5.110 questoes nao podem parar de subir por causa
      de um nome de categoria.

   A funcao publicar_conteudo() e longa e ja estava certa; em vez de reescrever
   duzentas linhas na mao (e arriscar mudar algo sem querer), a migracao le a
   definicao viva com pg_get_functiondef(), aplica os tres remendos e executa.
   ============================================================================ */

create table if not exists public.categorias_simulado (
  id    text primary key,
  nome  text not null,
  ativo boolean not null default true
);
alter table public.categorias_simulado enable row level security;

drop policy if exists catalogo_cat_sim on public.categorias_simulado;
create policy catalogo_cat_sim on public.categorias_simulado
  for select using (ativo or public.eh_admin());

drop policy if exists admin_cat_sim on public.categorias_simulado;
create policy admin_cat_sim on public.categorias_simulado
  for all using (public.eh_admin()) with check (public.eh_admin());

grant select on public.categorias_simulado to anon, authenticated;

alter table public.simulados
  add column if not exists categoria_id text references public.categorias_simulado(id);

do $mig$
declare v text;
begin
  select pg_get_functiondef(p.oid) into v
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='publicar_conteudo';

  /* 1. grava as categorias ANTES dos simulados: e a chave estrangeira deles */
  v := replace(v,
$a$  -------------------------------------------------------------- simulados$a$,
$b$  ------------------------------------------------- categorias de simulado
  -- vem ANTES dos simulados: e a chave estrangeira deles
  for cat in select * from jsonb_array_elements(coalesce(p_dados->'categorias_simulado','[]'::jsonb)) loop
    insert into public.categorias_simulado (id, nome, ativo)
    values (cat->>'id', coalesce(cat->>'nome','(sem nome)'),
            coalesce((cat->>'ativo')::boolean,true))
    on conflict (id) do update set nome=excluded.nome, ativo=excluded.ativo;
  end loop;

  -------------------------------------------------------------- simulados$b$);

  /* 2. a coluna nova no insert */
  v := replace(v,
$c$(id, nome, slug, descricao, tempo_limite, corte,
                                  regra_acesso, ativo)$c$,
$d$(id, nome, slug, descricao, tempo_limite, corte,
                                  regra_acesso, ativo, categoria_id)$d$);

  v := replace(v,
$e$            coalesce((s->>'ativo')::boolean,true))$e$,
$f$            coalesce((s->>'ativo')::boolean,true),
            -- so grava a categoria se ela existir: assim um painel
            -- desatualizado nao derruba a publicacao inteira
            (select k.id from public.categorias_simulado k
              where k.id = s->>'categoria_id'))$f$);

  /* 3. e no update, senao republicar perderia a categoria */
  v := replace(v,
$g$      regra_acesso=excluded.regra_acesso, ativo=excluded.ativo;$g$,
$h$      regra_acesso=excluded.regra_acesso, ativo=excluded.ativo,
      categoria_id=excluded.categoria_id;$h$);

  execute v;
end $mig$;
