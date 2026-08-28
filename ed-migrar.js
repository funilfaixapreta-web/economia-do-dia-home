/* ============================================================================
   Economia do Dia · importar o banco de questoes do sistema antigo
   ----------------------------------------------------------------------------
   O site velho (economiadodia.com.br/admin) exporta o banco em JSON. Sao 5.105
   questoes espalhadas por 83 categorias. O importador de CSV que ja existia no
   painel nao serve aqui: ele joga tudo numa categoria so, e teria que ser
   repetido 83 vezes.

   Este arquivo le o JSON do jeito que ele sai de la e monta as categorias e as
   questoes de uma vez. Depois disso, o botao "Publicar no banco" (que ja manda
   em lotes de 300) leva tudo para o Supabase.

   O ref de cada questao vira "legacy-<id antigo>", entao:
     - reimportar nao duplica nada, atualiza no lugar
     - da para rastrear qualquer questao ate o sistema de origem
   ============================================================================ */
(function(){

  /* "CPA-20: Fundos de Investimento" -> "cpa-20-fundos-de-investimento" */
  function slug(s){
    return String(s||'')
      .normalize('NFD').replace(/[\u0300-\u036f]/g,'')   /* tira acento */
      .toLowerCase()
      .replace(/[^a-z0-9]+/g,'-')
      .replace(/^-+|-+$/g,'')
      .slice(0,80) || 'sem-categoria';
  }

  /* O enunciado vem as vezes como HTML. O painel mostra texto puro. */
  function texto(s){
    var d=document.createElement('div');
    d.innerHTML=String(s||'');
    return (d.textContent||'').replace(/\s+/g,' ').trim();
  }

  function verdade(v){
    if(typeof v==='boolean')return v;
    var s=String(v==null?'':v).trim().toLowerCase();
    return s==='1'||s==='sim'||s==='true'||s==='s';
  }

  /* ------------------------------------------------------------------ ler */
  /* Aceita os dois formatos que o site antigo produz:
       {questoes:[...]}                    · com "categoria" pelo nome
       {categorias:[...], questoes:[...]}  · com categoria_id tambem       */
  function analisar(texto_json){
    var d;
    try{ d=JSON.parse(texto_json); }
    catch(e){ return {erro:'Arquivo não é um JSON válido: '+e.message}; }

    var lista = Array.isArray(d) ? d : (d.questoes||d.questions||null);
    if(!lista||!lista.length) return {erro:'Não encontrei a lista de questões neste arquivo.'};

    var cats={}, questoes=[], semGabarito=[], semEnunciado=0;

    lista.forEach(function(q){
      var nomeCat = q.categoria || q.categoria_nome || q.category || '';
      /* alguns exports ja trazem o slug pronto; usar o de la mantem o mesmo
         identificador que o resto da migracao usou */
      var idCat   = q.slug_categoria || q.categoria_slug || slug(nomeCat);
      if(!cats[idCat]) cats[idCat]={id:idCat, name:nomeCat||'Sem categoria', desc:'', active:true};

      var alts=(q.alternativas||q.answers||q.opcoes||[])
        .slice()
        .sort(function(a,b){return (+a.ordem||0)-(+b.ordem||0);})
        .map(function(a){
          return {text:texto(a.texto||a.text||''), correct:verdade(a.correta||a.correct)};
        })
        .filter(function(a){return a.text;});

      /* o export mais completo traz enunciado_texto e enunciado_html; os mais
         simples trazem so "enunciado". Preferimos o texto ja limpo. */
      var enun=texto(q.enunciado_texto||q.enunciado||q.enunciado_html
                     ||q.text||q.pergunta||'');
      if(!enun)semEnunciado++;

      var corretas=alts.filter(function(a){return a.correct;}).length;
      /* se o arquivo ja traz o ref, respeita: e ele que casa com o que
         porventura ja foi carregado antes */
      var ref=q.ref||('legacy-'+(q.id!=null?q.id:(questoes.length+1)));
      if(alts.length<2||corretas!==1)semGabarito.push(ref);

      questoes.push({
        id:ref,                                   /* vira o ref no banco */
        categoryId:idCat,
        text:enun||'(sem enunciado)',
        comment:texto(q.comentario||q.explicacao||q.comment||''),
        /* o audio do gabarito comentado do site antigo */
        audioUrl:(q.audio_url||q.audio_src||q.audio||'')||'',
        audioEmbed:(q.audio_embed||'')||'',
        /* a regra do audio governa o gabarito comentado, NAO quem pode
           responder a questao: sao coisas diferentes */
        audioRegra:(q.audio_regra||'')||'',
        accessRule:/assinante/i.test(q.regra_acesso||'')?'assinantes':'livre',
        active:verdade(q.ativo==null?true:q.ativo),
        answers:alts.map(function(a,i){
          return {id:'a'+(i+1), text:a.text, correct:a.correct, active:true};
        })
      });
    });

    var listaCats=Object.keys(cats).map(function(k){return cats[k];})
                        .sort(function(a,b){return a.name.localeCompare(b.name,'pt-BR');});

    /* ------------------------------------------------------------ provas */
    /* O export do site antigo pode trazer os simulados junto. Ate aqui eles
       eram ignorados calados: o arquivo tinha 54 provas e so as questoes
       entravam, entao a aba Simulados continuava com os exemplos.

       Um simulado do sistema antigo e: os dados da prova + a composicao, que
       diz de quais categorias sortear e quantas questoes de cada. Sem a
       composicao a prova nao existe, entao ela e o que mais importa trazer. */
    var provas=[], catsSim={};
    (d.simulados||d.provas||d.quizzes||[]).forEach(function(p){
      var nome=texto(p.nome||p.name||p.titulo||'');
      var idSim=p.id!=null?('legacy-sim-'+p.id):(p.slug||p.friendly_url||slug(nome));

      var nomeCat=texto(p.categoria||p.categoria_nome||p.quiz_categoria||'');
      var idCat=p.slug_categoria||p.categoria_slug||p.quiz_category_id||(nomeCat?slug(nomeCat):'');
      if(idCat&&!catsSim[idCat])catsSim[idCat]={id:idCat,name:nomeCat||idCat,desc:'',active:true};

      var comp=(p.composicao||p.composition||p.categorias||p.modulos||[])
        .map(function(x,i){
          var cid=x.categoria_id||x.question_category_id||x.slug_categoria
                 ||x.categoria_slug||(x.categoria?slug(x.categoria):'');
          var qtd=+(x.quantidade!=null?x.quantidade:x.questions_quantity)||0;
          if(!cid||qtd<1)return null;
          return {id:'cc-'+cid, question_category_id:cid,
                  questions_quantity:qtd,
                  is_active:x.ativo==null&&x.is_active==null?true:verdade(x.ativo!=null?x.ativo:x.is_active)};
        }).filter(Boolean);

      /* categoria repetida na mesma prova: soma, nao duplica (a chave no
         banco e simulado+categoria) */
      var porCat={};
      comp.forEach(function(x){
        if(porCat[x.question_category_id])porCat[x.question_category_id].questions_quantity+=x.questions_quantity;
        else porCat[x.question_category_id]=x;
      });
      comp=Object.keys(porCat).map(function(k){return porCat[k];});

      var regra=String(p.regra_acesso||p.access_rule_id||p.acesso||'').toLowerCase();
      provas.push({
        id:idSim,
        quiz_category_id:idCat||'',
        name:nome||'(sem nome)',
        friendly_url:slug(p.slug||p.friendly_url||p.url_amigavel||nome),
        headline:texto(p.chamada||p.headline||p.subtitulo||''),
        description:String(p.descricao||p.description||''),
        keywords:texto(p.palavras_chave||p.keywords||''),
        file_download_url:String(p.url_download||p.file_download_url||''),
        time_limit:+(p.tempo_limite!=null?p.tempo_limite:p.time_limit)||0,
        hit_percentage:+(p.percentual_acerto!=null?p.percentual_acerto:p.hit_percentage)||70,
        access_rule_id:/assinante/.test(regra)?'assinantes':(/cadastr/.test(regra)?'cadastrados':'livre'),
        is_active:verdade(p.ativo==null&&p.is_active==null?true:(p.ativo!=null?p.ativo:p.is_active)),
        composition:comp
      });
    });

    var listaCatsSim=Object.keys(catsSim).map(function(k){return catsSim[k];})
                           .sort(function(a,b){return a.name.localeCompare(b.name,'pt-BR');});

    /* Prova que aponta para categoria que nao veio no arquivo nao sorteia
       nada. Melhor dizer isso agora do que o aluno descobrir na prova. */
    var catsQueExistem={}; listaCats.forEach(function(c){catsQueExistem[c.id]=true;});
    var provasQuebradas=provas.filter(function(p){
      return !p.composition.length
          || p.composition.some(function(x){return !catsQueExistem[x.question_category_id];});
    }).map(function(p){return p.name;});

    return {
      categorias:listaCats,
      questoes:questoes,
      simulados:provas,
      categoriasSimulado:listaCatsSim,
      resumo:{
        simulados:provas.length,
        categoriasSimulado:listaCatsSim.length,
        provasQuebradas:provasQuebradas,
        questoes:questoes.length,
        categorias:listaCats.length,
        alternativas:questoes.reduce(function(n,q){return n+q.answers.length;},0),
        comAudio:questoes.filter(function(q){return q.audioUrl;}).length,
        semGabarito:semGabarito.length,
        semEnunciado:semEnunciado,
        refsSemGabarito:semGabarito.slice(0,50)
      }
    };
  }

  /* --------------------------------------------------------------- gravar */
  /* Junta com o que ja existe no painel, casando pelo id (o ref). Reimportar
     o mesmo arquivo atualiza em vez de duplicar. */
  function aplicar(r){
    if(!r||r.erro)return {ok:false, motivo:(r&&r.erro)||'nada para importar'};

    db.qCategories = db.qCategories || [];
    db.questions   = db.questions   || [];

    var porId={};
    db.qCategories.forEach(function(c){porId[c.id]=c;});
    var novasCats=0;
    r.categorias.forEach(function(c){
      if(porId[c.id]){porId[c.id].name=c.name;}
      else{db.qCategories.push(c);novasCats++;}
    });

    var idx={};
    db.questions.forEach(function(q,i){idx[q.id]=i;});
    var novas=0, atualizadas=0;
    r.questoes.forEach(function(q){
      if(idx[q.id]!=null){db.questions[idx[q.id]]=q;atualizadas++;}
      else{db.questions.push(q);novas++;}
    });

    /* Simulados: o ref e o id de la, entao reimportar atualiza no lugar.
       A composicao vem inteira do arquivo -- ela e o simulado. */
    db.simCategories = db.simCategories || [];
    db.simulados     = db.simulados     || [];
    var catSimPorId={}; db.simCategories.forEach(function(c){catSimPorId[c.id]=c;});
    var novasCatsSim=0;
    (r.categoriasSimulado||[]).forEach(function(c){
      if(catSimPorId[c.id]){catSimPorId[c.id].name=c.name;}
      else{db.simCategories.push(c);novasCatsSim++;}
    });

    var idxSim={}; db.simulados.forEach(function(x,i){idxSim[x.id]=i;});
    var novosSims=0, simsAtualizados=0;
    (r.simulados||[]).forEach(function(p){
      if(idxSim[p.id]!=null){db.simulados[idxSim[p.id]]=p;simsAtualizados++;}
      else{db.simulados.push(p);novosSims++;}
    });

    save();
    return {ok:true, novasCategorias:novasCats, novas:novas, atualizadas:atualizadas,
            novosSimulados:novosSims, simuladosAtualizados:simsAtualizados,
            novasCategoriasSimulado:novasCatsSim,
            resumo:r.resumo};
  }

  window.EDMigrar={analisar:analisar, aplicar:aplicar, slug:slug};
})();
