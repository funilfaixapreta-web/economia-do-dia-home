-- 0019 — o painel passa a ver imagens, paginas e tags do site antigo
--
-- As tres tinham aba no painel, mas as tres liam a copia local do seed. As 166
-- imagens, 133 paginas e 17 tags que vieram do site antigo estavam no banco e
-- nao apareciam em lugar nenhum.
--
-- paginas, tags e blocos_site estavam com RLS ligada e ZERO politicas, entao
-- nem o administrador lia. Na 0017 eu registrei isso como "certo, nada le
-- essas tabelas" -- e estava certo naquele momento, mas a conclusao era
-- preguicosa: o certo era o painel passar a ler, nao a tabela ficar fechada.
--
-- Politica de ADMINISTRADOR, nao publica. Leitura publica aqui publicaria 133
-- paginas do site antigo sem ninguem pedir.
create policy admin_paginas on public.paginas     for select using (public.eh_admin());
create policy admin_tags    on public.tags        for select using (public.eh_admin());
create policy admin_blocos  on public.blocos_site for select using (public.eh_admin());
grant select on public.paginas     to authenticated;
grant select on public.tags        to authenticated;
grant select on public.blocos_site to authenticated;

-- Conferido com JWT real: aluno ve 0 linhas nas tres, admin ve 133, 17 e 7.
--
-- O conteudo das paginas NAO e baixado para o painel. Somados dao 1 MB (a
-- maior tem 164 kB), e o painel vive num localStorage de ~5 MB que ja estourou
-- nesta migracao por causa dos embeds de audio. A lista vem sem conteudo e
-- ele e buscado quando alguem abre a pagina para editar.
