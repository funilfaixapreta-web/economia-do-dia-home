-- 0015 — tira o alcance das tabelas de resto da importacao
--
-- A importacao de 30/09 deixou tres tabelas no schema public:
--
--   _legacy_raw   164.841 linhas de JSON cru, inclusive 66.002 pessoas com
--                 nome, e-mail, celular e estado
--   _legacy_map        98 linhas de mapeamento de categoria
--   _legacy_urls      164 urls
--
-- Nao havia vazamento: as tres estao com RLS ligada e ZERO politicas, e um
-- teste trocando para o papel authenticated leu 0 linhas de _legacy_map e
-- _legacy_urls e foi barrado no _legacy_raw, que nem grant tinha. Nenhuma
-- linha guarda password, remember_token ou api_token — conferido.
--
-- Mesmo assim _legacy_map e _legacy_urls tinham GRANT SELECT para anon e
-- authenticated. Isso deixava as duas a UMA politica permissiva de distancia
-- de ficarem legiveis, e grant que nao serve para nada nao deve existir.
revoke all on public._legacy_map  from anon, authenticated;
revoke all on public._legacy_urls from anon, authenticated;
revoke all on public._legacy_raw  from anon, authenticated;

-- O certo e as tres deixarem de existir: o _legacy_raw e um segundo lugar
-- guardando o dado pessoal de 66 mil pessoas, e dado que nao existe nao
-- vaza. Os DROP ficam aqui para serem rodados a mao porque o MCP do Supabase
-- barra verbo destrutivo (DELETE, TRUNCATE e DROP dao timeout).
--
--   drop table if exists public._legacy_raw;
--   drop table if exists public._legacy_map;
--   drop table if exists public._legacy_urls;
--
-- Antes de rodar, vale lembrar que o _legacy_raw e a unica copia por aqui do
-- que veio do sistema antigo: foi ele que mostrou que os 3 alunos faltantes
-- se perderam na exportacao, nao na importacao. Guardar o arquivo fora do
-- banco antes de apagar e uma boa ideia.
