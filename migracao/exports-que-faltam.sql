-- ===========================================================================
-- PARTE 1 -- FEITO em 07/10/2026. Os tres CSVs vieram, foram importados e
-- conferidos: 91.242 provas, 2.625 linhas de log e 50.433 trilhas, exatas.
-- Ver migracao/importar-o-que-falta.sql e a 0023. Fica registrado por que
-- cada consulta era essa e nao outra.
--
-- O que preciso para puxar tudo: TRES CSVs, com cabecalho.
--
-- Use SELECT * mesmo. O cabecalho do CSV me diz os nomes das colunas, entao
-- nao preciso de uma consulta de estrutura antes -- economiza uma ida e volta.
--
-- Nenhum leva e-mail, nome, telefone ou CPF. Os ids de aluno eu caso sozinho:
-- 65.877 dos 66.000 ja estao mapeados para o uuid do banco novo.
-- ===========================================================================

-- 1) HISTORICO DE PROVA
SELECT * FROM quiz_user ORDER BY id;

-- 2) LOG DE ASSINATURA  (esperado: 2.625 linhas)
SELECT * FROM subscription_log ORDER BY id;

-- 3) TRILHAS DO ALUNO  (esperado: 50.424 linhas)
SELECT * FROM user_quiz_category ORDER BY quiz_category_id, user_id;


-- ---------------------------------------------------------------------------
-- Se o quiz_user for grande e o arquivo nao couber, mande primeiro so isto,
-- que e uma linha de resposta, e eu te digo como fatiar:
--
--   SELECT COUNT(*) AS linhas, MIN(id) AS menor, MAX(id) AS maior FROM quiz_user;
-- ---------------------------------------------------------------------------


-- ===========================================================================
-- PARTE 2 -- A PROXIMA LEITURA
--
-- A lista de tabelas mostrou 14 que nunca vieram. Duas delas mudam o que da
-- para fazer no painel (ver migracao/tabelas-que-nao-vieram.md). Antes de
-- pedir CSV de 1,9 milhao de linhas, preciso ver a ESTRUTURA -- e isso e uma
-- linha de resposta por consulta, nao um arquivo.
--
-- IMPORTANTE: uma consulta por vez. Depois de uma consulta no
-- information_schema o phpMyAdmin executa a seguinte NESSE banco, e a
-- segunda falha com "#1109 Unknown table 'x' in information_schema".
-- ===========================================================================

-- 1) O aluno 66044, o decimo. Mesmas colunas que voce ja mandou dos outros 9.
SELECT id, name, email, phone, state, created_at, is_active
  FROM user WHERE id = 66044;

-- 2) ESTRUTURA das sete que valem olhar. Uma linha de resposta cada.
--    Rode uma, me mande, rode a seguinte.
SHOW CREATE TABLE quiz_user_question_answer;
SHOW CREATE TABLE postback;
SHOW CREATE TABLE setting;
SHOW CREATE TABLE access_rule;
SHOW CREATE TABLE taggables;
SHOW CREATE TABLE imageables;
SHOW CREATE TABLE menu;

-- 3) AMOSTRA das duas que importam de verdade. 5 linhas cada, so para eu ver
--    o que cada coluna realmente guarda -- nome de coluna mente, conteudo nao.
SELECT * FROM quiz_user_question_answer ORDER BY id LIMIT 5;
SELECT * FROM postback ORDER BY id DESC LIMIT 5;

-- 4) As tres pequenas inteiras. Somam 173 linhas: cabem na tela, sem CSV.
SELECT * FROM setting;
SELECT * FROM access_rule;
SELECT * FROM taggables;
SELECT * FROM imageables;

-- ---------------------------------------------------------------------------
-- CUIDADO COM O QUE VOLTA EM `setting` E EM `postback`.
--
-- `setting` costuma guardar chave de gateway, token de API e senha de SMTP.
-- `postback` pode trazer dado de cartao mascarado e CPF do comprador.
--
-- Se aparecer chave, token ou senha: NAO cole no chat e nao mande para mim.
-- Troque o valor por "<segredo>" antes de enviar, ou pule a linha. O que eu
-- preciso e o NOME da configuracao, para saber o que o site antigo fazia --
-- o valor nao me serve para nada, e este repositorio e publico.
--
-- Se aparecer CPF ou cartao em `postback`: mande so as colunas de valor,
-- data, status e id do pedido. Nao preciso do resto, e dado de pagamento nao
-- entra em repositorio.
-- ---------------------------------------------------------------------------
