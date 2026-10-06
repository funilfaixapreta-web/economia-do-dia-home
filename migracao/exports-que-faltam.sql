-- ===========================================================================
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
