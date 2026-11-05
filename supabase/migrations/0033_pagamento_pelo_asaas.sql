-- ===========================================================================
-- Economia do Dia · pagamento pelo ASAAS
-- ---------------------------------------------------------------------------
-- Ate aqui o pedido nascia "aguardando" e so virava acesso quando um admin
-- apertava "Confirmar pagamento". Agora:
--
--   checkout  -> criar_pedido()            (preco vem da tabela, como antes)
--   checkout  -> edge asaas-cobranca       (cria a cobranca no ASAAS: Pix,
--                                           cartao ou boleto)
--   ASAAS     -> edge asaas-webhook        (pagamento caiu)
--   webhook   -> liberar_pedido_interno()  (vira matricula, sem admin)
--
-- liberar_pedido_interno e estornar_pedido_interno so rodam com a chave de
-- servico (a das edge functions). Ninguem do navegador chama, nem admin.
-- confirmar_pagamento continua existindo para o admin confirmar na mao
-- (transferencia, cortesia, ou enquanto o ASAAS nao estiver ligado), e agora
-- so confere o admin e chama a mesma liberacao.
--
-- Aplicada no projeto ernqeokvkytwdlmjupwm em 30/10/2026.
-- ===========================================================================

-- o que a tela precisa mostrar de volta sem ir ao ASAAS de novo
alter table public.pedidos add column if not exists parcelas        int;
alter table public.pedidos add column if not exists cobranca_url    text;
alter table public.pedidos add column if not exists pix_copia_cola  text;
alter table public.pedidos add column if not exists boleto_linha    text;
alter table public.pedidos add column if not exists vence_em        date;
alter table public.pedidos add column if not exists estornado_em    timestamptz;

-- o mesmo aluno nao vira cliente novo no ASAAS a cada compra
alter table public.alunos add column if not exists asaas_cliente_id text;

-- estorno precisa saber QUAIS matriculas aquele pedido criou
alter table public.matriculas add column if not exists pedido_id uuid references public.pedidos(id);
create index if not exists matriculas_pedido_ix on public.matriculas(pedido_id);

-- todo aviso do ASAAS fica guardado: o id do evento e a trava contra repeticao
-- (o ASAAS reenvia ate receber 200) e o payload e a prova do que aconteceu.
create table if not exists public.asaas_eventos (
  id            text primary key,
  evento        text not null,
  pagamento_id  text,
  pedido_id     uuid,
  payload       jsonb not null,
  resultado     text,
  recebido_em   timestamptz not null default now()
);
create index if not exists asaas_eventos_pedido_ix on public.asaas_eventos(pedido_id, recebido_em desc);
alter table public.asaas_eventos enable row level security;
drop policy if exists asaas_eventos_admin on public.asaas_eventos;
create policy asaas_eventos_admin on public.asaas_eventos for select using (public.eh_admin());

-- ---------------------------------------------------------------------------
-- liberar_pedido_interno: a compra vira acesso. Idempotente: pedido ja pago
-- devolve ok sem criar matricula de novo (o ASAAS manda CONFIRMED e depois
-- RECEIVED para o mesmo cartao).
-- ---------------------------------------------------------------------------
create or replace function public.liberar_pedido_interno(
  p_pedido uuid, p_metodo text, p_gateway text default null, p_gateway_id text default null)
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
  select * into v_p from public.pedidos where id = p_pedido for update;
  if not found then
    return jsonb_build_object('ok',false,'motivo','pedido-nao-encontrado');
  end if;
  if v_p.status = 'pago' then
    return jsonb_build_object('ok',true,'pedido',p_pedido,'matriculas',0,'ja_pago',true);
  end if;
  if v_p.status in ('estornado') then
    return jsonb_build_object('ok',false,'motivo','pedido-estornado');
  end if;

  update public.pedidos
     set status='pago', pago_em=now(), metodo=coalesce(p_metodo, metodo),
         gateway=coalesce(p_gateway, gateway), gateway_id=coalesce(p_gateway_id, gateway_id)
   where id = p_pedido;

  for it in select i.plano_id, p.validade_meses
              from public.pedido_itens i
              join public.planos p on p.id = i.plano_id
             where i.pedido_id = p_pedido loop
    insert into public.matriculas (aluno_id, plano_id, ativa, expira_em, pedido_id)
    values (v_p.aluno_id, it.plano_id, true,
            case when coalesce(it.validade_meses,0) > 0
                 then now() + (it.validade_meses || ' months')::interval end,
            p_pedido);
    v_n := v_n + 1;
  end loop;

  insert into public.pagamentos (aluno_id, plano_id, gateway, gateway_id, status,
                                 metodo, valor_centavos, pago_em)
  select v_p.aluno_id, (select plano_id from public.pedido_itens
                         where pedido_id = p_pedido limit 1),
         coalesce(p_gateway, v_p.gateway), coalesce(p_gateway_id, v_p.gateway_id),
         'pago', coalesce(p_metodo, v_p.metodo), v_p.total_centavos, now()
  on conflict (gateway_id) do nothing;

  return jsonb_build_object('ok',true,'pedido',p_pedido,'matriculas',v_n);
end $FN$;

-- ---------------------------------------------------------------------------
-- estornar_pedido_interno: dinheiro devolvido ou contestado = acesso desligado.
-- So desliga as matriculas que ESTE pedido criou.
-- ---------------------------------------------------------------------------
create or replace function public.estornar_pedido_interno(p_pedido uuid, p_gateway_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $FN$
declare v_n int;
begin
  update public.pedidos set status='estornado', estornado_em=now()
   where id = p_pedido and status <> 'estornado';
  update public.matriculas set ativa=false where pedido_id = p_pedido and ativa;
  get diagnostics v_n = row_count;
  update public.pagamentos set status='estornado'
   where gateway_id = coalesce(p_gateway_id, (select gateway_id from public.pedidos where id = p_pedido));
  return jsonb_build_object('ok',true,'pedido',p_pedido,'matriculas_desligadas',v_n);
end $FN$;

-- ---------------------------------------------------------------------------
-- confirmar_pagamento: o botao do admin. Mesma assinatura de antes.
-- ---------------------------------------------------------------------------
create or replace function public.confirmar_pagamento(
  p_pedido uuid, p_metodo text default 'pix',
  p_gateway text default null, p_gateway_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $FN$
declare r jsonb;
begin
  if not public.eh_admin() then
    raise exception 'apenas administradores confirmam pagamento' using errcode='42501';
  end if;
  if exists (select 1 from public.pedidos where id = p_pedido and status = 'pago') then
    return jsonb_build_object('ok',false,'motivo','ja-pago');
  end if;
  r := public.liberar_pedido_interno(p_pedido, p_metodo, coalesce(p_gateway,'manual'), p_gateway_id);
  return r;
end $FN$;

-- ---------------------------------------------------------------------------
-- status_do_pedido: a tela de pagamento pergunta a cada poucos segundos se ja
-- caiu. So o dono (ou admin) ve.
-- ---------------------------------------------------------------------------
create or replace function public.status_do_pedido(p_pedido uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $FN$
  select coalesce((
    select jsonb_build_object('ok',true,'status',p.status,'pago_em',p.pago_em,'metodo',p.metodo)
      from public.pedidos p
     where p.id = p_pedido and (p.aluno_id = auth.uid() or public.eh_admin())),
    jsonb_build_object('ok',false,'motivo','pedido-nao-encontrado'));
$FN$;

-- pedidos_admin passa a dizer por onde pagou e o link da cobranca
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
        'parcelas',p.parcelas,'gateway',p.gateway,'gateway_id',p.gateway_id,
        'cobranca_url',p.cobranca_url,
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

revoke execute on function public.liberar_pedido_interno(uuid,text,text,text) from public, anon, authenticated;
revoke execute on function public.estornar_pedido_interno(uuid,text)          from public, anon, authenticated;
grant  execute on function public.liberar_pedido_interno(uuid,text,text,text) to service_role;
grant  execute on function public.estornar_pedido_interno(uuid,text)          to service_role;

revoke execute on function public.status_do_pedido(uuid)                      from public, anon, authenticated;
grant  execute on function public.status_do_pedido(uuid)                      to authenticated;
revoke execute on function public.confirmar_pagamento(uuid,text,text,text)    from public, anon, authenticated;
grant  execute on function public.confirmar_pagamento(uuid,text,text,text)    to authenticated;
revoke execute on function public.pedidos_admin(int)                          from public, anon, authenticated;
grant  execute on function public.pedidos_admin(int)                          to authenticated;
