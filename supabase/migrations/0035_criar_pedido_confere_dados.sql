-- ============================================================================
-- 0035 · o criar_pedido() recusa dados que nao fecham
-- ----------------------------------------------------------------------------
-- O checkout ja confere na tela (tamanho, CPF, telefone), mas a regra de
-- verdade tem de estar aqui. Aplicar SO depois do checkout novo no ar: o
-- antigo deixava o telefone vazio, e passaria a ser recusado.
-- ============================================================================

create or replace function public.criar_pedido(p_itens jsonb, p_dados jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_aluno uuid := auth.uid();
  v_ped   uuid;
  v_num   bigint;
  v_total int := 0;
  it      jsonb;
  v_plano public.planos%rowtype;
  v_qtd   int;
  v_itens jsonb := '[]'::jsonb;
  v_nome  text := btrim(coalesce(p_dados->>'nome',''));
  v_email text := lower(btrim(coalesce(p_dados->>'email','')));
  v_tel   text := regexp_replace(coalesce(p_dados->>'telefone',''), '\D', '', 'g');
  v_doc   text := regexp_replace(coalesce(p_dados->>'documento',''), '\D', '', 'g');
begin
  if v_aluno is null then
    return jsonb_build_object('ok',false,'motivo','precisa-entrar');
  end if;
  if p_itens is null or jsonb_array_length(p_itens) = 0 then
    return jsonb_build_object('ok',false,'motivo','carrinho-vazio');
  end if;

  -- mesmos limites do formulario do checkout
  if length(v_nome) < 3 or length(v_nome) > 120 then
    return jsonb_build_object('ok',false,'motivo','nome');
  end if;
  if v_email = '' then
    v_email := coalesce((select lower(email) from public.alunos where id = v_aluno), '');
  end if;
  if length(v_email) > 160 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('ok',false,'motivo','email');
  end if;
  -- DDD + numero (10 ou 11), com ou sem o 55 na frente
  if length(v_tel) not in (10, 11, 12, 13) then
    return jsonb_build_object('ok',false,'motivo','telefone');
  end if;
  if length(v_doc) not in (11, 14) then
    return jsonb_build_object('ok',false,'motivo','cpf');
  end if;

  insert into public.pedidos (aluno_id, nome, email, telefone, documento)
  values (v_aluno, v_nome, v_email, v_tel, v_doc)
  returning id, numero into v_ped, v_num;

  for it in select * from jsonb_array_elements(p_itens) loop
    select * into v_plano from public.planos
     where id = it->>'plano_id' and ativo;
    if not found then
      -- plano sumiu ou foi desativado entre por no carrinho e fechar
      delete from public.pedidos where id = v_ped;
      return jsonb_build_object('ok',false,'motivo','plano-indisponivel',
                                'plano', it->>'plano_id');
    end if;

    v_qtd := least(10, greatest(1, coalesce((it->>'quantidade')::int, 1)));

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
end $function$;
