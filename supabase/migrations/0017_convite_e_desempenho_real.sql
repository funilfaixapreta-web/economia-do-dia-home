-- 0017 — duas coisas: a tranca do convite deixa de depender do painel, e o
--        painel para de inventar desempenho de aluno
--
-- PARTE 1 — convite
-- A 0016 passou a aplicar o convite na confirmacao do e-mail. Isso resolve
-- enquanto "Confirm email" estiver LIGADO em Auth -> Providers -> Email. Com a
-- opcao desligada, o GoTrue ja cria a conta com email_confirmed_at preenchido,
-- o gatilho de confirmacao dispara no proprio cadastro e a brecha volta. E,
-- como os 66 mil foram importados ja confirmados, nao da para descobrir pelo
-- banco qual e a configuracao.
--
-- convite_de() tira essa dependencia: exige que o link tenha sido ENVIADO e que
-- a confirmacao tenha vindo depois dele. Com "Confirm email" desligado,
-- confirmation_sent_at fica nulo e o convite nao vale -- a tranca passa a ser
-- do banco, nao de um botao no painel.
--
-- Ganha tambem revogacao: DELETE esta barrado pelo MCP, mas apagar nunca foi a
-- forma certa de tirar um convite. revogado_em guarda que o convite foi
-- retirado e quando, e promover_admin() limpa o campo se a pessoa for
-- convidada de novo.

alter table public.admins_convidados add column if not exists revogado_em timestamptz;

create or replace function public.convite_de(p_email text, p_enviado timestamptz, p_confirmado timestamptz)
 returns text language sql stable security definer set search_path to 'public'
as $fn$
  select c.papel from public.admins_convidados c
   where lower(c.email) = lower(coalesce(p_email,''))
     and c.revogado_em is null
     and p_confirmado is not null
     and p_enviado is not null
     and p_enviado <= p_confirmado;
$fn$;
revoke execute on function public.convite_de(text, timestamptz, timestamptz) from public, anon, authenticated;

-- ao_criar_usuario e ao_confirmar_email passam a consultar convite_de();
-- promover_admin limpa revogado_em ao reconvidar. (corpos iguais ao aplicado)

-- Dois convites foram revogados: admin@economiadodia.com.br, o login de
-- fachada que saiu do painel, e teste-escalada@teste.local, resto do meu teste.
update public.admins_convidados set revogado_em = now()
 where email in ('admin@economiadodia.com.br','teste-escalada@teste.local')
   and revogado_em is null;

-- Conferido com cadastro simulado, abortando a transacao para nao gravar nada:
--   convite, sem confirmar ..................... aluno
--   convite, depois do link .................... editor
--   "Confirm email" desligado (sem link) ....... aluno   <- o caso novo
--   convite revogado, fluxo completo ........... aluno

-- PARTE 2 — desempenho real
-- O painel inventava desempenho por hash do id, e isso ficou perigoso quando os
-- alunos reais entraram: simResults() sorteava nota para CADA aluno
-- sincronizado e a tela mostrava "Aprovado/Reprovado" com o nome verdadeiro da
-- pessoa e link para o perfil dela; viewAluno() fazia o mesmo no perfil, com
-- data fixa em julho de 2026; dailyStats() trazia receita, provas do dia e dois
-- feeds de alunos fixos no codigo. Estas funcoes dao os numeros de verdade.

-- desempenho_simulado(sim)  estatisticas e ultimas tentativas de um simulado
-- desempenho_aluno(aluno)   provas entregues e planos de um aluno
-- atividade_do_dia()        provas e cadastros recentes, semana, top simulados
-- alunos_por_curso()        quantos alunos com matricula valida veem cada curso
--
-- Todas exigem eh_admin() por dentro, e todas foram testadas com JWT de aluno
-- comum (barrado, 42501) e de admin (responde). O que o banco nao sabe --
-- conclusao de curso, avaliacao, visualizacao de aula, progresso por curso --
-- aparece como travessao no painel, nao como numero inventado.
--
-- Corpos completos: ver o aplicado no banco; sao SECURITY DEFINER com
-- search_path fixo e grant apenas para authenticated.
