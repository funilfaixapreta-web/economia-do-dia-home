-- 0026 — o catalogo passa a dizer a que certificacao cada simulado pertence
--
-- Faltava: catalogo() entregava os 54 simulados numa lista plana, sem
-- categoria. A area do aluno nao tinha como agrupar por certificacao, e foi
-- por isso que ela inventou quatro "trilhas" proprias (cnpi, evaluation,
-- mercado, comercial) que nao existem no banco.
--
-- As trilhas de verdade sao as 8 categorias_simulado -- as mesmas que
-- trilhas_do_aluno usa para dizer o que cada aluno acompanha, com 50.433
-- vinculos vindos do sistema antigo.
--
-- 'certificacoes' vem com a contagem de simulados ativos de cada uma, e isso
-- expoe um fato que o site escondia: dos 54 simulados ativos, 21 sao de
-- cnpi-cg1, 13 de cfg, 11 de cnpi-ct1 e 9 de cnpi-cb. CPA-10, CPA-20, CEA e
-- ANCORD tem ZERO -- e sao as trilhas de 43.607 dos vinculos de aluno
-- (cpa-10 17.960, cpa-20 17.213, cea 5.195, ancord 3.239). A tela precisa
-- poder dizer "ainda nao ha simulado desta certificacao" em vez de mostrar
-- uma trilha que abre vazia.
--
-- 'composicao' entra pelo mesmo motivo: a tela mostrava o simulado quebrado
-- em "4 modulos" fixos, com nota por modulo. Os simulados de verdade tem de
-- 1 a 4 materias na composicao, e varios tem uma so.

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
        'categoria_id',s.categoria_id,
        'questoes',(select coalesce(sum(k.quantidade),0) from public.composicoes k
                     where k.simulado_id = s.id and k.ativo),
        -- a composicao por materia, que e o que permite mostrar o simulado
        -- quebrado por modulo sem inventar os modulos
        'composicao',(
          select coalesce(jsonb_agg(jsonb_build_object(
                   'categoria_id',k.categoria_id,
                   'nome',cq.nome,
                   'quantidade',k.quantidade)
                   order by cq.nome),'[]'::jsonb)
            from public.composicoes k
            left join public.categorias_questao cq on cq.id = k.categoria_id
           where k.simulado_id = s.id and k.ativo))
        order by s.nome),'[]'::jsonb)
      from public.simulados s where s.ativo),

    'certificacoes', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id',cs.id,'nome',cs.nome,
        'simulados',(select count(*) from public.simulados s
                      where s.categoria_id = cs.id and s.ativo))
        order by cs.nome),'[]'::jsonb)
      from public.categorias_simulado cs),

    'planos', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id',p.id,'nome',p.nome,'preco_centavos',p.preco_centavos,
        'validade_meses',p.validade_meses,
        'cursos',(select coalesce(jsonb_agg(pc.curso_id order by pc.curso_id),'[]'::jsonb)
                    from public.plano_cursos pc where pc.plano_id = p.id))
        order by p.preco_centavos desc),'[]'::jsonb)
      from public.planos p where p.ativo)
  );
$$;

revoke execute on function public.catalogo() from public;
grant  execute on function public.catalogo() to anon, authenticated;

-- Conferido com papel anon: cursos 2, simulados 54, certificacoes 8, planos 4.
-- Continua sem gabarito e sem link de video -- quem entrega video e a
-- ver_aula(), que confere quem esta pedindo.
