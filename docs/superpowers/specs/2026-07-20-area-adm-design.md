# Área do Adm — Economia do Dia (spec de design)

**Data:** 2026-07-20
**Autor:** definido com a Kamilly (produto) via brainstorming

## Contexto

A plataforma Economia do Dia é um **site estático puro** (HTML/CSS/JS inline, sem build), com três superfícies:

| Superfície | Arquivo | Público |
|---|---|---|
| Site (landing) | `index.html` | lead/público |
| Área do aluno | `app.html` | aluno logado |
| **Área do adm** | `adm.html` *(novo)* | administrador |

Hoje o conteúdo do site (cursos, aulas, áudios, simulados, questões) é **100% mock** — arrays fixos no JS do `app.html`, sem backend. O objetivo desta entrega é criar um **painel administrativo em protótipo** onde o admin "gerencia tudo": sobe vídeos, áudios, cria simulados etc.

## Decisões (definidas com o usuário)

1. **Arquitetura:** protótipo mock, sem servidor. Dados no `localStorage`; uploads viram preview na sessão. Entra no ar estático na Vercel.
2. **Escopo v1:** gerenciar **tudo** — cursos/módulos/aulas (com vídeo + áudio), simulados/questões, trilhas, alunos/planos, além de uma visão geral.
3. **Integração:** painel **standalone** — NÃO altera `app.html`. O adm tem seus próprios dados (semeados com o conteúdo atual). Mudanças no admin não precisam refletir na área do aluno.
4. **Acesso:** `/adm.html` abre uma **tela de login mock** (email/senha fictícios, botão "Entrar" passa direto) → painel. Link discreto "Área do administrador" no rodapé do `login.html`. Landing pública fica limpa, sem pista de admin.

## Design system (preservar)

Mesmo do resto do site: fontes Sora (títulos) / Inter (texto) / IBM Plex Mono (dados); dourado `#D4A437`/`#E6BE54` sobre `#08090C`; tema claro/escuro via `data-theme` + `localStorage`. SPA com hash router `#/rota` (mesmo padrão do `app.html`). Selo **ADMIN** no topo.

## Estrutura do painel

Sidebar à esquerda + top bar (título da seção, busca, toggle de tema, "Ver site", "Ver como aluno", avatar admin, sair).

- **Visão geral** — contadores (cursos, aulas, simulados, questões, alunos), atividade recente, ações rápidas.
- **Cursos** — lista → curso → módulos → **aula**: título, descrição, duração, upload de vídeo, upload de áudio (gabarito), status (rascunho/publicado), ordem ↑↓.
- **Simulados** — lista → simulado → **questões**: enunciado, alternativas A–E, correta, comentário, tema, dificuldade.
- **Trilhas** — nome, eyebrow, cor, ícone, descrição, cursos incluídos.
- **Alunos & Planos** — lista de alunos (plano, progresso, status); edição de planos (preço, benefícios).

Padrões de interação: CRUD com criar/editar/excluir; busca e filtros nas listas; formulário em **drawer** lateral; **toasts** de confirmação (padrão do `app.html`); reordenação por setas ↑↓; toggle publicado/rascunho; botão "Restaurar dados de exemplo".

## Uploads e persistência

- **Upload:** arrastar-soltar ou escolher arquivo → **preview real** (player de vídeo, player de áudio, thumb de imagem) via object URL.
- **Persistência:** estrutura/textos/questões/planos salvos em `localStorage` (namespace próprio do adm, ex.: `eda-*`), semeado com o conteúdo atual.
- **Limite assumido:** arquivos grandes (vídeo/áudio) **não sobrevivem ao reload** — persiste só o registro da aula (nome, tamanho, duração); reanexar após recarregar. Imagens pequenas (thumbs) persistem como dataURL.

## Não-objetivos (YAGNI)

Autenticação/segurança real, hospedagem real de arquivos, editor de texto rico, permissões multiusuário, analytics avançado. Não tocar em `index.html`/`app.html` (exceto link discreto no `login.html`).

## Modelo de dados (admin, defaults semeados)

- `courses`: `{id, code, title, cert, color, status, modules:[{title, lessons:[{id, title, duration, desc, video:{name,size,type}, audio:{name,size,type}, status}]}]}`
- `simulados`: `{id, cert, title, module, questions:[{id, stmt, options:[...], correct, comment, theme, difficulty}]}`
- `trilhas`: `{id, eye, name, color, ico, desc, courses:[...]}`
- `students`: `{id, name, email, plan, progress, status}`
- `plans`: `{id, name, price, benefits:[...]}`

## Arquivos

- **Novo:** `adm.html` (painel completo, CSS/JS inline; inclui tela de login mock e todas as telas do SPA).
- **Editado (mínimo):** `login.html` (link discreto "Área do administrador").
- **Intocados:** `index.html`, `app.html`.

## Deploy

Estático na Vercel (deploy a partir da branch `main`). Enquanto não publicado, roda local em `http://localhost:4322/adm.html`.
