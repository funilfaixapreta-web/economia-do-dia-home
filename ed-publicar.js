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

    /* Os planos sao o que se VENDE. Sem eles publicados, o carrinho nao tem
       preco e criar_pedido() recusa o pedido. O preco vem como texto no
       painel ("R$ 2.997") e vai para o banco em centavos. */
    var planos=(db.plans||[]).map(function(p){
      return {
        id:p.id, nome:p.name||'(sem nome)',
        preco_centavos:centavos(p.price),
        validade_meses:mesesDoPlano(p),
        ativo:true,
        cursos:cursosDoPlano(p)
      };
    });

    return {cursos:cursos, categorias:categorias, questoes:questoes,
            simulados:simulados, planos:planos};
  }

  /* "R$ 2.997" -> 299700 · "R$ 1.234,56" -> 123456 */
  function centavos(v){
    if(window.EDCarrinho&&EDCarrinho.paraCentavos)return EDCarrinho.paraCentavos(v);
    var s=String(v||'').replace(/[^\d.,]/g,'');
    if(!s)return 0;
    if(s.indexOf(',')>=0)s=s.replace(/\./g,'').replace(',','.');
    else s=s.replace(/\./g,'');
    var n=parseFloat(s);
    return isNaN(n)?0:Math.round(n*100);
  }
  /* "Acesso por 2 anos" -> 24 · "Acesso por 1 ano" -> 12 */
  function mesesDoPlano(p){
    var t=(p.benefits||[]).join(' ');
    var a=t.match(/(\d+)\s*anos?/i);   if(a)return parseInt(a[1],10)*12;
    var m=t.match(/(\d+)\s*mes(es)?/i); if(m)return parseInt(m[1],10);
    return 12;
  }
  /* Quais cursos o plano libera. Se o painel nao disser, deduz pelo texto do
     proprio plano ("CB + CG1 + CT1"), que e como os planos sao descritos. */
  function cursosDoPlano(p){
    if(Array.isArray(p.courses)&&p.courses.length)return p.courses.slice();
    var t=((p.benefits||[]).join(' ')+' '+(p.name||'')).toUpperCase();
    var mapa=[['CB','cb'],['CG1','cg1'],['CT1','ct1']];
    var ids=mapa.filter(function(x){
      return new RegExp('\\b'+x[0]+'\\b').test(t);
    }).map(function(x){return x[1];});
    if(!ids.length&&/VALUATION/.test(t))ids=['cg1'];
    return ids;
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
            simuladosCurtos:faltando,
            planos:p.planos.length,
            planosSemPreco:p.planos.filter(function(x){return !x.preco_centavos;}).length,
            planosSemCurso:p.planos.filter(function(x){return !x.cursos.length;})
                                   .map(function(x){return x.nome;})};
  }

  /* ------------------------------------------------------------ publicar */
  function publicar(){
    if(!window.EDApi||!EDApi.rpc)
      return Promise.reject(new Error('A ponte com o banco (ed-api.js) nao carregou.'));
    if(!EDApi.sessao())
      return Promise.reject(new Error('sem-sessao'));
    return publicarEmLotes(montarPacote(), arguments[0]);
  }

  /* Quantas questoes por chamada. O papel "authenticated" do Postgres tem
     statement_timeout de 8 segundos, e medindo no banco: 5.105 questoes numa
     chamada unica levam ~9s — ou seja, estouraria. Em lotes de 300 cada
     chamada fica na casa de meio segundo, com folga.
     Republicar e seguro (upsert por ref), entao um lote que falhe pode ser
     repetido sem duplicar nada. */
  var LOTE=300;

  function publicarEmLotes(pacote, aoProgredir){
    function avisar(feito,total){
      if(typeof aoProgredir==='function')try{aoProgredir(feito,total)}catch(_){}
    }
    var questoes=pacote.questoes||[];
    var total=questoes.length;

    /* 1a chamada: tudo menos as questoes. Cursos e categorias precisam existir
       antes, senao a composicao do simulado nao acha a categoria. */
    var primeiro=Object.assign({},pacote,{questoes:[]});

    return EDApi.rpc('publicar_conteudo',{p_dados:primeiro}).then(function(r){
      r.questoes=0; r.alternativas=0; r.questoes_sem_gabarito=0;
      r.refs_sem_gabarito=[];
      avisar(0,total);

      /* 2a em diante: as questoes, em lotes, uma chamada por vez */
      var i=0;
      function proximo(){
        if(i>=total)return r;
        var fatia=questoes.slice(i,i+LOTE);
        return EDApi.rpc('publicar_conteudo',{p_dados:{questoes:fatia}})
          .then(function(p){
            r.questoes      += (p.questoes||0);
            r.alternativas  += (p.alternativas||0);
            r.questoes_sem_gabarito += (p.questoes_sem_gabarito||0);
            if(p.refs_sem_gabarito&&p.refs_sem_gabarito.length)
              r.refs_sem_gabarito=r.refs_sem_gabarito.concat(p.refs_sem_gabarito);
            i+=LOTE; avisar(Math.min(i,total),total);
            return proximo();
          });
      }
      return proximo();
    }).then(function(r){
      return EDApi.rpc('publicar_planos',{p_planos:pacote.planos})
        .then(function(pl){r.planos=(pl&&pl.planos)||0;return r;})
        .catch(function(){return r;});
    });
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
