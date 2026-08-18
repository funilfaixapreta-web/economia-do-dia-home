/* ============================================================================
   Economia do Dia · 0009 · fecha a edicao do cadastro e cria o perfil unico
   ----------------------------------------------------------------------------
   ACHADO DE SEGURANCA (corrigido aqui)

   A politica de UPDATE da tabela "alunos" era assim:

       create policy edito_meu_cad on public.alunos
         for update using (id = auth.uid());          -- sem WITH CHECK

   Quando um UPDATE nao tem WITH CHECK, o Postgres usa a expressao do USING
   no lugar dele. E o USING so amarra QUAL LINHA pode ser tocada -- nao amarra
   QUAIS COLUNAS. Como a role "authenticated" tinha GRANT UPDATE na tabela
   inteira, qualquer aluno logado podia mandar, direto no PostgREST:

       PATCH /rest/v1/alunos?id=eq.<o proprio id>   { "papel": "admin" }

   ... e virar admin sozinho. Testado no banco: passou. Com papel=admin ele
   teria publicar_conteudo (mexer no banco de questoes), confirmar_pagamento
   (liberar curso sem pagar), pedidos_admin (dados de todos os clientes) e o
   gabarito completo.

   E o mesmo erro do gabarito na 0003: RLS filtra LINHA, nao COLUNA. Quem
   escolhe coluna e o GRANT. Entao a correcao tem tres camadas:

     1. GRANT por coluna  -> authenticated so pode escrever nome e telefone
     2. WITH CHECK de verdade na politica
     3. gatilho que barra papel/email/id trocados por quem veio do navegador

   Uma camada ja resolveria. As tres existem porque se alguem no futuro rodar
   um "grant all on all tables" (coisa que todo tutorial de Supabase manda
   fazer), a camada 1 cai sozinha e as outras duas seguram.
   ============================================================================ */

/* ---------------------------------------------------------------- 1. GRANT */
revoke insert, update, delete on public.alunos from anon, authenticated;

/* o aluno (e o admin) mexem no proprio nome e telefone. So nisso.
   e-mail muda pelo Auth (com confirmacao); papel muda por promover_admin() */
grant update (nome, telefone) on public.alunos to authenticated;

/* tentativa e resposta de prova sempre foram escritas por montar_simulado() e
   enviar_tentativa(), que sao SECURITY DEFINER. O navegador nunca precisou de
   escrita direta -- e com ela dava para reescrever a propria nota. */
revoke insert, update, delete on public.tentativas from anon, authenticated;
revoke insert, update, delete on public.respostas  from anon, authenticated;

/* ------------------------------------------------------------- 2. POLITICA */
drop policy if exists edito_meu_cad on public.alunos;
create policy edito_meu_cad on public.alunos
  for update
  using      (id = auth.uid())
  with check (id = auth.uid());

/* -------------------------------------------------------------- 3. GATILHO */
/* current_user dentro de uma funcao SECURITY DEFINER e o dono dela (postgres).
   Vindo do PostgREST, e 'anon' ou 'authenticated'. Entao da para distinguir
   "veio do navegador" de "veio de uma funcao que ja checou quem pode". */
create or replace function public.alunos_campos_travados()
returns trigger language plpgsql as $$
begin
  if current_user in ('anon','authenticated') then
    if new.papel is distinct from old.papel then
      raise exception 'papel do cadastro nao se muda por aqui'
        using errcode='42501';
    end if;
    if new.email is distinct from old.email then
      raise exception 'e-mail se muda pelo Auth, com confirmacao'
        using errcode='42501';
    end if;
    if new.id is distinct from old.id or new.criado_em is distinct from old.criado_em then
      raise exception 'campo de identificacao nao se muda'
        using errcode='42501';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trava_campos on public.alunos;
create trigger trava_campos before update on public.alunos
  for each row execute function public.alunos_campos_travados();

/* ================================================================== PERFIL */
/* Uma leitura so, que serve tanto para o aluno quanto para o admin. Devolve
   tambem o plano vigente, porque a tela mostra isso e nao vale a pena uma
   segunda ida ao banco. */
create or replace function public.meu_perfil()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare v_eu uuid := auth.uid(); r jsonb;
begin
  if v_eu is null then raise exception 'precisa estar logado'; end if;

  select to_jsonb(x) into r from (
    select a.id, a.nome, a.email, a.telefone, a.papel, a.criado_em,
           (select jsonb_build_object('id',p.id,'nome',p.nome,'expira_em',m.expira_em)
              from public.matriculas m
              join public.planos p on p.id = m.plano_id
             where m.aluno_id = a.id and m.ativa
               and (m.expira_em is null or m.expira_em > now())
             order by m.expira_em nulls first limit 1) as plano
      from public.alunos a where a.id = v_eu
  ) x;

  return coalesce(r, '{}'::jsonb);
end $$;

revoke all on function public.meu_perfil() from public, anon, authenticated;
grant execute on function public.meu_perfil() to authenticated;

/* Grava nome e telefone. Existe porque a tela nao precisa saber que a tabela
   se chama "alunos" nem quais colunas ela tem direito de tocar -- e porque
   assim o dia em que a regra mudar, muda num lugar so. */
create or replace function public.atualizar_meu_perfil(p_nome text, p_telefone text default null)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_eu uuid := auth.uid(); v_nome text := btrim(coalesce(p_nome,''));
begin
  if v_eu is null then raise exception 'precisa estar logado'; end if;
  if length(v_nome) < 2 then raise exception 'nome muito curto'; end if;

  update public.alunos
     set nome     = left(v_nome,120),
         telefone = nullif(btrim(coalesce(p_telefone,'')),'')
   where id = v_eu;

  return public.meu_perfil();
end $$;

revoke all on function public.atualizar_meu_perfil(text,text) from public, anon, authenticated;
grant execute on function public.atualizar_meu_perfil(text,text) to authenticated;

/* --------------------------------------------------- e-mail: Auth -> alunos */
/* Trocar o e-mail e coisa do GoTrue: ele manda confirmacao para o endereco
   novo e so entao grava em auth.users. Este gatilho faz a tabela publica
   seguir o que o Auth decidiu -- nunca o contrario. */
create or replace function public.ao_trocar_email()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if new.email is distinct from old.email and new.email is not null then
    update public.alunos set email = new.email where id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists sincroniza_email on auth.users;
create trigger sincroniza_email after update of email on auth.users
  for each row execute function public.ao_trocar_email();
