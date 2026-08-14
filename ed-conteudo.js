/* ============================================================================
   Economia do Dia · de onde a area do aluno tira o conteudo
   ----------------------------------------------------------------------------
   Ate aqui a area do aluno tinha os cursos escritos na mao dentro do app.html.
   Ou seja: o que o admin editava no painel nunca aparecia para o aluno, e o
   player nem tocava video — era um botao de play desenhado.

   Este arquivo resolve as duas coisas, em tres camadas, nesta ordem:

     1. BANCO      quando a ponte esta ligada, o catalogo vem do Postgres
                   (funcao catalogo()) e o video vem da ver_aula(), que so
                   entrega o link para quem tem o curso ou gastou o token
     2. PAINEL     senao, le o que o admin salvou no proprio navegador
                   (eda-db). E o que faz a demonstracao funcionar: edita no
                   painel, abre a area do aluno, esta la
     3. EXEMPLO    senao, os cursos de exemplo que ja existiam no app.html

   Nada aqui quebra se a camada de cima faltar: sempre cai para a de baixo.
   ============================================================================ */
(function(){

  var CACHE=null;           /* catalogo do banco, quando chega */
  var ouvintes=[];

  function ligado(){return !!(window.EDApi&&EDApi.ativo()&&EDApi.sessao());}

  /* --------------------------------------------------------- camada 2: painel
     Converte o formato do painel (adm.html) para o formato que a area do aluno
     ja usa: modules[].lessons[] com [id, titulo, duracao, progresso].        */
  function doPainel(){
    var db;
    try{db=JSON.parse(localStorage.getItem('eda-db')||'null');}catch(_){return null;}
    if(!db||!db.courses||!db.courses.length)return null;

    var out=db.courses.filter(function(c){return c.status!=='rascunho';}).map(function(c){
      return {
        id:c.id, code:c.code||c.cert||'CURSO', title:c.title||'',
        trilha:'cnpi', owned:false, color:c.color||'#D4A437',
        desc:c.desc||'',
        modules:(c.modules||[]).map(function(m){
          return {
            title:m.title||'',
            lessons:(m.lessons||[])
              .filter(function(l){return l.status!=='rascunho';})
              .map(function(l){return [l.id, l.title||'', +l.duration||0, 0];})
          };
        }).filter(function(m){return m.lessons.length;})
      };
    }).filter(function(c){return c.modules.length;});

    return out.length?out:null;
  }

  /* ---------------------------------------------------------- camada 1: banco
     Mesmo formato, vindo do catalogo(). O id da aula aqui e o uuid do banco,
     que e o que a ver_aula() espera.                                        */
  function doBanco(cat){
    if(!cat||!cat.cursos||!cat.cursos.length)return null;
    return cat.cursos.map(function(c){
      return {
        id:c.id, code:c.codigo||'CURSO', title:c.titulo||'',
        trilha:'cnpi', owned:false, color:c.cor||'#D4A437', desc:c.descricao||'',
        modules:(c.modulos||[]).map(function(m){
          return {title:m.titulo||'', lessons:(m.aulas||[]).map(function(a){
            return [a.id, a.titulo||'', +a.duracao_min||0, 0];
          })};
        }).filter(function(m){return m.lessons.length;})
      };
    });
  }

  /* Chamado uma vez pelo app.html, de forma sincrona. Devolve o melhor que
     der AGORA; se o banco estiver ligado, busca em segundo plano e avisa. */
  function cursos(exemplo){
    if(ligado())buscarDoBanco();
    return doPainel()||exemplo||[];
  }

  function buscarDoBanco(){
    if(CACHE||!ligado())return;
    EDApi.rpc('catalogo').then(function(cat){
      CACHE=cat;
      var lista=doBanco(cat);
      if(lista&&lista.length)ouvintes.forEach(function(f){try{f(lista)}catch(_){}});
    }).catch(function(){/* sem banco, segue com o painel */});
  }

  function aoChegar(f){if(typeof f==='function')ouvintes.push(f);}

  /* ------------------------------------------------------------------ video
     Devolve {ok, video_url, video_embed, video_id} da aula.
     No banco, quem decide se pode ver e a ver_aula(). No painel, o video ja
     esta no proprio registro — a cobranca do token acontece antes, na tela. */
  function aula(cursoId, aulaId){
    if(ligado()&&/^[0-9a-f-]{36}$/i.test(String(aulaId)))
      return EDApi.rpc('ver_aula',{p_aula:aulaId});

    var db;
    try{db=JSON.parse(localStorage.getItem('eda-db')||'null');}catch(_){db=null;}
    var achada=null;
    if(db&&db.courses)db.courses.forEach(function(c){
      if(c.id!==cursoId)return;
      (c.modules||[]).forEach(function(m){
        (m.lessons||[]).forEach(function(l){if(l.id===aulaId)achada=l;});
      });
    });
    if(!achada)return Promise.resolve({ok:false,motivo:'aula-nao-encontrada'});
    return Promise.resolve({ok:true, titulo:achada.title,
      video_url:achada.videoUrl||null, video_embed:achada.videoEmbed||null,
      video_id:achada.video&&achada.video.name||null});
  }

  /* Link de video -> endereco que da para por num iframe. */
  function embutir(u){
    u=String(u||'');
    var y=u.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/)([\w-]{6,})/);
    if(y)return 'https://www.youtube.com/embed/'+y[1];
    var v=u.match(/vimeo\.com\/(?:video\/)?(\d+)/);
    if(v)return 'https://player.vimeo.com/video/'+v[1];
    return null;
  }

  window.EDConteudo={
    cursos:cursos, aula:aula, aoChegar:aoChegar, embutir:embutir,
    doBanco:function(){return CACHE;}, ligado:ligado
  };
})();
