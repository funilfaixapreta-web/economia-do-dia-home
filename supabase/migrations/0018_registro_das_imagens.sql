-- 0018 — registro das 166 imagens do site antigo
--
-- Eu disse, no balanco da migracao, que as imagens do site antigo nao tinham
-- subido. Estava errado: as 164 que tem arquivo ja estao no Storage, no bucket
-- publico "legado" (22 MB, subidas em 30/09), e as 133 paginas importadas ja
-- apontam para la -- nenhuma pagina ainda referencia economiadodia.com.br.
--
-- O que faltava era so o inventario. Os titulos e os ids do sistema antigo
-- viviam apenas dentro do _legacy_raw, que esta para ser apagado. Esta tabela
-- guarda isso fora dele, e registra onde cada arquivo foi parar.
--
-- Conferencia depois de popular:
--   166 no registro · 164 com arquivo no Storage · 0 com url antiga sem arquivo
--   2 sem url nem no sistema antigo (nao havia o que buscar)
--   0 arquivos no bucket sem linha aqui
--   0 paginas apontando para o servidor antigo
--
-- Com isto, apagar _legacy_raw e _legacy_urls (migracao 0015) nao perde nada.

create table if not exists public.imagens (
  id            text primary key,     -- id no sistema antigo
  url_antiga    text,                 -- onde estava em economiadodia.com.br
  titulo        text,
  caminho       text,                 -- caminho dentro do bucket "legado"
  url_nova      text,                 -- url publica no Storage
  baixada_em    timestamptz,          -- quando o arquivo entrou no Storage
  criado_em     timestamptz not null default now()
);

alter table public.imagens enable row level security;

insert into public.imagens (id, url_antiga, titulo, caminho)
select r.data->>'id',
       nullif(btrim(r.data->>'url'),''),
       nullif(btrim(regexp_replace(coalesce(r.data->>'titulo',''), '\s+', ' ', 'g')),''),
       regexp_replace(coalesce(nullif(btrim(r.data->>'url'),''),''), '^https?://[^/]+/', '')
  from public._legacy_raw r
 where r.src = 'image'
on conflict (id) do nothing;

update public.imagens i
   set url_nova = 'https://ernqeokvkytwdlmjupwm.supabase.co/storage/v1/object/public/legado/'||o.name,
       baixada_em = o.created_at
  from storage.objects o
 where o.bucket_id = 'legado' and o.name = i.caminho;

-- inventario e coisa de administrador: aluno nao tem o que fazer com isto
revoke all on public.imagens from anon, authenticated;
create policy admin_imagens on public.imagens for select using (public.eh_admin());
grant select on public.imagens to authenticated;

-- Conferido com JWT real: aluno ve 0 linhas, admin ve 166, anon e barrado no grant.
