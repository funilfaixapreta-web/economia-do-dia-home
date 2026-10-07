# As 31 tabelas do sistema antigo: 17 vieram, 14 não

Levantado em 07/10/2026 pelo `information_schema.TABLES` do phpMyAdmin. A
contagem de linhas é `TABLE_ROWS`, que no MySQL é **estimativa** — serve para
dimensionar, não para conferir importação.

Eu vinha dizendo que eram 32 tabelas e 15 de fora. São **31 e 14**. Das
tabelas de framework do Laravel só existem `migrations` e `password_resets`:
não há `sessions`, `failed_jobs` nem `personal_access_tokens`.

## As 17 que vieram

| Antiga | Linhas | Virou |
|---|---|---|
| `user` | 55.521 | `alunos` + `auth.users` (66.014) |
| `quiz_user` | 93.320 | `tentativas` (91.242) |
| `user_quiz_category` | 50.079 | `trilhas_do_aluno` (50.433) |
| `question` | 5.120 | `questoes` |
| `question_answer` | 19.977 | `alternativas` |
| `question_audio` | 5.615 | áudio das questões |
| `question_category` | 90 | `categorias` |
| `quiz_question_category` | 113 | `composicoes` |
| `quiz` | 54 | `simulados` |
| `quiz_category` | 8 | `categorias_simulado` |
| `module` | 7 | `modulos` |
| `plan` | 18 | `planos` |
| `subscription` | 1.330 | `matriculas` |
| `subscription_log` | 2.501 | `matriculas_historico` (2.625) |
| `page` | 101 | `paginas` |
| `tag` | 17 | `tags` |
| `image` | 161 | `imagens` + Storage (164 arquivos, 22 MB) |

Onde o número do novo é maior que o do antigo, é porque `TABLE_ROWS` é
estimativa e o export trouxe a contagem exata.

## As 14 que não vieram

Duas delas desmentem coisas que eu afirmei mais de uma vez. Começo por essas.

### 1. `quiz_user_question_answer` — 1.925.677 linhas

**Isto contradiz o que eu disse.** Eu afirmei, duas vezes, que "o sistema
antigo não guarda acertos, só percentual", e por causa disso deixei
`tentativas.acertos` e `tentativas.total` **nulos nas 91.242 provas
importadas**. Também documentei que o índice de erro por categoria do painel
não cobriria as provas históricas.

Esse detalhe existe: são quase 2 milhões de linhas com a resposta de cada
aluno em cada questão de cada prova. Com ela dá para:

- preencher `acertos` e `total` das 91.242 provas, em vez de deixar nulo;
- ter índice de erro por questão e por categoria com histórico de verdade,
  e não só com as provas feitas no sistema novo;
- saber quais questões mais derrubam aluno — que é o dado que decide onde
  gravar conteúdo novo.

O que eu disse estava errado sobre a *existência* do dado. O que continua
certo é que ele não estava em nenhum dos três arquivos que você exportou, e
que eu não tinha como adivinhar uma tabela que não aparecia na lista.

Não é obrigatório para a virada. É o maior ganho de qualidade disponível, e
1,9 milhão de linhas cabe em CSV fatiado por faixa de `id`.

### 2. `postback` — 4.128 linhas

**Isto também contradiz o que eu disse.** Eu construí a tela de Assinaturas
inteira sobre a premissa de que "o sistema antigo não guardava registro de
pagamento". É por isso que a tela não tem lista de inadimplência, e que todo
valor aparece marcado como "preço de tabela" em vez de valor pago.

`postback` são as respostas do gateway de pagamento — quase sempre é ali que
mora o valor realmente pago, a data, o meio de pagamento e a recusa. Se for
isso, dá para:

- mostrar receita real em vez de preço de tabela;
- montar lista de inadimplência de verdade (cobrança recusada, não só
  matrícula vencida);
- casar venda com assinatura e ver taxa de recusa por plano.

Antes de prometer qualquer uma dessas, preciso ver a estrutura: "postback"
pode ser um log cru de JSON sem nada aproveitável. Por isso ela está na
lista de leituras abaixo, e não num plano.

### 3. As outras 12

| Tabela | Linhas | O que é | Por que ficou fora |
|---|---|---|---|
| `access_log` | 630.414 | log de acesso por página | histórico de navegação; não muda o produto |
| `email_recipient` | 12.162 | destinatários de e-mail enviado | histórico de disparo |
| `email` | 3.532 | e-mails enviados | histórico de disparo |
| `password_resets` | 820 | tokens de troca de senha | lixo de framework; os tokens não valem no GoTrue |
| `taggables` | 124 | liga tag ↔ conteúdo | **as tags vieram, o vínculo não.** As 17 tags estão no novo sem nada pendurado |
| `menu` | 62 | menu do site antigo | o site novo tem menu próprio |
| `imageables` | 49 | liga imagem ↔ conteúdo | as 164 imagens vieram; este vínculo não |
| `setting` | 21 | configurações do site antigo | pode ter texto de rodapé, pixel, chave de gateway — vale uma olhada |
| `access_rule` | 3 | regras de acesso | 3 linhas; provavelmente já está refletido em `regra_acesso` |
| `migrations` | 3 | controle do Laravel | framework |
| `plan_category` | 0 | vazia | nada a trazer |
| `table_template` | 0 | vazia | nada a trazer |

`taggables` e `imageables` são pequenas e consertam uma coisa meio torta: hoje
as tags e as imagens existem no banco novo soltas, sem saber a que página
pertencem.

## A próxima leitura

Está em `migracao/exports-que-faltam.sql`, na parte 2. São sete consultas de
estrutura (`SHOW CREATE TABLE`, uma linha de resposta cada) mais um registro
de aluno. Com a estrutura na mão eu digo quais dessas 14 valem a pena e quais
são lixo de framework — sem isso, qualquer plano meu é chute.
