-- ===========================================================================
-- Economia do Dia · faixas de audio que ja nao existem mais
-- ---------------------------------------------------------------------------
-- Os gabaritos comentados nao estao no servidor do site: sao faixas da conta
-- economiadodia no SoundCloud (soundcloud.com/user-87449170), embutidas por
-- iframe. O levantamento das 4.395 questoes com audio encontrou 1.957 faixas
-- distintas — a mesma faixa se repete porque a questao e reaproveitada entre
-- certificacoes. Dessas, 104 respondem 404: sumiram. Afetam 109 questoes,
-- quase todas do CNPI-CT1 (analise tecnica).
--
-- Sem isto o aluno abre a revisao e recebe um player que nao toca, sem
-- explicacao. Com isto o audio nao e oferecido nessas questoes e a tela sabe
-- dizer que esta indisponivel.
--
-- Guardado como TABELA, nao como UPDATE nas questoes: republicar o conteudo
-- pelo painel sobrescreve as colunas da questao, mas nao mexe aqui. A
-- informacao sobrevive a qualquer nova carga.
--
-- Aplicada no projeto ernqeokvkytwdlmjupwm em 18/08/2026.
-- ===========================================================================
create table if not exists public.audios_indisponiveis (
  track_id     text primary key,
  motivo       text not null default '404 no SoundCloud',
  conferido_em timestamptz not null default now()
);
alter table public.audios_indisponiveis enable row level security;

drop policy if exists audios_ind_leitura on public.audios_indisponiveis;
create policy audios_ind_leitura on public.audios_indisponiveis for select using (true);
drop policy if exists audios_ind_admin on public.audios_indisponiveis;
create policy audios_ind_admin on public.audios_indisponiveis for all
  using (public.eh_admin()) with check (public.eh_admin());

-- Tira o id da faixa de dentro da URL do player. Aceita a forma escapada
-- (tracks%3A / tracks%2F) e a normal, que aparecem misturadas no export.
create or replace function public.track_do_audio(p_url text)
returns text
language sql
immutable
as $$ select (regexp_match(coalesce(p_url,''), 'tracks[/%3A]*([0-9]{6,})'))[1] $$;

insert into public.audios_indisponiveis (track_id) values
('693925780'),('697240367'),('1446184660'),('1446198319'),('1446212764'),
('1446219910'),('1446227572'),('1460751475'),('1541883484'),('1541911351'),
('1541943703'),('1541968012'),('1547892739'),('1547910454'),('1547923162'),
('1547931838'),('1547934925'),('1547937217'),('1547941630'),('1547945296'),
('1547948695'),('1547950426'),('1547953003'),('1547957770'),('1547959552'),
('1547961127'),('1547963482'),('1547966899'),('1557539083'),('1557544312'),
('1557548239'),('1557550765'),('1557553087'),('1557555754'),('1557561085'),
('1557562621'),('1557564481'),('1557573247'),('1557790420'),('1557800911'),
('1557802960'),('1557813910'),('1557819448'),('1571149531'),('1571181232'),
('1571181979'),('1571183182'),('1571183746'),('1571184766'),('1571185369'),
('1571186464'),('1571240248'),('1571241031'),('1571241790'),('1571242654'),
('1571243869'),('1571244718'),('1571245573'),('1571246800'),('1571247709'),
('1571248759'),('1571249584'),('1571250331'),('1571251087'),('1571251582'),
('1571252311'),('1571252707'),('1571253205'),('1571253805'),('1571254360'),
('1571255125'),('1571255788'),('1571256640'),('1571259976'),('1571263666'),
('1571266255'),('1596113994'),('1596115536'),('1596116619'),('1596116910'),
('1596117174'),('1596117456'),('1596117816'),('1596118113'),('1596118377'),
('1764317082'),('1764317517'),('1764317919'),('1764318255'),('1764318501'),
('1764318867'),('1764319191'),('1764319452'),('1764319629'),('1764319941'),
('1764320172'),('1764320652'),('1778456946'),('1778457981'),('1778458836'),
('1778462382'),('1778463132'),('1778463483'),('1778464644')
on conflict (track_id) do nothing;

-- ---------------------------------------------------------------------------
-- gabarito_tentativa passa a esconder o audio das faixas mortas e a dizer
-- "audio_indisponivel" para a tela. Reescrita a partir de si mesma para nao
-- reescrever a funcao inteira na mao.
-- ---------------------------------------------------------------------------
do $B$
declare def text;
begin
  select pg_get_functiondef(p.oid) into def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='gabarito_tentativa';

  def := replace(def,
    'case when v_assinante or coalesce(q.audio_regra,'''') !~* ''assinante''
                                   then q.audio_url end',
    'case when (v_assinante or coalesce(q.audio_regra,'''') !~* ''assinante'')
                                    and not exists (select 1 from public.audios_indisponiveis x
                                                     where x.track_id = public.track_do_audio(q.audio_url))
                                   then q.audio_url end');
  def := replace(def,
    'case when v_assinante or coalesce(q.audio_regra,'''') !~* ''assinante''
                                   then q.audio_embed end',
    'case when (v_assinante or coalesce(q.audio_regra,'''') !~* ''assinante'')
                                    and not exists (select 1 from public.audios_indisponiveis x
                                                     where x.track_id = public.track_do_audio(q.audio_url))
                                   then q.audio_embed end');
  def := replace(def,
    '''audio_bloqueado'',',
    '''audio_indisponivel'', exists (select 1 from public.audios_indisponiveis x
                                      where x.track_id = public.track_do_audio(q.audio_url)),
               ''audio_bloqueado'',');

  execute def;
end $B$;
