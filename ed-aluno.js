/* ============================================================================
   Economia do Dia · o desempenho que a area do aluno mostra
   ----------------------------------------------------------------------------
   Antes deste arquivo, o app.html tinha as notas escritas na mao: um aluno
   de verdade abria "Simulados" e via 84%, 58% e 76%; a tela inicial dizia
   "voce esta 78% pronto", "14 de sequencia", "42h estudadas"; e a revisao de
   erros montava a questao, a alternativa que o aluno "marcou" e o comentario
   a partir de um banco fixo no arquivo (QBANK). Nada disso era dele.

   Num produto de certificacao isso passa de enfeite a problema: a pessoa
   estuda para uma prova real, e uma questao inventada com gabarito inventado
   ensina errado.

   Aqui o desempenho vem de meu_desempenho(), que le auth.uid() no banco e
   nao aceita parametro de aluno -- nao existe como pedir o de outra pessoa.

   O QUE O BANCO SABE E O QUE NAO SABE
   O sistema antigo guardava, por prova, apenas o percentual de acerto
   (quiz_user.hit_percentage). Entao das 91.242 provas importadas nao existe
   resposta por questao: nem quais o aluno errou, nem quantas acertou.
   Por isso 'com_detalhe' vem no resumo e precisa ser respeitado: so as
   provas feitas no sistema NOVO podem abrir a revisao questao por questao.
   Para as outras a tela diz que o detalhe nao existe -- e nao inventa um.

   (Esse detalhe existe no sistema antigo, em quiz_user_question_answer, 1,9
   milhao de linhas que nunca foram exportadas. Se um dia vierem, esta camada
   nao muda: por_categoria e com_detalhe passam a vir preenchidos sozinhos.)
   ============================================================================ */
(function(){

  var DADOS=null, BUSCANDO=false, ouvintes=[];

  function ligado(){
    return !!(window.EDApi && EDApi.ativo() && EDApi.sessao());
  }

  function avisar(){
    ouvintes.forEach(function(f){try{f(DADOS)}catch(_){}});
  }

  /* Busca uma vez por carregamento de pagina. Falha nao quebra tela nenhuma:
     DADOS fica null e quem pergunta recebe null, que e o sinal de "nao sei".
     "Nao sei" tem de aparecer como travessao, nunca como zero -- zero e uma
     afirmacao (voce fez 0 provas) e pode ser mentira. */
  function buscar(){
    if(DADOS||BUSCANDO||!ligado())return;
    BUSCANDO=true;
    EDApi.rpc('meu_desempenho').then(function(d){
      BUSCANDO=false;
      if(d&&typeof d==='object'){DADOS=d;avisar();}
    }).catch(function(){BUSCANDO=false;});
  }

  function dados(){return DADOS;}
  function resumo(){return DADOS&&DADOS.resumo||null;}

  /* Ultima nota do aluno naquele simulado, ou null se ele nunca fez. */
  function notaDe(simId){
    if(!DADOS||!DADOS.por_simulado)return null;
    var l=DADOS.por_simulado;
    for(var i=0;i<l.length;i++) if(l[i].simulado_id===simId) return l[i];
    return null;
  }

  /* As provas que PODEM ser revisadas questao por questao. Sao as que o aluno
     fez no sistema novo; o historico do antigo nao tem esse detalhe. */
  function revisaveis(){
    if(!DADOS||!DADOS.ultimas)return [];
    return DADOS.ultimas.filter(function(t){return t.origem!=='legado';});
  }

  function temDetalhe(){
    var r=resumo();
    return !!(r&&r.com_detalhe>0);
  }

  /* Materias ordenadas por erro, so quando ha base para isso. Lista vazia
     significa "o banco nao tem como saber", e a tela precisa dizer isso em
     vez de mostrar uma materia qualquer como ponto fraco. */
  function porCategoria(){
    return (DADOS&&DADOS.por_categoria)||[];
  }

  function trilhas(){return (DADOS&&DADOS.trilhas)||[];}
  function ultimas(){return (DADOS&&DADOS.ultimas)||[];}

  function aoChegar(f){
    if(typeof f!=='function')return;
    ouvintes.push(f);
    if(DADOS)try{f(DADOS)}catch(_){}
  }

  /* ------------------------------------------------------------------ texto
     Formatacoes que varias telas repetiam, cada uma do seu jeito.          */
  function horas(seg){
    seg=+seg||0;
    if(!seg)return null;
    var h=Math.floor(seg/3600), m=Math.round((seg%3600)/60);
    if(h&&m)return h+'h'+(m<10?'0':'')+m;
    if(h)return h+'h';
    return m+' min';
  }

  function quando(iso){
    if(!iso)return '';
    var d=new Date(iso); if(isNaN(d))return '';
    var hoje=new Date(), um=86400000;
    var dia=function(x){return new Date(x.getFullYear(),x.getMonth(),x.getDate()).getTime();};
    var dif=Math.round((dia(hoje)-dia(d))/um);
    if(dif===0)return 'hoje';
    if(dif===1)return 'ontem';
    if(dif<30)return 'há '+dif+' dias';
    return d.toLocaleDateString('pt-BR',{day:'2-digit',month:'short',year:
      d.getFullYear()===hoje.getFullYear()?undefined:'numeric'});
  }

  window.EDAluno={
    ligado:ligado, buscar:buscar, aoChegar:aoChegar,
    dados:dados, resumo:resumo, notaDe:notaDe, porCategoria:porCategoria,
    trilhas:trilhas, ultimas:ultimas, revisaveis:revisaveis,
    temDetalhe:temDetalhe, horas:horas, quando:quando
  };
})();
