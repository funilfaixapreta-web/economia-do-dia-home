-- 0013 — tres correcoes encontradas na conferencia com o banco antigo
--
-- 1. telefone unico barrava cadastro e edicao de perfil
-- 2. questao com audio e sem regra entregava a gravacao paga para qualquer um
-- 3. os planos legados nao estavam ligados a nenhum curso, e os que ainda
--    estao a venda duplicavam os planos do painel sem entregar nada

-- 1 ---------------------------------------------------------------------
-- dois alunos podem compartilhar o mesmo telefone (casal, familia, celular
-- de trabalho). A unicidade rejeitou 5 alunos na importacao e faria
-- atualizar_meu_perfil estourar 23505 na cara do aluno.
alter table public.alunos drop constraint if exists alunos_telefone_key;
create index if not exists alunos_telefone_idx on public.alunos (telefone);

-- 2 ---------------------------------------------------------------------
-- quem tem gravacao tem regra; sem regra, gabarito_tentativa entrega o audio
-- a quem nao assina.
update public.questoes
   set audio_regra = 'Somente assinantes'
 where audio_regra is null
   and (audio_url is not null or audio_embed is not null);

create or replace function public.audio_sempre_com_regra() returns trigger
language plpgsql as $fn$
begin
  if (new.audio_url is not null or new.audio_embed is not null)
     and coalesce(btrim(new.audio_regra),'') = '' then
    new.audio_regra := 'Somente assinantes';
  end if;
  return new;
end $fn$;

drop trigger if exists audio_com_regra on public.questoes;
create trigger audio_com_regra
  before insert or update on public.questoes
  for each row execute function public.audio_sempre_com_regra();

revoke execute on function public.audio_sempre_com_regra() from public, anon, authenticated;

-- 3 ---------------------------------------------------------------------
-- os tres planos legados de CNPI dizem no nome quais cursos compraram.
-- Sem plano_cursos, tem_acesso_curso devolve false e o aluno que pagou
-- nao abre aula nenhuma.
insert into public.plano_cursos (plano_id, curso_id) values
  ('legacy-14','cb'), ('legacy-14','cg1'), ('legacy-14','ct1'),  -- CNPI - Curso Completo
  ('legacy-16','cb'), ('legacy-16','cg1'),                        -- CNPI - CB + CG
  ('legacy-15','cb'), ('legacy-15','ct1')                         -- CNPI - CB + CT
on conflict do nothing;

-- os mesmos planos continuavam a venda, com preco igual ao do painel e sem
-- curso ligado: quem comprasse pagava e nao recebia acesso. Desativar nao
-- corta o acesso de quem ja tem — tem_acesso_curso nao olha planos.ativo.
update public.planos set ativo = false
 where id in ('legacy-14','legacy-15','legacy-16','legacy-18');

-- 4 ---------------------------------------------------------------------
-- respostas.questao_id nao tinha indice. Hoje a tabela e pequena, mas ela
-- cresce uma linha por questao por tentativa: sem indice, cada exclusao de
-- questao no painel varre a tabela inteira.
create index if not exists respostas_questao_idx on public.respostas (questao_id);
