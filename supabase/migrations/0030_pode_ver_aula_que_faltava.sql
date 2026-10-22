-- 0030 — URGENTE: repor pode_ver_aula(), que a 0029 passou a chamar
--
-- Erro meu, e desta vez com o aluno no meio. A 0029 reescreveu ver_aula()
-- chamando public.pode_ver_aula(), funcao que eu tinha escrito numa migracao
-- ANTERIOR que deu timeout e nao aplicou nada. Eu sabia que ela nao tinha
-- aplicado -- tinha conferido e dito isso -- e mesmo assim deixei a chamada
-- no corpo novo.
--
-- Entre a 0029 e esta, toda aula aberta por aluno estourava "function
-- public.pode_ver_aula(uuid) does not exist". O erro acontece em tempo de
-- EXECUCAO no plpgsql, nao na criacao da funcao -- por isso a 0029 foi aceita
-- sem reclamar e a quebra so apareceria no uso.
--
-- Licao, para a proxima: funcao que chama funcao exige conferir que a
-- chamada existe ANTES de aplicar, nao depois.

create or replace function public.pode_ver_aula(p_aula uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.eh_admin()
      or exists (select 1 from public.aulas a
                   join public.modulos m on m.id = a.modulo_id
                  where a.id = p_aula and a.ativo
                    and public.tem_acesso_curso(m.curso_id))
      or exists (select 1 from public.liberacoes l
                  where l.aluno_id = auth.uid()
                    and l.tipo = 'aula' and l.item_id = p_aula::text);
$$;

revoke execute on function public.pode_ver_aula(uuid) from public, anon;
grant  execute on function public.pode_ver_aula(uuid) to authenticated;

-- Conferido logo depois, com aula real:
--   admin ..................... ok=true, com o embed do VEED
--   aluno sem o curso ......... motivo=sem-acesso, sem estourar
--   anon ...................... barrado, 42501
