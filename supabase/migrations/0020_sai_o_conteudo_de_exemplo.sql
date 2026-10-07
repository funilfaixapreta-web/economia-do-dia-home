-- 0020 — fica so o que veio do PHP da plataforma antiga
--
-- O corte foi feito pelo marcador 'legacy-': questao, aula e modulo que vieram
-- do sistema antigo tem ref='legacy-N'; simulado e plano tem id='legacy-N'.
-- O que nao tem esse marcador foi criado como exemplo durante o prototipo.
--
-- DESATIVADO, nao apagado: DELETE, TRUNCATE e DROP dao timeout nesta sessao
-- (conferido, nao suposto -- inclusive o DROP, que eu tinha dado como barrado
-- sem testar). Desativar tem o mesmo efeito para o aluno: montar_simulado so
-- sorteia questao com ativo, e ver_aula exige aula com ativo.
--
--   7 questoes de exemplo   -> cfg-m1 (4), cfg-m2 (1), cnpi-cb-m1 (1), e uma
--                              "[teste] audio sem regra" que eu mesmo criei
--                              testando o gatilho de audio
--   8 categorias de exemplo -> cfg-m1 a cfg-m6, cnpi-cb-m1, cnpi-cb-m3
--                              (ids curtos; as do PHP tem slug longo)
--  14 aulas de exemplo      -> "Regulação e órgãos do SFN", "Renda fixa",
--                              "Introdução a valuation", "Ética e suitability"
--
-- O QUE NAO SAIU, E POR QUE:
--
--   3 cursos (cb, cg1, ct1)  nao sao exemplo: sao a estrutura que plano_cursos
--                            usa, inclusive para os planos legados de CNPI que
--                            a 0013 ligou. Apagar cortaria o acesso de quem
--                            comprou.
--   4 planos (completo,      nao sao exemplo: sao a loja de verdade, com preco
--   fundamentalista,         e cursos ligados. Os 18 planos legados estao
--   tecnico, valuation)      desativados desde a 0013 e nao vendem mais.
--   7 blocos_site            TODOS vieram do PHP (legacy-1 a legacy-8):
--                            rodape, topo, chamada de planos, botao do
--                            WhatsApp, promessa da home e DUAS landing pages
--                            de depoimentos -- que e onde devem estar os
--                            depoimentos reais que faltavam.
--   7 categorias cfp-* e     vieram do PHP (estao no _legacy_map) e estao
--   ancord-etica             vazias porque o sistema antigo nunca teve questao
--                            de CFP. Categoria do cliente, nao lixo nosso.
--   8 modulos, 3 liberacoes  nao tem coluna ativo. Ficaram inertes: modulo sem
--                            aula ativa nao mostra nada, e liberacao de aula
--                            inativa nao abre nada, porque ver_aula confere
--                            o ativo da aula antes de olhar a liberacao.

update public.questoes set ativo = false
 where (ref not like 'legacy-%' or ref is null) and ativo;

update public.categorias_questao set ativo = false
 where id in ('cfg-m1','cfg-m2','cfg-m3','cfg-m4','cfg-m5','cfg-m6','cnpi-cb-m1','cnpi-cb-m3')
   and not exists (select 1 from public._legacy_map m
                    where m.tipo='qc' and m.new_id = categorias_questao.id);

update public.aulas set ativo = false
 where (ref not like 'legacy-%' or ref is null) and ativo;

-- Depois: 5.098 questoes ativas (todas do PHP), 90 categorias ativas (todas do
-- PHP), 54 simulados ativos (todos do PHP), 0 aula ativa, 0 questao de exemplo
-- ativa. E a checagem que mais importava: ZERO simulado perdeu questao com
-- isso -- nenhum deles dependia de categoria de exemplo.
