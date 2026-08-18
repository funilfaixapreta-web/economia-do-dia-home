-- ===========================================================================
-- Economia do Dia · carrinho e pedidos
-- ---------------------------------------------------------------------------
-- O carrinho vive no navegador de proposito: e rascunho, o cliente mexe a
-- vontade e nada disso vale dinheiro. O que vale e o PEDIDO, e o pedido nasce
-- aqui.
--
-- Regra que nao se negocia: o preco NUNCA vem do navegador. criar_pedido()
-- recebe so QUAIS planos e QUANTOS, e busca o preco na tabela. Senao qualquer
-- pessoa leva o curso de R$ 2.997 por R$ 1,00 editando o JSON no F12.
--
-- Aplicada no projeto ernqeokvkytwdlmjupwm em 14/08/2026.
-- ===========================================================================

create table if not exists public.pedidos (
  id              uuid primary key default gen_random_uuid(),
  numero          bigint generated always as identity,
  aluno_id        uuid not null references public.alunos(id),
  nome            text,
  email           text,
  telefone        text,
  documento       text,
  status          text not null default 'aguardando'
                  check (status in ('aguardando','pago','cancelado','estornado')),
  total_centavos  int  not null default 0 check (total_centavos >= 0),
  metodo          text check (metodo in ('pix','cartao','boleto')),
  gateway         text,
  gateway_id      text,
  criado_em       timestamptz not null default now(),
  pago_em         timestamptz
);
create unique index if not exists pedidos_numero_uk on public.pedidos(numero);
create index if not exists pedidos_aluno_ix on public.pedidos(aluno_id, criado_em desc);

create table if not exists public.pedido_itens (
  pedido_id       uuid not null references public.pedidos(id) on delete cascade,
  plano_id        text not null references public.planos(id),
  nome            text not null,
  preco_centavos  int  not null check (preco_centavos >= 0),
  quantidade      int  not null default 1 check (quantidade > 0),
  primary key (pedido_id, plano_id)
);

alter table public.pedidos      enable row level security;
alter table public.pedido_itens enable row level security;

drop policy if exists pedido_do_dono on public.pedidos;
create policy pedido_do_dono on public.pedidos for select
  using (aluno_id = auth.uid() or public.eh_admin());
drop policy if exists pedido_admin on public.pedidos;
create policy pedido_admin on public.pedidos for all
  using (public.eh_admin()) with check (public.eh_admin());

drop policy if exists item_do_dono on public.pedido_itens;
create policy item_do_dono on public.pedido_itens for select
  using (exists (select 1 from public.pedidos p
                  where p.id = pedido_itens.pedido_id
                    and (p.aluno_id = auth.uid() or public.eh_admin())));
drop policy if exists item_admin on public.pedido_itens;
create policy item_admin on public.pedido_itens for all
  using (public.eh_admin()) with check (public.eh_admin());

-- o catalogo de venda: aberto, so nome e preco
drop policy if exists catalogo_planos on public.planos;
create policy catalogo_planos on public.planos for select
  using (ativo or public.eh_admin());
drop policy if exists admin_planos on public.planos;
create policy admin_planos on public.planos for all
  using (public.eh_admin()) with check (public.eh_admin());

drop policy if exists catalogo_plano_cursos on public.plano_cursos;
create policy catalogo_plano_cursos on public.plano_cursos for select using (true);
drop policy if exists admin_plano_cursos on public.plano_cursos;
create policy admin_plano_cursos on public.plano_cursos for all
  using (public.eh_admin()) with check (public.eh_admin());

-- ---------------------------------------------------------------------------
-- criar_pedido: fecha o carrinho num pedido. O preco vem DAQUI, nao de la.
-- ---------------------------------------------------------------------------
create or replace function public.criar_pedido(p_itens jsonb, p_dados jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $FN$
declare
  v_aluno uuid := auth.uid();
  v_ped   uuid;
  v_num   bigint;
  v_total int := 0;
  it      jsonb;
  v_plano public.planos%rowtype;
  v_qtd   int;
  v_itens jsonb := '[]'::jsonb;
begin
  if v_aluno is null then
    return jsonb_build_object('ok',false,'motivo','precisa-entrar');
  end if;
  if p_itens is null or jsonb_array_length(p_itens) = 0 then
    return jsonb_build_object('ok',false,'motivo','carrinho-vazio');
  end if;

  insert into public.pedidos (aluno_id, nome, email, telefone, documento)
  values (v_aluno,
          nullif(p_dados->>'nome',''),
          coalesce(nullif(p_dados->>'email',''),
                   (select email from public.alunos where id = v_aluno)),
          nullif(p_dados->>'telefone',''),
          nullif(p_dados->>'documento',''))
  returning id, numero into v_ped, v_num;

  for it in select * from jsonb_array_elements(p_itens) loop
    -- repare: le o plano da TABELA. O que veio no p_itens sobre preco e ignorado.
    select * into v_plano from public.planos
     where id = it->>'plano_id' and ativo;
    if not found then
      delete from public.pedidos where id = v_ped;
      return jsonb_build_object('ok',false,'motivo','plano-indisponivel',
                                'plano', it->>'plano_id');
    end if;

    v_qtd := greatest(1, coalesce((it->>'quantidade')::int, 1));

    insert into public.pedido_itens (pedido_id, plano_id, nome, preco_centavos, quantidade)
    values (v_ped, v_plano.id, v_plano.nome, coalesce(v_plano.preco_centavos,0), v_qtd)
    on conflict (pedido_id, plano_id) do update set quantidade = pedido_itens.quantidade + excluded.quantidade;

    v_total := v_total + coalesce(v_plano.preco_centavos,0) * v_qtd;
    v_itens := v_itens || jsonb_build_object('plano_id',v_plano.id,'nome',v_plano.nome,
                 'preco_centavos',coalesce(v_plano.preco_centavos,0),'quantidade',v_qtd);
  end loop;

  update public.pedidos set total_centavos = v_total where id = v_ped;

  return jsonb_build_object('ok',true,'pedido',v_ped,'numero',v_num,
                            'total_centavos',v_total,'itens',v_itens);
end $FN$;

-- ---------------------------------------------------------------------------
-- confirmar_pagamento: e AQUI que a compra vira acesso. So admin — quando
-- houver gateway, o webhook chama isto com a chave de servico.
-- ---------------------------------------------------------------------------
create or replace function public.confirmar_pagamento(
  p_pedido uuid, p_metodo text default 'pix',
  p_gateway text default null, p_gateway_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $FN$
declare
  v_p public.pedidos%rowtype;
  it  record;
  v_n int := 0;
begin
  if not public.eh_admin() then
    raise exception 'apenas administradores confirmam pagamento' using errcode='42501';
  end if;

  select * into v_p from public.pedidos where id = p_pedido;
  if not found then
    return jsonb_build_object('ok',false,'motivo','pedido-nao-encontrado');
  end if;
  if v_p.status = 'pago' then
    return jsonb_build_object('ok',false,'motivo','ja-pago');
  end if;

  update public.pedidos
     set status='pago', pago_em=now(), metodo=p_metodo,
         gateway=p_gateway, gateway_id=p_gateway_id
   where id = p_pedido;

  -- cada item vira matricula; o plano diz por quantos meses
  for it in select i.plano_id, p.validade_meses
              from public.pedido_itens i
              join public.planos p on p.id = i.plano_id
             where i.pedido_id = p_pedido loop
    insert into public.matriculas (aluno_id, plano_id, ativa, expira_em)
    values (v_p.aluno_id, it.plano_id, true,
            case when coalesce(it.validade_meses,0) > 0
                 then now() + (it.validade_meses || ' months')::interval end);
    v_n := v_n + 1;
  end loop;

  insert into public.pagamentos (aluno_id, plano_id, gateway, gateway_id, status,
                                 metodo, valor_centavos, pago_em)
  select v_p.aluno_id, (select plano_id from public.pedido_itens
                         where pedido_id = p_pedido limit 1),
         p_gateway, p_gateway_id, 'pago', p_metodo, v_p.total_centavos, now()
  on conflict (gateway_id) do nothing;

  return jsonb_build_object('ok',true,'pedido',p_pedido,'matriculas',v_n);
end $FN$;

-- o que o cliente ve dos proprios pedidos
create or replace function public.meus_pedidos()
returns jsonb
language sql
stable
security definer
set search_path = public
as $FN$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,'numero',p.numero,'status',p.status,
    'total_centavos',p.total_centavos,'criado_em',p.criado_em,'pago_em',p.pago_em,
    'itens',(select coalesce(jsonb_agg(jsonb_build_object(
               'nome',i.nome,'preco_centavos',i.preco_centavos,'quantidade',i.quantidade)),'[]'::jsonb)
               from public.pedido_itens i where i.pedido_id = p.id))
    order by p.criado_em desc),'[]'::jsonb)
  from public.pedidos p where p.aluno_id = auth.uid();
$FN$;

-- a lista de pedidos da tela de Venda do painel
create or replace function public.pedidos_admin(p_limite int default 200)
returns jsonb
language plpgsql
security definer
set search_path = public
as $FN$
begin
  if not public.eh_admin() then
    raise exception 'apenas administradores veem os pedidos' using errcode='42501';
  end if;
  return (
    select coalesce(jsonb_agg(x order by x->>'criado_em' desc),'[]'::jsonb) from (
      select jsonb_build_object(
        'id',p.id,'numero',p.numero,'status',p.status,'metodo',p.metodo,
        'total_centavos',p.total_centavos,'criado_em',p.criado_em,'pago_em',p.pago_em,
        'nome',coalesce(p.nome,a.nome),'email',coalesce(p.email,a.email),
        'telefone',p.telefone,'documento',p.documento,
        'itens',(select coalesce(jsonb_agg(jsonb_build_object(
                   'nome',i.nome,'quantidade',i.quantidade,'preco_centavos',i.preco_centavos)),'[]'::jsonb)
                   from public.pedido_itens i where i.pedido_id = p.id)) as x
        from public.pedidos p
        left join public.alunos a on a.id = p.aluno_id
       order by p.criado_em desc
       limit greatest(1, coalesce(p_limite,200))
    ) t);
end $FN$;

-- ---------------------------------------------------------------------------
-- publicar_planos: o painel tambem publica o que se VENDE. Sem isto, o
-- carrinho nao tem preco e criar_pedido() recusa tudo.
-- ---------------------------------------------------------------------------
create or replace function public.publicar_planos(p_planos jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $FN$
declare pl jsonb; cid jsonb; n int := 0; nc int := 0;
begin
  if not public.eh_admin() then
    raise exception 'apenas administradores podem publicar' using errcode='42501';
  end if;

  for pl in select * from jsonb_array_elements(coalesce(p_planos,'[]'::jsonb)) loop
    insert into public.planos (id, nome, preco_centavos, validade_meses, ativo)
    values (pl->>'id', coalesce(pl->>'nome','(sem nome)'),
            coalesce((pl->>'preco_centavos')::int,0),
            coalesce((pl->>'validade_meses')::int,12),
            coalesce((pl->>'ativo')::boolean,true))
    on conflict (id) do update set
      nome=excluded.nome, preco_centavos=excluded.preco_centavos,
      validade_meses=excluded.validade_meses, ativo=excluded.ativo;
    n := n + 1;

    delete from public.plano_cursos where plano_id = pl->>'id';
    for cid in select * from jsonb_array_elements(coalesce(pl->'cursos','[]'::jsonb)) loop
      if exists (select 1 from public.cursos c where c.id = trim(both '"' from cid::text)) then
        insert into public.plano_cursos (plano_id, curso_id)
        values (pl->>'id', trim(both '"' from cid::text))
        on conflict do nothing;
        nc := nc + 1;
      end if;
    end loop;
  end loop;

  return jsonb_build_object('ok',true,'planos',n,'vinculos',nc);
end $FN$;

revoke execute on function public.criar_pedido(jsonb,jsonb)                from public, anon, authenticated;
revoke execute on function public.confirmar_pagamento(uuid,text,text,text) from public, anon, authenticated;
revoke execute on function public.meus_pedidos()                           from public, anon, authenticated;
revoke execute on function public.pedidos_admin(int)                       from public, anon, authenticated;
revoke execute on function public.publicar_planos(jsonb)                   from public, anon, authenticated;
grant  execute on function public.criar_pedido(jsonb,jsonb)                to authenticated;
grant  execute on function public.confirmar_pagamento(uuid,text,text,text) to authenticated;
grant  execute on function public.meus_pedidos()                           to authenticated;
grant  execute on function public.pedidos_admin(int)                       to authenticated;
grant  execute on function public.publicar_planos(jsonb)                   to authenticated;

-- ---------------------------------------------------------------------------
-- catalogo() passa a devolver tambem 'planos' — e dai que o carrinho tira o
-- preco quando a ponte com o banco esta ligada. Redefinida por inteiro (e um
-- "create or replace") para quem replicar as migracoes na ordem terminar com
-- a versao certa.
-- ---------------------------------------------------------------------------
create or replace function public.catalogo()
returns jsonb
language sql
stable
security definer
set search_path = public
as $FN$
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
        'tempo_limite',s.tempo_limite,'corte',s.corte,'regra_acesso',s.regra_acesso,
        'questoes',(select coalesce(sum(k.quantidade),0) from public.composicoes k
                     where k.simulado_id = s.id and k.ativo))
        order by s.nome),'[]'::jsonb)
      from public.simulados s where s.ativo),
    'planos', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id',p.id,'nome',p.nome,'preco_centavos',p.preco_centavos,
        'validade_meses',p.validade_meses,
        'cursos',(select coalesce(jsonb_agg(pc.curso_id),'[]'::jsonb)
                    from public.plano_cursos pc where pc.plano_id = p.id))
        order by p.preco_centavos desc),'[]'::jsonb)
      from public.planos p where p.ativo)
  );
$FN$;

revoke execute on function public.catalogo() from public;
grant  execute on function public.catalogo() to anon, authenticated;

-- ===========================================================================
-- ADENDO (aplicado depois): questao sem gabarito nao entra em prova
-- ---------------------------------------------------------------------------
-- A extracao do sistema antigo (5.105 questoes) revelou casos reais: questoes
-- sem alternativa nenhuma, com alternativa unica, e uma com quatro
-- alternativas e NENHUMA marcada como correta. Essa ultima e a pior: entra no
-- sorteio normalmente e o aluno erra sempre, porque nao existe resposta certa.
--
-- Regra: para valer numa prova a questao precisa de pelo menos duas
-- alternativas e EXATAMENTE UMA correta. Quem nao cumprir entra no banco (para
-- nao perder o cadastro) mas com ativo=false, fora do sorteio. publicar_conteudo
-- passa a devolver 'questoes_sem_gabarito' e 'refs_sem_gabarito'.
--
-- A definicao completa e atual da funcao esta em
-- 0006_questao_sem_gabarito_fora_da_prova.sql.
-- ===========================================================================
