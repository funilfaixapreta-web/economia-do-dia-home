-- ===========================================================================
-- Economia do Dia
--   1) Catalogo aberto, video fechado
--   2) Admin por convite de e-mail
--   3) catalogo(): tudo que o site monta na tela, numa chamada so
--
-- Aplicada no projeto ernqeokvkytwdlmjupwm em 14/08/2026.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. AULAS
-- O PROBLEMA: a politica aula_liberada escondia a LINHA INTEIRA da aula de
-- quem nao comprou o curso. Com o modelo de tokens isso quebra o produto — o
-- aluno precisa VER a lista de aulas para escolher qual vai destravar com os
-- tokens dele. Do jeito antigo, o curso aparecia vazio.
--
-- E o mesmo erro do gabarito: RLS filtra LINHA, e o que precisamos filtrar e
-- COLUNA. Titulo e duracao viram catalogo publico; o link do video sai so
-- pela ver_aula(), que confere quem esta pedindo.
-- ---------------------------------------------------------------------------
drop policy if exists aula_liberada on public.aulas;
create policy catalogo_aulas on public.aulas for select
  using (ativo or public.eh_admin());

revoke select on public.aulas from anon, authenticated;
grant  select (id, ref, modulo_id, titulo, descricao, duracao_min, ordem, ativo)
  on public.aulas to anon, authenticated;

-- Entrega o video de UMA aula, e so para quem pode: admin, quem tem o curso,
-- ou quem ja gastou token naquela aula (liberacoes).
create or replace function public.ver_aula(p_aula uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_curso text; v_ok boolean;
  v_titulo text; v_url text; v_embed text; v_vid text; v_mat text;
begin
  select m.curso_id, a.titulo, a.video_url, a.video_embed, a.video_id, a.material_url
    into v_curso, v_titulo, v_url, v_embed, v_vid, v_mat
    from public.aulas a join public.modulos m on m.id = a.modulo_id
   where a.id = p_aula and a.ativo;
  if not found then
    return jsonb_build_object('ok',false,'motivo','aula-nao-encontrada');
  end if;

  v_ok := public.eh_admin()
       or public.tem_acesso_curso(v_curso)
       or exists (select 1 from public.liberacoes l
                   where l.aluno_id = auth.uid()
                     and l.tipo = 'aula' and l.item_id = p_aula::text);

  if not v_ok then
    return jsonb_build_object('ok',false,'motivo',
      case when auth.uid() is null then 'precisa-entrar' else 'sem-acesso' end);
  end if;

  return jsonb_build_object('ok',true,'id',p_aula,'titulo',v_titulo,
    'video_url',v_url,'video_embed',v_embed,
    'video_id',v_vid,'material_url',v_mat);
end $$;

revoke execute on function public.ver_aula(uuid) from public, anon, authenticated;
grant  execute on function public.ver_aula(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. ADMIN POR CONVITE
-- Nao da para criar um admin sem a senha do dono da conta, e senha conhecida
-- em producao nao presta. Entao a lista de e-mails convidados fica no banco:
-- quem se cadastrar pelo site com um desses e-mails ja nasce admin, sem
-- ninguem digitar senha em lugar nenhum.
-- ---------------------------------------------------------------------------
create table if not exists public.admins_convidados (
  email      text primary key,
  papel      text not null default 'admin'
             check (papel in ('admin','editor')),
  criado_em  timestamptz not null default now()
);
alter table public.admins_convidados enable row level security;
drop policy if exists admin_convidados on public.admins_convidados;
create policy admin_convidados on public.admins_convidados
  for all using (public.eh_admin()) with check (public.eh_admin());

create or replace function public.ao_criar_usuario()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_ini int; v_papel text;
begin
  select inicial into v_ini from public.config_tokens where id;

  -- e-mail convidado ja entra com o papel combinado
  select papel into v_papel from public.admins_convidados
   where lower(email) = lower(coalesce(new.email,''));

  insert into public.alunos (id, nome, email, telefone, telefone_verificado_em, papel)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'nome', split_part(coalesce(new.email,'aluno'),'@',1)),
          new.email, new.phone, new.phone_confirmed_at,
          coalesce(v_papel,'aluno'));

  insert into public.carteiras (aluno_id, saldo, base, competencia)
  values (new.id, v_ini, v_ini, to_char(now(),'YYYY-MM'));

  insert into public.movimentos (aluno_id, quantidade, motivo)
  values (new.id, v_ini, 'credito-inicial');

  return new;
end $$;

-- Promove quem JA tem conta e deixa o convite pronto para quem ainda nao tem.
create or replace function public.promover_admin(p_email text, p_papel text default 'admin')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_n int;
begin
  if not public.eh_admin() then
    raise exception 'apenas administradores podem promover' using errcode='42501';
  end if;
  if p_papel not in ('admin','editor') then
    return jsonb_build_object('ok',false,'motivo','papel-invalido');
  end if;

  insert into public.admins_convidados (email, papel)
  values (lower(trim(p_email)), p_papel)
  on conflict (email) do update set papel = excluded.papel;

  update public.alunos set papel = p_papel
   where lower(email) = lower(trim(p_email));
  get diagnostics v_n = row_count;

  return jsonb_build_object('ok',true,'convite',true,'ja_tinha_conta',v_n>0);
end $$;

revoke execute on function public.promover_admin(text,text) from public, anon, authenticated;
grant  execute on function public.promover_admin(text,text) to authenticated;

-- O primeiro convite: sem ele nao existe admin nenhum e ninguem publica nada.
insert into public.admins_convidados (email, papel)
values ('admin@economiadodia.com.br','admin')
on conflict (email) do nothing;

-- ---------------------------------------------------------------------------
-- 3. CATALOGO
-- Uma chamada devolve tudo que o site monta na tela. Sem video, sem gabarito.
-- "tem_video" existe para a tela saber se mostra o play, sem entregar o link.
-- ---------------------------------------------------------------------------
create or replace function public.catalogo()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'cursos', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id',c.id,'codigo',c.codigo,'titulo',c.titulo,'descricao',c.descricao,
        'cor',c.cor,'ordem',c.ordem,
        'modulos',(
          select coalesce(jsonb_agg(jsonb_build_object(
            'ref',m.ref,'titulo',m.titulo,'ordem',m.ordem,
            'aulas',(
              select coalesce(jsonb_agg(jsonb_build_object(
                'id',a.id,'ref',a.ref,'titulo',a.titulo,'descricao',a.descricao,
                'duracao_min',a.duracao_min,'ordem',a.ordem,
                'tem_video',(a.video_url is not null or a.video_embed is not null
                             or a.video_id is not null))
                order by a.ordem),'[]'::jsonb)
              from public.aulas a where a.modulo_id = m.id and a.ativo))
            order by m.ordem),'[]'::jsonb)
          from public.modulos m where m.curso_id = c.id))
        order by c.ordem),'[]'::jsonb)
      from public.cursos c where c.ativo),
    'simulados', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id',s.id,'nome',s.nome,'slug',s.slug,'descricao',s.descricao,
        'tempo_limite',s.tempo_limite,'corte',s.corte,
        'regra_acesso',s.regra_acesso,
        'questoes',(select coalesce(sum(k.quantidade),0) from public.composicoes k
                     where k.simulado_id = s.id and k.ativo))
        order by s.nome),'[]'::jsonb)
      from public.simulados s where s.ativo)
  );
$$;

revoke execute on function public.catalogo() from public;
grant  execute on function public.catalogo() to anon, authenticated;
