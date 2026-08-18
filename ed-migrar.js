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
      var idCat   = slug(nomeCat);
      if(!cats[idCat]) cats[idCat]={id:idCat, name:nomeCat||'Sem categoria', desc:'', active:true};

      var alts=(q.alternativas||q.answers||q.opcoes||[])
        .slice()
        .sort(function(a,b){return (+a.ordem||0)-(+b.ordem||0);})
        .map(function(a){
          return {text:texto(a.texto||a.text||''), correct:verdade(a.correta||a.correct)};
        })
        .filter(function(a){return a.text;});

      var enun=texto(q.enunciado||q.text||q.pergunta||'');
      if(!enun)semEnunciado++;

      var corretas=alts.filter(function(a){return a.correct;}).length;
      var ref='legacy-'+(q.id!=null?q.id:(questoes.length+1));
      if(alts.length<2||corretas!==1)semGabarito.push(ref);

      questoes.push({
        id:ref,                                   /* vira o ref no banco */
        categoryId:idCat,
        text:enun||'(sem enunciado)',
        comment:texto(q.comentario||q.explicacao||q.comment||''),
        /* o audio do gabarito comentado do site antigo */
        audioUrl:(q.audio_src||q.audio||q.audio_url||'')||'',
        audioEmbed:'',
        accessRule:'livre',
        active:verdade(q.ativo==null?true:q.ativo),
        answers:alts.map(function(a,i){
          return {id:'a'+(i+1), text:a.text, correct:a.correct, active:true};
        })
      });
    });

    var listaCats=Object.keys(cats).map(function(k){return cats[k];})
                        .sort(function(a,b){return a.name.localeCompare(b.name,'pt-BR');});

    return {
      categorias:listaCats,
      questoes:questoes,
      resumo:{
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

    save();
    return {ok:true, novasCategorias:novasCats, novas:novas, atualizadas:atualizadas,
            resumo:r.resumo};
  }

  window.EDMigrar={analisar:analisar, aplicar:aplicar, slug:slug};
})();
