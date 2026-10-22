-- 0029 — dá para EDITAR a aula, e o quiz de fixacao passa a existir
--
-- Tres buracos que a tela de Videos expos:
--
-- 1. NAO DAVA PARA EDITAR. O editor de aula do painel trabalha com indices do
--    db LOCAL (curso, modulo, aula). As 314 aulas estao no banco e nao no
--    localStorage de quem abre o painel, entao o botao Editar nunca achava a
--    aula -- na pratica a tela era so leitura.
--
-- 2. O QUIZ DE FIXACAO NAO EXISTIA. Os campos "categoria de perguntas" e
--    "quantidade" so apareciam no adm.html: nao estao em publicar_conteudo
--    nem em lugar nenhum do app.html. Quem preenchia salvava no proprio
--    navegador e pronto -- o aluno nunca via quiz nenhum. Agora sao colunas.
--
-- 3. NAO DAVA PARA ACRESCENTAR. So criando curso e modulo no painel e
--    publicando tudo. criar_aula() resolve pelo banco.
--
-- As tres funcoes exigem eh_admin() e mexem em UMA aula por vez. Isso e de
-- proposito: publicar_conteudo() reescreve o pacote inteiro a partir do
-- localStorage de quem clicou, e com 314 aulas no banco e 7 no rascunho de um
-- navegador qualquer, isso e uma arma apontada para o pe.

alter table public.aulas
  add column if not exists quiz_categoria_id text,
  add column if not exists quiz_quantidade   int;

do $mig$
begin
  if not exists (select 1 from pg_constraint where conname='aulas_quiz_categoria_fk') then
    alter table public.aulas
      add constraint aulas_quiz_categoria_fk
      foreign key (quiz_categoria_id) references public.categorias_questao(id)
      on delete set null;
  end if;
  if not exists (select 1 from pg_constraint where conname='aulas_quiz_quantidade_ck') then
    alter table public.aulas
      add constraint aulas_quiz_quantidade_ck
      check (quiz_quantidade is null or quiz_quantidade between 1 and 50);
  end if;
end $mig$;

comment on column public.aulas.quiz_categoria_id is
  'Categoria de questoes do quiz de fixacao desta aula. A chave estrangeira
   existe para o quiz nao apontar para categoria apagada -- era o tipo de erro
   que so apareceria para o aluno, no meio da aula.';

-- salvar_aula / criar_aula / opcoes_de_aula / aulas_admin / ver_aula:
-- corpos completos conforme aplicado no banco. Campo ausente no jsonb NAO e
-- campo apagado: salvar_aula() so toca no que foi mandado, e por isso o teste
-- e "a chave existe?" (p ? 'titulo') e nao "o valor e nulo?".
--
-- aulas_admin() ganhou quiz_categoria, quiz_quantidade e quiz_disponivel --
-- este ultimo e quantas questoes ATIVAS a categoria tem. Sem esse numero,
-- pedir 10 questoes de uma categoria que tem 6 passa batido no painel e vira
-- prova curta na cara do aluno.
--
-- Conferido trocando de papel, com a transacao abortada no fim:
--   aluno comum .................. salvar e criar barrados (42501)
--   salvar so o quiz ............. titulo e duracao INTACTOS
--   categoria inexistente ........ categoria-nao-encontrada
--   quantidade 99 ................ quantidade-fora-de-1-a-50
--   sem aula_id .................. sem-aula_id
--   criar_aula ................... ok, ref 'painel:<uuid>'
--   opcoes_de_aula ............... 42 modulos, 90 categorias
