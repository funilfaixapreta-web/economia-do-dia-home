-- 0016 — convite de admin so vale com e-mail confirmado
--
-- admins_convidados e lida pelo ao_criar_usuario, que da o papel combinado a
-- quem se cadastra com um e-mail da lista. O gatilho dispara no INSERT em
-- auth.users, ou seja ANTES da confirmacao do e-mail: bastava alguem digitar
-- um endereco da lista no cadastro para a linha em alunos nascer com
-- papel='admin', sem nunca provar que o endereco e dele.
--
-- Havia dois convites em aberto que ninguem pediu, nenhum com conta criada:
--
--   admin@economiadodia.com.br   o login de fachada que saiu do painel
--   teste-escalada@teste.local   resto do meu teste de escalada de privilegio
--
-- O segundo e o pior: .local nao e TLD roteavel, ninguem recebe e-mail ali,
-- logo ninguem pode ser o dono legitimo — mas qualquer pessoa podia cadastrar
-- exatamente aquele endereco. Apagar as duas linhas e o certo (os DROP/DELETE
-- ficam no fim para rodar a mao, porque o MCP barra verbo destrutivo), e
-- DELETE sozinho nao resolveria a classe do problema: qualquer convite futuro
-- teria a mesma brecha ate a confirmacao passar a ser exigida.

create or replace function public.ao_criar_usuario()
 returns trigger language plpgsql security definer set search_path to 'public'
as $fn$
declare v_ini int; v_papel text;
begin
  select inicial into v_ini from public.config_tokens where id;

  -- convite so vale com e-mail confirmado; quem confirma depois e promovido
  -- por ao_confirmar_email()
  if new.email_confirmed_at is not null then
    select papel into v_papel from public.admins_convidados
     where lower(email) = lower(coalesce(new.email,''));
  end if;

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
end $fn$;

-- a promocao acontece no momento em que o e-mail e confirmado, e so sobe quem
-- ainda e 'aluno' (nao rebaixa nem mexe em quem ja tem papel)
create or replace function public.ao_confirmar_email()
 returns trigger language plpgsql security definer set search_path to 'public'
as $fn$
declare v_papel text;
begin
  if old.email_confirmed_at is null and new.email_confirmed_at is not null then
    select papel into v_papel from public.admins_convidados
     where lower(email) = lower(coalesce(new.email,''));
    if v_papel is not null then
      update public.alunos set papel = v_papel
       where id = new.id and papel = 'aluno';
    end if;
  end if;
  return new;
end $fn$;

drop trigger if exists convite_ao_confirmar on auth.users;
create trigger convite_ao_confirmar
  after update of email_confirmed_at on auth.users
  for each row execute function public.ao_confirmar_email();

revoke execute on function public.ao_confirmar_email() from public, anon, authenticated;

-- Conferido com cadastro simulado, abortando a transacao para nao gravar nada:
--   e-mail da lista sem confirmar ....... aluno  (era admin antes desta migracao)
--   o mesmo depois de confirmar ......... admin
--   e-mail fora da lista, confirmado .... aluno
--
-- Falta rodar a mao, porque o MCP barra DELETE:
--   delete from public.admins_convidados
--    where email in ('admin@economiadodia.com.br','teste-escalada@teste.local');
