/* ============================================================================
   Economia do Dia · 0011 · fechamento de seguranca
   ----------------------------------------------------------------------------
   Auditoria do banco inteiro: advisors do Supabase, privilegios de tabela e
   de coluna, politicas de RLS e as 22 funcoes. O que estava aberto:

   1. VAZAMENTO DO AUDIO DO GABARITO  (o mais grave)

      A coluna questoes.audio_url estava legivel pela role anon. Ou seja, sem
      login nenhum:

          GET /rest/v1/questoes?select=enunciado,audio_url

      devolvia as 5.110 questoes com o link do gabarito comentado em audio --
      que e justamente o que se vende. A 0007 tinha criado audio_regra para
      controlar isso em gabarito_tentativa(), mas a coluna crua continuava
      aberta ao lado, e coluna aberta ganha de regra em funcao.

      E o mesmo erro da 0003 e da 0009: RLS filtra LINHA, nao COLUNA.

   2. A PROVA ENTREGAVA A EXPLICACAO JUNTO COM A PERGUNTA

      montar_simulado() devolvia audio_embed dentro de cada questao. O audio e
      a explicacao da resposta: ele pertence ao gabarito, depois de entregar a
      prova, nao ao enunciado. Nenhuma tela usava esse campo -- estava so
      vazando.

   3. TABELA DE TESTE ESQUECIDA

      public._t, sem RLS e com todos os privilegios para anon. Sobra de uma
      sessao de depuracao. Apagada.

   4. ESCRITA DIRETA EM TODAS AS TABELAS

      anon e authenticated tinham insert/update/delete/truncate em tudo. So o
      RLS segurava -- e o RLS nao vale para TRUNCATE. O navegador nunca
      escreve direto em tabela nenhuma: cadastro e login vao pelo GoTrue, e
      todo o resto passa por funcao SECURITY DEFINER. Entao o privilegio nao
      tinha por que existir.

      Junto: as default privileges do schema, para tabela nova nao nascer
      aberta e alguem ter que lembrar de fechar depois.

   5. FUNCAO DE GATILHO EXPOSTA COMO ENDPOINT

      ao_trocar_email() e alunos_campos_travados() sao gatilhos, mas estavam
      em /rest/v1/rpc/. Chamar direto ja dava erro (falta contexto de
      gatilho); mesmo assim, o que nao e endpoint nao fica na porta.

   6. search_path solto em duas funcoes -- porta para sequestro por schema.

   7. A COMPOSICAO DA PROVA ERA PUBLICA

      A politica de leitura de composicoes era "true": qualquer um via de
      quais categorias cada simulado sorteia e quantas questoes de cada. E o
      mapa da prova. So o painel le isso, e sempre como admin.

   O QUE **NAO** FOI MUDADO, DE PROPOSITO

   Os advisors continuam avisando que funcoes SECURITY DEFINER podem ser
   chamadas por anon/authenticated. Elas SAO a API -- e cada uma confere por
   dentro quem esta chamando (eh_admin(), auth.uid(), dono da tentativa).
   Revogar seria desligar o site. Ficou testado, com um aluno de verdade:

     ler o audio do gabarito direto ....... barrado
     ver qual alternativa e a correta ..... barrado
     ver a composicao das provas .......... barrado
     se matricular sozinho ................ barrado
     encher a propria carteira de tokens .. barrado
     marcar o proprio pedido como pago .... barrado
     apagar o banco de questoes ........... barrado
     publicar conteudo .................... barrado
     se dar tokens ........................ barrado
     ler os pedidos de todo mundo ......... barrado
     chamar a funcao de gatilho ........... barrado
     virar admin sozinho .................. barrado
     ler o enunciado ...................... ok (tem que poder)
     cadastros que enxerga ................ 1 (so o dele)

   E o que precisa funcionar continua funcionando: publicar, ler a composicao
   como admin, abrir o catalogo, fazer a prova (2 questoes sorteadas), entregar
   e receber o gabarito, editar o proprio perfil.
   ============================================================================ */

drop table if exists public._t;

revoke select (audio_url, audio_embed) on public.questoes from anon, authenticated;

/* tira audio_embed do payload da prova sem reescrever a funcao inteira */
do $mig$
declare v text;
begin
  select pg_get_functiondef(p.oid) into v
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='montar_simulado';
  v := replace(v, $a$               'audio_embed', q.audio_embed,
$a$, '');
  execute v;
end $mig$;

do $mig$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname='public' loop
    execute format(
      'revoke insert, update, delete, truncate, references, trigger on public.%I from anon, authenticated',
      t.tablename);
  end loop;
end $mig$;

alter default privileges in schema public
  revoke insert, update, delete, truncate, references, trigger on tables from anon, authenticated;

revoke execute on function public.ao_trocar_email() from public, anon, authenticated;
revoke execute on function public.alunos_campos_travados() from public, anon, authenticated;

alter function public.track_do_audio(text) set search_path = public;
alter function public.alunos_campos_travados() set search_path = public;

drop policy if exists catalogo_comp on public.composicoes;
create policy admin_le_comp on public.composicoes
  for select using (public.eh_admin());
