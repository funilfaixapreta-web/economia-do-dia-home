-- 0024 — fecha o aviso de search_path nas duas helpers da importacao
--
-- _vazio e _legacy_slug sao puras, so mexem em texto e nao tocam tabela
-- nenhuma, entao nao ha ataque real aqui. Mas search_path solto num
-- SECURITY DEFINER e um padrao ruim para deixar no banco, e o linter marca
-- as duas como WARN -- aviso que fica ligado acaba virando aviso que ninguem
-- le. Custa uma linha fechar.

alter function public._vazio(text) set search_path = public, pg_temp;

do $mig$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
              where n.nspname='public' and p.proname='_legacy_slug') then
    execute 'alter function public._legacy_slug(text) set search_path = public, pg_temp';
  end if;
end $mig$;

-- Sobraram no linter, todos esperados e conferidos antes:
--   rls_enabled_no_policy nas 7 tabelas de trabalho (_imp_*, _legacy_*,
--     _mapa_aluno) -- RLS ligada com ZERO politica E a negacao total para
--     anon e authenticated, conferido trocando de papel. Nao e falta de
--     politica, e a politica.
--   security_definer_function_executable nas 26 RPC -- cada uma confere
--     eh_admin() ou auth.uid() por dentro. SECURITY DEFINER e o que permite
--     o painel ler o que o aluno nao pode. Nenhuma e SECURITY INVOKER por
--     descuido.
--   auth_leaked_password_protection -- botao do painel do Supabase
--     (Auth -> Policies), nao da para ligar por SQL. Pendente com voce.
