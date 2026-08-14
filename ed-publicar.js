/* ============================================================================
   Economia do Dia · publicacao do conteudo no banco
   ----------------------------------------------------------------------------
   O painel guarda tudo no navegador (localStorage). Isso e otimo para editar,
   mas nao chega ao aluno: o material so existe na maquina de quem editou.

   Este arquivo faz a ponte. Ele le o que esta no painel, monta um pacote unico
   e manda para a funcao publicar_conteudo() do Postgres, que grava tudo de uma
   vez so — cursos, modulos, aulas (video por upload, por LINK ou por embed),
   categorias, questoes com suas alternativas, simulados e a composicao de cada
   simulado.

   Republicar e seguro. Cada item leva um "ref" fixo e o banco casa por ele:
   o que ja existe e atualizado no lugar, nada duplica.

   Depende de: EDApi (ed-api.js) e das variaveis do painel (db, save, toast).
   ============================================================================ */
(function(){

  /* --------------------------------------------------------------- helpers */
  function txt(v){v=(v==null?'':String(v)).trim();return v||null;}
  function num(v){var n=parseInt(v,10);return isNaN(n)?null:n;}
  function bool(v){return v!==false&&v!=='nao'&&v!=='rascunho';}

  /* O painel nao guarda id de modulo (so o titulo). Sem uma chave fixa, mudar
     o nome do modulo criaria um modulo novo no banco a cada publicacao. Entao
     na primeira publicacao a gente carimba um ref e salva de volta. */
  function garantirRefs(){
    var mexeu=false;
    (db.courses||[]).forEach(function(c){
      (c.modules||[]).forEach(function(m){
        if(!m.ref){m.ref=(c.id||'curso')+'::'+uid('m');mexeu=true;}
        (m.lessons||[]).forEach(function(l){
          if(!l.id){l.id=uid('l');mexeu=true;}
        });
      });
    });
    (db.questions||[]).forEach(function(q){
      if(!q.id){q.id=uid('q');mexeu=true;}
    });
    if(mexeu&&typeof save==='function')save();
    return mexeu;
  }

  /* ------------------------------------------------------------ o pacote */
  function montarPacote(){
    garantirRefs();

    var cursos=(db.courses||[]).map(function(c,ci){
      return {
        id:c.id, codigo:txt(c.code||c.cert), titulo:c.title||'(sem titulo)',
        descricao:txt(c.desc), cor:txt(c.color), ordem:ci,
        /* curso em rascunho entra no banco desativado: fica pronto, mas
           invisivel para o aluno ate ser publicado no painel */
        ativo:c.status!=='rascunho',
        modulos:(c.modules||[]).map(function(m,mi){
          return {
            ref:m.ref, titulo:m.title||'(sem titulo)', ordem:mi,
            aulas:(m.lessons||[]).map(function(l,li){
              return {
                ref:l.id, titulo:l.title||'(sem titulo)', descricao:txt(l.desc),
                duracao_min:num(l.duration),
                /* as tres formas de por video, na ordem em que o painel manda */
                video_url:txt(l.videoUrl),
                video_embed:txt(l.videoEmbed),
                video_id:l.video&&l.video.name?txt(l.video.name):null,
                material_url:txt(l.materialUrl),
                ordem:li, ativo:l.status!=='rascunho'
              };
            })
          };
        })
      };
    });

    var categorias=(db.qCategories||[]).map(function(k){
      return {id:k.id, nome:k.name||'(sem nome)', ativo:bool(k.active)};
    });

    var questoes=(db.questions||[]).map(function(q){
      return {
        ref:q.id, categoria_id:txt(q.categoryId),
        enunciado:q.text||'(sem enunciado)', comentario:txt(q.comment),
        audio_embed:txt(q.audioEmbed), regra_acesso:txt(q.accessRule)||'livre',
        ativo:bool(q.active),
        alternativas:(q.answers||[]).map(function(a){
          return {texto:a.text||'', correta:!!a.correct, ativo:bool(a.active)};
        })
      };
    });

    var simulados=(db.simulados||[]).map(function(s){
      return {
        id:s.id, nome:s.name||'(sem nome)', slug:txt(s.friendly_url),
        descricao:txt(s.description), tempo_limite:num(s.time_limit),
        corte:num(s.hit_percentage), regra_acesso:txt(s.access_rule_id)||'livre',
        ativo:bool(s.is_active),
        composicao:(s.composition||[]).map(function(x){
          return {categoria_id:x.question_category_id,
                  quantidade:num(x.questions_quantity)||0,
                  ativo:bool(x.is_active)};
        })
      };
    });

    return {cursos:cursos, categorias:categorias, questoes:questoes,
            simulados:simulados};
  }

  /* Numeros que o painel mostra antes de publicar, para o admin conferir. */
  function resumo(){
    var p=montarPacote(), mods=0, aulas=0, comLink=0, semVideo=0, alts=0;
    p.cursos.forEach(function(c){
      mods+=c.modulos.length;
      c.modulos.forEach(function(m){
        aulas+=m.aulas.length;
        m.aulas.forEach(function(a){
          if(a.video_url||a.video_embed)comLink++;
          else if(!a.video_id)semVideo++;
        });
      });
    });
    p.questoes.forEach(function(q){alts+=q.alternativas.length;});

    /* Quantas questoes ATIVAS existem por categoria. Um simulado que pede mais
       do que existe no banco de questoes sobe, mas cai numa prova curta. */
    var porCat={};
    p.questoes.forEach(function(q){
      if(q.ativo&&q.categoria_id)porCat[q.categoria_id]=(porCat[q.categoria_id]||0)+1;
    });
    var faltando=[];
    p.simulados.forEach(function(s){
      var pede=0, tem=0;
      (s.composicao||[]).forEach(function(x){
        if(!x.ativo)return;
        pede+=x.quantidade;
        tem+=Math.min(x.quantidade, porCat[x.categoria_id]||0);
      });
      if(pede>tem)faltando.push({nome:s.nome, pede:pede, tem:tem});
    });

    return {cursos:p.cursos.length, modulos:mods, aulas:aulas,
            aulasComLink:comLink, aulasSemVideo:semVideo,
            categorias:p.categorias.length, questoes:p.questoes.length,
            alternativas:alts, simulados:p.simulados.length,
            simuladosCurtos:faltando};
  }

  /* ------------------------------------------------------------ publicar */
  function publicar(){
    if(!window.EDApi||!EDApi.rpc)
      return Promise.reject(new Error('A ponte com o banco (ed-api.js) nao carregou.'));
    if(!EDApi.sessao())
      return Promise.reject(new Error('sem-sessao'));
    return EDApi.rpc('publicar_conteudo',{p_dados:montarPacote()});
  }

  /* Entrar com a conta de admin do banco (o login do painel e so do prototipo,
     nao vale no Postgres). */
  function entrar(email,senha){
    if(!window.EDApi)return Promise.reject(new Error('ed-api.js nao carregou.'));
    return EDApi.entrar({email:email,senha:senha});
  }

  function conta(){
    var s=EDApi&&EDApi.sessao&&EDApi.sessao();
    return s&&s.user?(s.user.email||''):'';
  }

  window.EDPublicar={
    resumo:resumo, pacote:montarPacote, publicar:publicar,
    entrar:entrar, conta:conta,
    sair:function(){return EDApi.sair();}
  };

  /* este arquivo carrega depois do painel. Se a tela Sistema ja estiver
     aberta, ela foi desenhada sem o bloco de publicacao: redesenha. */
  if(typeof repintaPublicar==='function')try{repintaPublicar()}catch(_){}
})();
