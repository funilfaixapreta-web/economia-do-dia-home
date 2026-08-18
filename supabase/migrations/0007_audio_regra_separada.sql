-- ===========================================================================
-- Economia do Dia · a regra do AUDIO nao e a regra da QUESTAO
-- ---------------------------------------------------------------------------
-- O export do sistema antigo traz audio_regra = "Somente assinantes" em quase
-- todas as questoes. Isso governa quem OUVE o gabarito comentado — nao quem
-- pode RESPONDER a questao. Ao herdar essa regra na questao, 5.106 de 5.110
-- viravam "assinantes": se um dia regra_acesso passar a valer para acesso,
-- todo simulado gratuito morre de uma vez.
--
-- Correcao: coluna propria para a regra do audio, e a questao volta a livre.
-- Alem disso, o audio agora SAI na revisao — antes gabarito_tentativa devolvia
-- so audio_embed, entao o link do audio nunca chegava ao aluno.
--
-- Aplicada no projeto ernqeokvkytwdlmjupwm em 18/08/2026.
-- ===========================================================================
alter table public.questoes
  add column if not exists audio_regra text;

-- desfaz a heranca indevida da carga anterior
update public.questoes
   set regra_acesso = 'livre'
 where ref like 'legacy-%' and regra_acesso = 'assinantes';

grant select (id, categoria_id, enunciado, audio_url, audio_embed, audio_regra,
              regra_acesso, ativo, ref, criada_em)
  on public.questoes to anon, authenticated;

-- ---------------------------------------------------------------------------
-- O audio e parte do gabarito comentado: sai na revisao, depois de entregue.
-- Se o audio for de assinante e o aluno nao for, ele recebe o resto da revisao
-- normalmente e um sinalizador "audio_bloqueado" — nunca o link.
-- ---------------------------------------------------------------------------
create or replace function public.gabarito_tentativa(p_tentativa uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $FN$
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
               'comentario', q.comentario,
               'audio_url',   case when v_assinante or coalesce(q.audio_regra,'') !~* 'assinante'
                                   then q.audio_url end,
               'audio_embed', case when v_assinante or coalesce(q.audio_regra,'') !~* 'assinante'
                                   then q.audio_embed end,
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
        from public.respostas r join public.questoes q on q.id = r.questao_id
       where r.tentativa_id = p_tentativa)
  );
end $FN$;

revoke execute on function public.gabarito_tentativa(uuid) from public, anon, authenticated;
grant  execute on function public.gabarito_tentativa(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- publicar_conteudo passa a gravar audio_regra. Em vez de reescrever as ~200
-- linhas da funcao na mao (e arriscar quebrar outra coisa), ela e reescrita a
-- partir de si mesma, acrescentando so a coluna nova.
-- ---------------------------------------------------------------------------
do $B$
declare def text;
begin
  select pg_get_functiondef(p.oid) into def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='publicar_conteudo';

  def := replace(def,
    'audio_url, audio_embed, regra_acesso, ativo)',
    'audio_url, audio_embed, audio_regra, regra_acesso, ativo)');
  def := replace(def,
    'q->>''audio_url'', q->>''audio_embed'',',
    'q->>''audio_url'', q->>''audio_embed'', q->>''audio_regra'',');
  def := replace(def,
    'audio_embed=excluded.audio_embed,',
    'audio_embed=excluded.audio_embed, audio_regra=excluded.audio_regra,');

  execute def;
end $B$;
