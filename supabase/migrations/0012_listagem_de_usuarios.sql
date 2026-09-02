/* ============================================================================
   Economia do Dia · 0012 · a aba Usuarios passa a mostrar gente de verdade
   ----------------------------------------------------------------------------
   A listagem de Usuarios do painel mostrava nomes de exemplo -- "Felipe
   Nunes", "Mariana Alves", "Rafael Antunes" -- que vieram junto com o
   prototipo e nunca existiram. Depois de criar cinco administradores de
   verdade, nenhum deles aparecia ali.

   Faltava por onde ler. O painel so sabia publicar (rpc de escrita) e, desde
   a 0011, ler simulados. Usuario nao dava para ler porque nao havia funcao
   que juntasse cadastro + plano + provas feitas.

   Uma chamada so em vez de tres leituras soltas: assim a tela nao precisa
   descobrir sozinha qual matricula esta valendo nem contar tentativa por
   aluno, e o banco nao expoe mais colunas do que a tela usa.

   Admin-gated na entrada. Sem isso seria a lista de clientes inteira -- nome,
   e-mail, telefone, o que cada um comprou -- atras de um endpoint que
   qualquer pessoa logada alcanca.
   ============================================================================ */
create or replace function public.usuarios_admin(p_limite int default 500)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare r jsonb;
begin
  if not public.eh_admin() then
    raise exception 'apenas administradores' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.criado_em desc), '[]'::jsonb) into r
  from (
    select a.id, a.nome, a.email, a.telefone, a.papel, a.origem, a.criado_em,
           (select p.nome from public.matriculas m
              join public.planos p on p.id = m.plano_id
             where m.aluno_id = a.id and m.ativa
               and (m.expira_em is null or m.expira_em > now())
             order by m.expira_em nulls first limit 1) as plano,
           (select count(*) from public.tentativas t where t.aluno_id = a.id) as simulados,
           (select max(t.enviada_em) from public.tentativas t where t.aluno_id = a.id) as ultima_prova
      from public.alunos a
     order by a.criado_em desc
     limit greatest(1, least(coalesce(p_limite,500), 2000))
  ) x;

  return r;
end $$;

revoke all on function public.usuarios_admin(int) from public, anon, authenticated;
grant execute on function public.usuarios_admin(int) to authenticated;
