-- ============================================================================
-- 0034 · a area do aluno passa a saber o que o aluno comprou
-- ----------------------------------------------------------------------------
-- O catalogo() e o mesmo para todo mundo, e o app.html marcava todo curso como
-- "nao comprado". Resultado: quem tinha plano via o proprio curso misturado
-- com os de venda, com preco em tokens. meus_cursos() devolve, para quem esta
-- logado, os cursos liberados e ate quando, pela mesma regra do
-- tem_acesso_curso() (matricula ativa, nao vencida, plano que inclui o curso).
-- ============================================================================

create or replace function public.meus_cursos()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'curso_id', x.curso_id,
           'expira_em', x.expira_em,
           'planos', x.planos)
           order by x.curso_id), '[]'::jsonb)
    from (
      select pc.curso_id,
             -- vale a matricula que dura mais; sem data = sem vencimento
             case when bool_or(m.expira_em is null) then null
                  else max(m.expira_em) end as expira_em,
             jsonb_agg(distinct p.nome) as planos
        from public.matriculas m
        join public.plano_cursos pc on pc.plano_id = m.plano_id
        join public.planos p on p.id = m.plano_id
       where m.aluno_id = auth.uid()
         and m.ativa
         and (m.expira_em is null or m.expira_em > now())
       group by pc.curso_id
    ) x;
$$;

revoke all on function public.meus_cursos() from public, anon;
grant execute on function public.meus_cursos() to authenticated;
