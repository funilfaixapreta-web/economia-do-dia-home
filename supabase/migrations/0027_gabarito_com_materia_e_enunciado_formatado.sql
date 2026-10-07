-- 0027 — a revisao passa a saber a materia da questao e o enunciado formatado
--
-- gabarito_tentativa() nao devolvia nem a materia nem o enunciado_html.
-- Consequencias praticas:
--   - a revisao nao podia marcar "Renda Fixa" na questao, e era justamente
--     por isso que a tela antiga tirava o tema do QBANK inventado;
--   - 1.970 das 5.098 questoes tem enunciado_html (tabela, formula, negrito)
--     e apareciam como texto cru, sem a formatacao que o enunciado precisa.
--
-- Nao mexe em permissao: continua devolvendo so para a dona da tentativa ou
-- para admin, e so depois de entregue.
--
-- Nota sobre o comentario: NENHUMA das 5.098 questoes ativas tem comentario
-- em texto -- 4.388 tem AUDIO. O "gabarito comentado" desta plataforma sempre
-- foi falado, nao escrito. A tela tem de tratar o audio como a explicacao
-- principal, e nao como enfeite ao lado de um texto que nao existe.

create or replace function public.gabarito_tentativa(p_tentativa uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_t public.tentativas%rowtype;
  v_assinante boolean;
begin
  select * into v_t from public.tentativas where id = p_tentativa;
  if not found then
    return jsonb_build_object('ok',false,'motivo','tentativa-nao-encontrada');
  end if;
  if v_t.aluno_id is distinct from auth.uid() and not public.eh_admin() then
    return jsonb_build_object('ok',false,'motivo','tentativa-nao-e-sua');
  end if;
  if v_t.enviada_em is null then
    return jsonb_build_object('ok',false,'motivo','ainda-nao-entregue');
  end if;

  v_assinante := public.eh_admin() or exists (
    select 1 from public.matriculas m
     where m.aluno_id = v_t.aluno_id and m.ativa
       and (m.expira_em is null or m.expira_em > now()));

  return jsonb_build_object(
    'ok', true,
    'tentativa', v_t.id,
    'acertos', v_t.acertos, 'total', v_t.total, 'nota', v_t.nota,
    'assinante', v_assinante,
    'aprovado', v_t.nota >= coalesce((select corte from public.simulados
                                       where id = v_t.simulado_id), 70),
    'questoes', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', q.id,
               'enunciado', q.enunciado,
               'enunciado_html', q.enunciado_html,
               'categoria', cq.nome,
               'comentario', q.comentario,
               'audio_url',   case when (v_assinante or coalesce(q.audio_regra,'') !~* 'assinante')
                                    and not exists (select 1 from public.audios_indisponiveis x
                                                     where x.track_id = public.track_do_audio(q.audio_url))
                                   then q.audio_url end,
               'audio_embed', case when (v_assinante or coalesce(q.audio_regra,'') !~* 'assinante')
                                    and not exists (select 1 from public.audios_indisponiveis x
                                                     where x.track_id = public.track_do_audio(q.audio_url))
                                   then q.audio_embed end,
               'audio_indisponivel', exists (select 1 from public.audios_indisponiveis x
                                      where x.track_id = public.track_do_audio(q.audio_url)),
               'audio_bloqueado', (q.audio_url is not null or q.audio_embed is not null)
                                  and not v_assinante
                                  and coalesce(q.audio_regra,'') ~* 'assinante',
               'marcada', r.alternativa_id,
               'acertou', coalesce(r.correta,false),
               'alternativas', (
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'id',a.id,'texto',a.texto,'correta',a.correta)
                          order by a.ordem),'[]'::jsonb)
                   from public.alternativas a
                  where a.questao_id = q.id and a.ativo)
             )),'[]'::jsonb)
        from public.respostas r
        join public.questoes q on q.id = r.questao_id
        left join public.categorias_questao cq on cq.id = q.categoria_id
       where r.tentativa_id = p_tentativa)
  );
end $function$;

revoke execute on function public.gabarito_tentativa(uuid) from public, anon, authenticated;
grant  execute on function public.gabarito_tentativa(uuid) to authenticated;

-- ATENCAO para quem for mexer na tela: 'marcada' e o ID da alternativa que o
-- aluno escolheu (ou null, se deixou em branco), e NAO um booleano em cada
-- alternativa. E 'acertou' fica na QUESTAO, nao na alternativa. Escrevi a
-- tela errado na primeira vez por supor o contrario, e o resultado foi
-- "Voce marcou" aparecendo na linha errada.
