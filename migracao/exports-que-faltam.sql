-- ===========================================================================
-- Tres exports do sistema antigo, para terminar a migracao.
-- Rode cada um no phpMyAdmin e exporte como CSV com cabecalho.
-- Nenhum leva e-mail, nome, telefone ou CPF: so ids, datas e notas. O id do
-- aluno eu ja sei casar com o do banco novo (65.877 de 66.000 mapeados).
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 0) ESTRUTURA — rode primeiro e me mande o resultado.
--    Eu nao conheco as colunas de quiz_user, e nao quero adivinhar.
-- ---------------------------------------------------------------------------
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, IS_NULLABLE
  FROM information_schema.COLUMNS
 WHERE TABLE_SCHEMA = 'u884123692_economiadodia'
   AND TABLE_NAME IN ('quiz_user','subscription_log','user_quiz_category')
 ORDER BY TABLE_NAME, ORDINAL_POSITION;

-- ---------------------------------------------------------------------------
-- 1) HISTORICO DE PROVA  (quiz_user)
--    Ajuste os nomes das colunas conforme o resultado do passo 0.
--    Se houver coluna de acertos/total, inclua; se nao houver, deixe de fora.
-- ---------------------------------------------------------------------------
SELECT id, user_id, quiz_id, created_at
  FROM quiz_user
 ORDER BY id;

-- ---------------------------------------------------------------------------
-- 2) LOG DE ASSINATURA  (subscription_log, 2.625 linhas)
-- ---------------------------------------------------------------------------
SELECT id, subscription_id, user_id, plan_id, expiration_at, is_active, created_at
  FROM subscription_log
 ORDER BY id;

-- ---------------------------------------------------------------------------
-- 3) TRILHAS DO ALUNO  (user_quiz_category, 50.424 linhas)
--    Se o CSV ficar grande demais para anexar, exporte so o agregado:
--      SELECT quiz_category_id, COUNT(*) FROM user_quiz_category GROUP BY 1;
--    e me mande o arquivo completo depois, ou em partes por categoria.
-- ---------------------------------------------------------------------------
SELECT user_id, quiz_category_id
  FROM user_quiz_category
 ORDER BY quiz_category_id, user_id;
