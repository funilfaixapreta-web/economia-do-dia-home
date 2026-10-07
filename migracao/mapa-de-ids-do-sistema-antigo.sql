-- ===========================================================================
-- Mapa de ids do sistema antigo -> ids do banco novo
--
-- Isto vivia SO dentro da tabela public._legacy_map, que estava marcada para
-- ser apagada. O mapa de trilha (zc) eu ja havia copiado para dentro do
-- script de importacao, mas o de categoria de questao (qc) -- 90 linhas de id
-- numerico para slug -- nao estava em lugar nenhum. Apagar a tabela teria
-- obrigado alguem a reconstruir isso a mao na virada.
--
-- Agora esta no git. A tabela _legacy_map passou a ser descartavel de fato.
--
-- Para recriar o mapa num banco onde ele nao exista:
--   create table public._legacy_map (tipo text, old_id text, new_id text);
--   e rodar o insert abaixo.
--
-- tipo 'qc' = question_category (categoria de questao)
-- tipo 'zc' = quiz_category     (trilha)
-- ===========================================================================

insert into public._legacy_map (tipo, old_id, new_id) values
  ('qc','1','cpa-20-sistema-financeiro-nacional-e-participantes-do-mercado'),
  ('qc','2','cpa-20-compliance-legal-etica-e-analise-de-perfil-do-investidor'),
  ('qc','3','cpa-20-principios-basicos-de-economia-e-financas'),
  ('qc','4','cpa-20-instrumentos-de-renda-variavel-renda-fixa-e-derivativos'),
  ('qc','5','cpa-20-fundos-de-investimento'),
  ('qc','6','cpa-20-previdencia-complementar-aberta-pgbl-e-vgbl'),
  ('qc','7','cpa-20-mensuracao-e-gestao-de-performance-e-riscos'),
  ('qc','8','cfp-planejamento-financeiro-e-etica'),
  ('qc','9','cfp-gestao-de-ativos-e-investimentos'),
  ('qc','10','cfp-planejamento-de-aposentadoria'),
  ('qc','11','cfp-gestao-de-riscos-e-seguros'),
  ('qc','12','cfp-planejamento-fiscal'),
  ('qc','13','cfp-planejamento-sucessorio'),
  ('qc','14','cea-sistema-financeiro-nacional-e-participantes-do-mercado'),
  ('qc','15','cea-principios-basicos-de-economia-e-financas'),
  ('qc','16','cea-instrumentos-de-renda-fixa-renda-variavel-e-derivativos'),
  ('qc','17','cea-fundos-de-investimentos'),
  ('qc','18','cea-produtos-de-previdencia-complementar'),
  ('qc','19','cea-gestao-de-carteiras-e-riscos'),
  ('qc','20','cea-planejamento-de-investimento'),
  ('qc','21','cpa-10-sistema-financeiro-nacional-e-participantes-do-mercado'),
  ('qc','22','cpa-10-etica-regulamentacao-e-analise-do-perfil-do-investidor'),
  ('qc','23','cpa-10-nocoes-de-economia-e-financas'),
  ('qc','24','cpa-10-principios-de-investimento'),
  ('qc','25','cpa-10-fundos-de-investimento'),
  ('qc','26','cpa-10-instrumentos-de-renda-variavel-e-renda-fixa'),
  ('qc','27','cpa-10-previdencia-complementar-aberta-pgbl-e-vgbl'),
  ('qc','28','ancord-a-atividade-do-agente-autonomo-de-investimento'),
  ('qc','29','ancord-outros-fundos-de-investimento'),
  ('qc','30','ancord-securitizacao-de-recebiveis'),
  ('qc','31','ancord-clube-de-investimentos'),
  ('qc','32','ancord-matematica-financeira'),
  ('qc','33','ancord-mercado-de-capitais'),
  ('qc','34','ancord-mercados-de-derivativos'),
  ('qc','35','ancord-etica-nos-negocios-do-aai'),
  ('qc','36','ancord-lavagem-de-dinheiro'),
  ('qc','37','ancord-economia'),
  ('qc','38','ancord-sistema-financeiro-nacional'),
  ('qc','39','ancord-instituicoes-e-intermediadores-financeiros'),
  ('qc','40','ancord-administracao-de-risco'),
  ('qc','41','ancord-mercado-de-capitais-outros-produtos-nao-classificados-como-valores-mobili'),
  ('qc','42','ancord-fundos-de-investimentos'),
  ('qc','49','cnpi-cb-m1-sistema-financeiro-nacional'),
  ('qc','50','cnpi-cb-m2-mercado-de-capitais'),
  ('qc','51','cnpi-cb-m3-mercado-de-renda-fixa'),
  ('qc','52','cnpi-cb-m4-mercado-de-derivativos'),
  ('qc','53','cnpi-cb-m5-conceitos-economicos'),
  ('qc','54','cnpi-cb-m6-conduta-e-relacionamento'),
  ('qc','55','cnpi-cb-m7-governanca-corporativa-e-relacoes-com-investidores'),
  ('qc','56','cnpi-cb-m8-integracao-de-questoes-asg-a-analise-de-investimentos'),
  ('qc','57','cnpi-cg1-m1-modelos-de-avaliacao-de-acoes'),
  ('qc','58','cnpi-cg1-m2-analise-das-operacoes-da-empresa'),
  ('qc','59','cnpi-cg1-m3-analise-setorial'),
  ('qc','60','cnpi-cg1-m4-financas-corporativas'),
  ('qc','61','cnpi-cg1-m5-decisoes-de-financiamento-de-longo-prazo'),
  ('qc','62','cnpi-cg1-m6-decisoes-de-financiamento-de-curto-prazo'),
  ('qc','63','cnpi-cg1-m7-estrutura-de-capital-e-politica-de-dividendos'),
  ('qc','64','cnpi-cg1-m8-fusoes-e-aquisicoes'),
  ('qc','65','cnpi-cg1-m9-financas-corporativas-internacionais'),
  ('qc','66','cnpi-cg1-m10-demonstracoes-contabeis'),
  ('qc','67','cnpi-cg1-m11-elaboracao-de-relatorios'),
  ('qc','68','cnpi-cg1-m12-estrutura-conceitual-basica'),
  ('qc','69','cnpi-cg1-m13-demonstracao-dos-fluxos-de-caixa'),
  ('qc','70','cnpi-cg1-m14-ativos-passivos-e-patrimonio-liquido'),
  ('qc','71','cnpi-cg1-m15-conversao-das-demonstracoes-contabeis-para-moeda-estrangeira'),
  ('qc','72','cnpi-cg1-m16-relatorios-contabeis-e-analise-das-demonstracoes-contabeis'),
  ('qc','73','cnpi-cg1-m17-instrumentos-analiticos-para-estimar-retornos-e-riscos'),
  ('qc','74','cnpi-cg1-m18-questoes-asg-na-analise-fundamentalista'),
  ('qc','75','cnpi-ct1-m1'),
  ('qc','76','cnpi-ct1-m2'),
  ('qc','77','cnpi-ct1-m3'),
  ('qc','78','cnpi-ct1-m4'),
  ('qc','79','cnpi-ct1-m5'),
  ('qc','80','cnpi-ct1-m6'),
  ('qc','81','cnpi-ct1-m7'),
  ('qc','82','cnpi-ct1-m8'),
  ('qc','83','cnpi-ct1-m9'),
  ('qc','84','cnpi-ct1-m10'),
  ('qc','85','cfg-m1-metodos-quantitativos'),
  ('qc','86','cfg-m2-economia'),
  ('qc','87','cfg-m3-analise-de-relatorios-financeiros'),
  ('qc','88','cfg-m4-financas-corporativas'),
  ('qc','89','cfg-m6-teoria-de-carteiras'),
  ('qc','90','cfg-m7-financas-comportamentais'),
  ('qc','91','cfg-m8-politica-de-investimentos'),
  ('qc','92','cfg-m9-alocacao-de-ativos'),
  ('qc','93','cfg-m5-mercados-e-instrumentos-financeiros'),
  ('qc','94','cfg-m10-novas-tecnologias-em-financas'),
  ('qc','95','cfg-m11-etica-e-autorregulacao'),
  ('qc','96','cfg-m12-legislacao-e-regulacao'),
  ('zc','1','cpa-20'),
  ('zc','2','cea'),
  ('zc','5','cpa-10'),
  ('zc','6','ancord'),
  ('zc','8','cnpi-cb'),
  ('zc','9','cnpi-cg1'),
  ('zc','10','cnpi-ct1'),
  ('zc','11','cfg');

-- Observacao: os ids 43 a 48 nao existem no qc, e 3, 4 e 7 nao existem no zc.
-- Sao lacunas do proprio sistema antigo (categoria criada e removida), nao
-- perda na copia. Conferido: os 98 new_id acima existem no banco novo.
