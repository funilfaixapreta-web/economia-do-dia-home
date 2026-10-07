-- 0023 — fecha a importacao: os 9 alunos que faltavam e as 26 linhas deles
--
-- 11338 ja existia no banco novo (veio pelo e-mail), mas o id antigo nao
-- estava no user_list, entao nao tinha ponte em _mapa_aluno e as 2 provas
-- dele ficavam de fora.
--
-- 66036 a 66043 cadastraram no sistema antigo DEPOIS do export de alunos.
-- Entram agora com 11 provas e 13 trilhas.
--
-- Os 8 entram como os outros 66.000: e-mail confirmado, encrypted_password
-- vazio. Ninguem tem senha no banco novo -- o hash do Laravel nao serve para o
-- GoTrue, entao todos entram pelo "esqueci minha senha". A linha em
-- auth.identities e obrigatoria: sem ela o GoTrue nao reconhece o provedor
-- de e-mail e a recuperacao de senha falha.
--
-- O gatilho criar_aluno cuida de alunos, carteiras e movimentos (15 tokens
-- iniciais, igual a quem se cadastra hoje). O update depois grava o que o
-- gatilho nao tem de onde saber: telefone em E.164, origem e a data de
-- cadastro real. Aqui ela vai com hora, e nao truncada no dia como nos
-- 66.000 -- a hora existe nestes registros, e dado mais preciso nao se joga
-- fora por simetria.
--
-- Nenhum dos 8 e-mails esta em admins_convidados, conferido antes: ninguem
-- nasce admin por acidente.

insert into public._mapa_aluno (id_antigo, aluno_id, email)
values ('11338','55fe19ae-4db4-4008-935c-026fe8d037c3','fpaula@cetsp.com.br')
on conflict (id_antigo) do nothing;

do $mig$
declare r record; v_id uuid; v_ts timestamptz;
begin
  for r in
    select * from (values
      ('66036','Renato Gonçalves da Conceição','renatogoncalvesdaconceicao@gmail.com','61999398331','2026-09-30 16:25:42'),
      ('66037','Rafael Torres','rafaeltorres.empresas@gmail.com','67288288828','2026-09-30 19:23:39'),
      ('66038','Wendel','wendelcasa4@hotmail.com','21333343333','2026-09-30 21:34:23'),
      ('66039','João Heitor Zabel da Rocha','joaoheitorzabel1808@gmail.com','47988520136','2026-10-03 17:04:36'),
      ('66040','Wesley Paulo Sousa Santos','angelportinari17@gmail.com','77988794606','2026-10-05 11:20:28'),
      ('66041','Gabriella Rabelo','gabirabelorodriguesii@gmail.com','48988579157','2026-10-06 11:41:33'),
      ('66042','Antonia','antonia1356@gmail.com','72987645644','2026-10-06 16:14:34'),
      ('66043','Marcelo Rezende Machado Almeida','marcelo.rm.almeida@gmail.com','37999070186','2026-10-06 18:24:05')
    ) as t(id_antigo, nome, email, telefone, criado)
  loop
    -- rodar de novo nao duplica nem derruba: quem ja existe passa batido
    if exists (select 1 from auth.users u where lower(u.email) = lower(r.email)) then
      continue;
    end if;

    v_ts := (r.criado::timestamp) at time zone 'America/Sao_Paulo';
    v_id := gen_random_uuid();

    insert into auth.users
      (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
       raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values ('00000000-0000-0000-0000-000000000000', v_id,
            'authenticated','authenticated', r.email, '', v_ts,
            '{"provider":"email","providers":["email"]}'::jsonb,
            jsonb_build_object('nome', r.nome, 'legado', true),
            v_ts, v_ts);

    insert into auth.identities
      (provider_id, user_id, identity_data, provider, created_at, updated_at)
    values (v_id::text, v_id,
            jsonb_build_object('sub', v_id::text, 'email', r.email, 'email_verified', true),
            'email', v_ts, v_ts);

    update public.alunos
       set nome      = r.nome,
           telefone  = '+55'||r.telefone,
           origem    = 'legado',
           criado_em = v_ts
     where id = v_id;

    insert into public._mapa_aluno (id_antigo, aluno_id, email)
    values (r.id_antigo, v_id, r.email)
    on conflict (id_antigo) do nothing;
  end loop;
end $mig$;

-- Mesmas tres transformacoes da migracao/importar-o-que-falta.sql. Com as
-- pontes novas, as 26 linhas que faltavam encontram o aluno. O on conflict
-- garante que as 91.229 provas e 50.420 trilhas ja gravadas sejam ignoradas.
insert into public.tentativas
  (aluno_id, simulado_id, iniciada_em, enviada_em, nota, duracao_seg, origem, ref_antigo)
select m.aluno_id,
       'legacy-'||i.quiz_id,
       public._vazio(i.created_at)::timestamptz,
       public._vazio(i.created_at)::timestamptz,
       round(public._vazio(i.hit_percentage)::numeric)::int,
       case when public._vazio(i.elapsed_time) ~ '^[0-9]+$'
            then nullif(public._vazio(i.elapsed_time)::int, 0) * 60 end,
       'legado',
       i.id
  from public._imp_quiz_user i
  join public._mapa_aluno m on m.id_antigo = public._vazio(i.user_id)
  join public.simulados  s on s.id = 'legacy-'||public._vazio(i.quiz_id)
 where public._vazio(i.deleted_at) is null
   and public._vazio(i.created_at) is not null
   and public._vazio(i.hit_percentage) is not null
on conflict (ref_antigo) where ref_antigo is not null do nothing;

insert into public.trilhas_do_aluno (aluno_id, categoria_simulado_id, origem)
select distinct m.aluno_id, z.novo, 'legado'
  from public._imp_user_quiz_category i
  join public._mapa_aluno m on m.id_antigo = public._vazio(i.user_id)
  join (values ('1','cpa-20'),('2','cea'),('5','cpa-10'),('6','ancord'),
               ('8','cnpi-cb'),('9','cnpi-cg1'),('10','cnpi-ct1'),('11','cfg')
       ) as z(antigo, novo) on z.antigo = public._vazio(i.quiz_category_id)
 where public._vazio(i.deleted_at) is null
on conflict (aluno_id, categoria_simulado_id) do nothing;

-- Historico de assinatura que ficou sem aluno porque o id antigo nao tinha
-- ponte. Para estes 9 deu zero (nenhum tem linha em subscription_log), mas a
-- instrucao fica: e a mesma que religa qualquer ponte criada depois.
update public.matriculas_historico h
   set aluno_id = m.aluno_id
  from public._mapa_aluno m
 where h.aluno_id is null
   and m.id_antigo = h.id_aluno_antigo;

-- ===========================================================================
-- CONFERIDO DEPOIS DE APLICAR — 07/10/2026
--
--   provas (origem legado) ......... 91.242  = alvo   EXATO
--   trilhas ........................ 50.433  = alvo   EXATO
--   provas sem tempo (era 0) ....... 1.605   = alvo   EXATO
--   log de assinatura .............. 2.625   = alvo   EXATO
--   log sem aluno conhecido ........ 12      (nao sao destes 9)
--   alunos / auth.users ............ 66.014 / 66.014
--   auth.identities ................ 66.014  (1 por aluno, nenhum sem)
--   carteiras ...................... 66.014  (nenhum aluno sem carteira)
--   _mapa_aluno .................... 65.886
--   linhas de _imp_ sem ponte ...... 0 provas, 0 trilhas
--   nota fora de 0-100 ............. 0
--   duracao acima de 3h ............ 0
--   alunos distintos com prova ..... 3.726   (3.718 + 8; o 66037 tem trilha
--                                            mas nenhuma prova)
--
-- Por categoria, as oito bateram EXATAS com a quebra medida no antigo:
--   cpa-10 17.960  cpa-20 17.213  cea 5.195  ancord 3.239
--   cnpi-cb 2.306  cnpi-cg1 2.011  cnpi-ct1 1.876  cfg 633   (soma 50.433)
--
-- Nao sobrou nenhuma linha dos tres arquivos sem importar.
-- ===========================================================================
