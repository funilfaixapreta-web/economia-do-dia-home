-- ============================================================================
-- Economia do Dia · estrutura inicial
-- ----------------------------------------------------------------------------
-- Tira a plataforma do localStorage: conta de aluno, carteira de tokens,
-- liberacoes, cursos/aulas, banco de questoes, simulados e matriculas.
--
-- A regra de acesso vive AQUI, no banco, com Row Level Security. Quem nao
-- comprou e nao gastou token nao recebe a linha -- nem pelo site, nem pela
-- API, nem pelo DevTools. Era o "anti-scraping" que o escopo pede e que o
-- controle no front-end nunca entregou.
-- ============================================================================

-- ---------------------------------------------------------------- 1. ALUNOS
-- Espelha auth.users. O telefone e UNICO: foi a decisao da reuniao de 05/08
-- para impedir que a mesma pessoa crie varias contas e refaca o simulado.
create table public.alunos (
  id                     uuid primary key references auth.users(id) on delete cascade,
  nome                   text not null,
  email                  text not null unique,
  telefone               text unique,
  telefone_verificado_em timestamptz,
  papel                  text not null default 'aluno'
                         check (papel in ('aluno','professor','editor','admin')),
  origem                 text,
  criado_em              timestamptz not null default now()
);

create or replace function public.eh_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.alunos
                  where id = auth.uid() and papel in ('admin','editor'));
$$;

-- ---------------------------------------------------------------- 2. TOKENS
-- Uma linha so, editavel em Admin > Sistema > Tokens.
create table public.config_tokens (
  id             boolean primary key default true check (id),
  ativo          boolean not null default true,
  inicial        int     not null default 15,
  renova_mes     boolean not null default false,
  custo_simulado int     not null default 10,
  custo_aula     int     not null default 2,
  custo_ia       int     not null default 1,
  atualizado_em  timestamptz not null default now()
);
insert into public.config_tokens (id) values (true);

create table public.carteiras (
  aluno_id    uuid primary key references public.alunos(id) on delete cascade,
  saldo       int not null default 0 check (saldo >= 0),
  base        int not null default 0,   -- saldo inicial vigente quando foi criada
  competencia text,                     -- 'AAAA-M' da ultima recarga mensal
  criada_em   timestamptz not null default now()
);

-- Extrato: toda entrada e saida fica registrada.
create table public.movimentos (
  id         bigserial primary key,
  aluno_id   uuid not null references public.alunos(id) on delete cascade,
  quantidade int  not null,             -- negativo = consumo
  motivo     text not null,             -- credito-inicial | consumo:aula | cortesia | recarga-mensal
  referencia text,
  criado_em  timestamptz not null default now()
);
create index on public.movimentos (aluno_id, criado_em desc);

-- Conteudo ja pago nao cobra de novo: rever a mesma aula e gratis.
create table public.liberacoes (
  aluno_id    uuid not null references public.alunos(id) on delete cascade,
  tipo        text not null check (tipo in ('simulado','aula','ia')),
  item_id     text not null,
  liberado_em timestamptz not null default now(),
  primary key (aluno_id, tipo, item_id)
);

-- --------------------------------------------------------------- 3. CONTEUDO
create table public.cursos (
  id        text primary key,           -- 'cb', 'cg1', 'ct1', 'cfg'
  codigo    text,                       -- 'CNPI-CB'
  titulo    text not null,
  descricao text,
  ordem     int  default 0,
  ativo     boolean default true
);

create table public.modulos (
  id       uuid primary key default gen_random_uuid(),
  curso_id text not null references public.cursos(id) on delete cascade,
  titulo   text not null,
  ordem    int  default 0
);

create table public.aulas (
  id          uuid primary key default gen_random_uuid(),
  modulo_id   uuid not null references public.modulos(id) on delete cascade,
  titulo      text not null,
  video_id    text,                     -- id no servico de video (Panda/Mux/Stream)
  duracao_min int,
  material_url text,
  ordem       int default 0,
  ativo       boolean default true
);

create table public.progresso (
  aluno_id      uuid not null references public.alunos(id) on delete cascade,
  aula_id       uuid not null references public.aulas(id) on delete cascade,
  percentual    int  not null default 0 check (percentual between 0 and 100),
  atualizado_em timestamptz not null default now(),
  primary key (aluno_id, aula_id)
);

-- ------------------------------------------------------ 4. BANCO DE QUESTOES
create table public.categorias_questao (
  id    text primary key,
  nome  text not null,
  ativo boolean default true
);

create table public.questoes (
  id           uuid primary key default gen_random_uuid(),
  categoria_id text references public.categorias_questao(id),
  enunciado    text not null,
  comentario   text,                    -- gabarito comentado
  audio_url    text,                    -- gabarito em audio
  ativo        boolean default true,
  criada_em    timestamptz default now()
);

create table public.alternativas (
  id        uuid primary key default gen_random_uuid(),
  questao_id uuid not null references public.questoes(id) on delete cascade,
  texto     text not null,
  correta   boolean not null default false,
  ordem     int default 0
);

-- --------------------------------------------------------------- 5. SIMULADOS
create table public.simulados (
  id           text primary key,
  nome         text not null,
  descricao    text,
  tempo_limite int  default 60,         -- minutos
  corte        int  default 70,         -- % de acerto para aprovacao
  regra_acesso text default 'livre'
               check (regra_acesso in ('livre','cadastrados','assinantes')),
  ativo        boolean default true
);

-- Ao iniciar, sorteia N questoes ativas de cada categoria.
create table public.composicoes (
  simulado_id  text not null references public.simulados(id) on delete cascade,
  categoria_id text not null references public.categorias_questao(id),
  quantidade   int  not null check (quantidade > 0),
  ativo        boolean default true,
  primary key (simulado_id, categoria_id)
);

create table public.tentativas (
  id          uuid primary key default gen_random_uuid(),
  aluno_id    uuid not null references public.alunos(id) on delete cascade,
  simulado_id text not null references public.simulados(id),
  iniciada_em timestamptz not null default now(),
  enviada_em  timestamptz,
  acertos     int,
  total       int,
  nota        int
);
create index on public.tentativas (aluno_id, iniciada_em desc);

create table public.respostas (
  tentativa_id   uuid not null references public.tentativas(id) on delete cascade,
  questao_id     uuid not null references public.questoes(id),
  alternativa_id uuid references public.alternativas(id),
  correta        boolean,
  primary key (tentativa_id, questao_id)
);

-- --------------------------------------------------- 6. PLANOS E MATRICULAS
create table public.planos (
  id             text primary key,
  nome           text not null,
  preco_centavos int,
  validade_meses int default 12,
  ativo          boolean default true
);

create table public.plano_cursos (
  plano_id text not null references public.planos(id) on delete cascade,
  curso_id text not null references public.cursos(id) on delete cascade,
  primary key (plano_id, curso_id)
);

create table public.matriculas (
  id        uuid primary key default gen_random_uuid(),
  aluno_id  uuid not null references public.alunos(id) on delete cascade,
  plano_id  text not null references public.planos(id),
  ativa     boolean not null default true,
  inicia_em timestamptz not null default now(),
  expira_em timestamptz
);
create index on public.matriculas (aluno_id) where ativa;

create table public.pagamentos (
  id             uuid primary key default gen_random_uuid(),
  aluno_id       uuid references public.alunos(id),
  plano_id       text references public.planos(id),
  gateway        text,                  -- pagarme | asaas | iugu
  gateway_id     text unique,
  status         text,                  -- pendente | pago | recusado | estornado
  metodo         text,                  -- pix | boleto | cartao
  valor_centavos int,
  criado_em      timestamptz default now(),
  pago_em        timestamptz
);

-- Quem comprou tem acesso ao curso, independente de token.
create or replace function public.tem_acesso_curso(p_curso text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
      from public.matriculas m
      join public.plano_cursos pc on pc.plano_id = m.plano_id
     where m.aluno_id = auth.uid()
       and m.ativa
       and (m.expira_em is null or m.expira_em > now())
       and pc.curso_id = p_curso);
$$;

-- =========================================================== 7. GASTAR TOKEN
-- Debitar o saldo e liberar o conteudo tem que acontecer junto ou nao
-- acontecer. Sem isso, dois cliques rapidos gastam uma vez e liberam duas.
create or replace function public.gastar_token(p_tipo text, p_item_id text)
returns table (ok boolean, saldo int, motivo text)
language plpgsql security definer set search_path = public as $$
declare
  v_aluno uuid := auth.uid();
  v_cfg   public.config_tokens%rowtype;
  v_preco int;
  v_novo  int;
begin
  if v_aluno is null then
    return query select false, 0, 'sem-sessao'; return;
  end if;

  select * into v_cfg from public.config_tokens where id;

  -- tokens desligados no admin: tudo liberado
  if not v_cfg.ativo then
    return query select true, coalesce((select c.saldo from public.carteiras c
                                         where c.aluno_id = v_aluno), 0), 'desligado';
    return;
  end if;

  -- ja pagou por este item antes
  if exists (select 1 from public.liberacoes l
              where l.aluno_id = v_aluno and l.tipo = p_tipo and l.item_id = p_item_id) then
    return query select true, (select c.saldo from public.carteiras c
                                where c.aluno_id = v_aluno), 'ja-liberado';
    return;
  end if;

  v_preco := case p_tipo
               when 'simulado' then v_cfg.custo_simulado
               when 'aula'     then v_cfg.custo_aula
               when 'ia'       then v_cfg.custo_ia
               else 0
             end;

  if v_preco <= 0 then
    insert into public.liberacoes (aluno_id, tipo, item_id)
      values (v_aluno, p_tipo, p_item_id) on conflict do nothing;
    return query select true, (select c.saldo from public.carteiras c
                                where c.aluno_id = v_aluno), 'gratis';
    return;
  end if;

  -- o guard do UPDATE e o que garante a atomicidade
  update public.carteiras
     set saldo = saldo - v_preco
   where aluno_id = v_aluno and saldo >= v_preco
   returning saldo into v_novo;

  if v_novo is null then
    return query select false, coalesce((select c.saldo from public.carteiras c
                                          where c.aluno_id = v_aluno), 0), 'sem-saldo';
    return;
  end if;

  insert into public.liberacoes (aluno_id, tipo, item_id)
    values (v_aluno, p_tipo, p_item_id);
  insert into public.movimentos (aluno_id, quantidade, motivo, referencia)
    values (v_aluno, -v_preco, 'consumo:' || p_tipo, p_item_id);

  return query select true, v_novo, 'cobrado';
end $$;

-- Cortesia do comercial (pedido do Bruno na reuniao).
create or replace function public.dar_tokens(p_aluno uuid, p_qtd int, p_motivo text)
returns int language plpgsql security definer set search_path = public as $$
declare v_novo int;
begin
  if not public.eh_admin() then
    raise exception 'somente administradores';
  end if;
  update public.carteiras set saldo = saldo + p_qtd
   where aluno_id = p_aluno returning saldo into v_novo;
  insert into public.movimentos (aluno_id, quantidade, motivo)
    values (p_aluno, p_qtd, coalesce(p_motivo,'cortesia'));
  return v_novo;
end $$;

-- ================================================== 8. CADASTRO DO ALUNO
-- Conta nova nasce com a carteira cheia. Foi o bug que apareceu no
-- prototipo: a carteira era do navegador, nao da conta.
create or replace function public.ao_criar_usuario()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_ini int;
begin
  select inicial into v_ini from public.config_tokens where id;

  insert into public.alunos (id, nome, email, telefone, telefone_verificado_em)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'nome', split_part(coalesce(new.email,'aluno'),'@',1)),
          new.email,
          new.phone,
          new.phone_confirmed_at);

  insert into public.carteiras (aluno_id, saldo, base, competencia)
  values (new.id, v_ini, v_ini, to_char(now(),'YYYY-MM'));

  insert into public.movimentos (aluno_id, quantidade, motivo)
  values (new.id, v_ini, 'credito-inicial');

  return new;
end $$;

create trigger criar_aluno
  after insert on auth.users
  for each row execute function public.ao_criar_usuario();

-- ========================================================= 9. RLS (o portao)
alter table public.alunos             enable row level security;
alter table public.carteiras          enable row level security;
alter table public.movimentos         enable row level security;
alter table public.liberacoes         enable row level security;
alter table public.progresso          enable row level security;
alter table public.tentativas         enable row level security;
alter table public.respostas          enable row level security;
alter table public.matriculas         enable row level security;
alter table public.pagamentos         enable row level security;
alter table public.cursos             enable row level security;
alter table public.modulos            enable row level security;
alter table public.aulas              enable row level security;
alter table public.categorias_questao enable row level security;
alter table public.questoes           enable row level security;
alter table public.alternativas       enable row level security;
alter table public.simulados          enable row level security;
alter table public.composicoes        enable row level security;
alter table public.planos             enable row level security;
alter table public.plano_cursos       enable row level security;
alter table public.config_tokens      enable row level security;

-- --- o aluno enxerga o que e dele -------------------------------------------
create policy meu_cadastro   on public.alunos     for select using (id = auth.uid() or public.eh_admin());
create policy edito_meu_cad  on public.alunos     for update using (id = auth.uid());
create policy minha_carteira on public.carteiras  for select using (aluno_id = auth.uid() or public.eh_admin());
create policy meu_extrato    on public.movimentos for select using (aluno_id = auth.uid() or public.eh_admin());
create policy minhas_liber   on public.liberacoes for select using (aluno_id = auth.uid() or public.eh_admin());
create policy meu_progresso  on public.progresso  for all    using (aluno_id = auth.uid()) with check (aluno_id = auth.uid());
create policy minhas_tent    on public.tentativas for all    using (aluno_id = auth.uid() or public.eh_admin()) with check (aluno_id = auth.uid());
create policy minhas_resp    on public.respostas  for all
  using (exists (select 1 from public.tentativas t
                  where t.id = respostas.tentativa_id
                    and (t.aluno_id = auth.uid() or public.eh_admin())))
  with check (exists (select 1 from public.tentativas t
                       where t.id = respostas.tentativa_id and t.aluno_id = auth.uid()));
create policy minhas_matr    on public.matriculas for select using (aluno_id = auth.uid() or public.eh_admin());
create policy meus_pag       on public.pagamentos for select using (aluno_id = auth.uid() or public.eh_admin());

-- --- catalogo e publico; a AULA nao -----------------------------------------
create policy catalogo_cursos on public.cursos  for select using (ativo or public.eh_admin());
create policy catalogo_mod    on public.modulos for select using (true);
create policy catalogo_sim    on public.simulados for select using (ativo or public.eh_admin());
create policy catalogo_comp   on public.composicoes for select using (true);
create policy catalogo_planos on public.planos for select using (ativo or public.eh_admin());
create policy catalogo_pc     on public.plano_cursos for select using (true);
create policy catalogo_cat    on public.categorias_questao for select using (ativo or public.eh_admin());
create policy ler_config      on public.config_tokens for select using (true);

-- A aula so aparece para quem comprou o curso OU gastou token nela.
create policy aula_liberada on public.aulas for select using (
  public.eh_admin()
  or exists (select 1 from public.modulos m
              where m.id = aulas.modulo_id
                and public.tem_acesso_curso(m.curso_id))
  or exists (select 1 from public.liberacoes l
              where l.aluno_id = auth.uid()
                and l.tipo = 'aula'
                and l.item_id = aulas.id::text)
);

-- A questao so aparece para quem esta com uma tentativa aberta daquele
-- simulado, ou para quem comprou. E o que impede baixar o banco inteiro.
create policy questao_em_prova on public.questoes for select using (
  public.eh_admin()
  or exists (select 1 from public.respostas r
               join public.tentativas t on t.id = r.tentativa_id
              where r.questao_id = questoes.id and t.aluno_id = auth.uid())
);
create policy alt_em_prova on public.alternativas for select using (
  public.eh_admin()
  or exists (select 1 from public.questoes q where q.id = alternativas.questao_id)
);

-- --- escrita de conteudo: so admin ------------------------------------------
create policy admin_cursos  on public.cursos             for all using (public.eh_admin()) with check (public.eh_admin());
create policy admin_mod     on public.modulos            for all using (public.eh_admin()) with check (public.eh_admin());
create policy admin_aulas   on public.aulas              for all using (public.eh_admin()) with check (public.eh_admin());
create policy admin_cat     on public.categorias_questao for all using (public.eh_admin()) with check (public.eh_admin());
create policy admin_quest   on public.questoes           for all using (public.eh_admin()) with check (public.eh_admin());
create policy admin_alt     on public.alternativas       for all using (public.eh_admin()) with check (public.eh_admin());
create policy admin_sim     on public.simulados          for all using (public.eh_admin()) with check (public.eh_admin());
create policy admin_comp    on public.composicoes        for all using (public.eh_admin()) with check (public.eh_admin());
create policy admin_planos  on public.planos             for all using (public.eh_admin()) with check (public.eh_admin());
create policy admin_pc      on public.plano_cursos       for all using (public.eh_admin()) with check (public.eh_admin());
create policy admin_config  on public.config_tokens      for update using (public.eh_admin()) with check (public.eh_admin());
create policy admin_matr    on public.matriculas         for all using (public.eh_admin()) with check (public.eh_admin());

-- ============================================================================
-- Proximos passos (fora deste arquivo):
--   * 0002: seed dos cursos, categorias e simulados que hoje estao no admin
--   * Edge Function do webhook do gateway -> grava pagamento + matricula
--   * Auth: ligar provider de telefone (SMS/WhatsApp) para o codigo do cadastro
--   * Video: guardar so o video_id; streaming com URL assinada no Panda/Mux
-- ============================================================================
