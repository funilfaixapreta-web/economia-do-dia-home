/* ============================================================================
   Economia do Dia · ponte com o Supabase
   ----------------------------------------------------------------------------
   Cliente enxuto sobre a API REST do Supabase, sem SDK e sem CDN: o site e
   HTML estatico e so precisa de quatro chamadas.

     cadastrar()  POST /auth/v1/signup
     entrar()     POST /auth/v1/token?grant_type=password
     saldo()      GET  /rest/v1/carteiras?select=saldo     (RLS devolve so a sua)
     gastar()     POST /rest/v1/rpc/gastar_token           (debita e libera junto)

   A chave publicavel abaixo e feita para ficar no front-end. Quem protege o
   dado e o RLS no banco, nao o segredo da chave.

   IMPORTANTE: enquanto ED_API.ativo for false, tudo continua funcionando no
   localStorage como antes. Ligar so depois de validar o cadastro de verdade.
   ============================================================================ */
(function(){
  var CFG={
    url:   'https://ernqeokvkytwdlmjupwm.supabase.co',
    chave: 'sb_publishable_btQ4val3FSdMv0UbjUtfXw_zUsFjqOL',
    /* CHAVE DE LIGA/DESLIGA. false = protótipo em localStorage (comportamento
       atual, publicado). true = banco de verdade. */
    ativo: false
  };
  var SKEY='ed-sessao';

  function sessao(){try{return JSON.parse(localStorage.getItem(SKEY))||null}catch(_){return null}}
  function guardaSessao(s){try{localStorage.setItem(SKEY,JSON.stringify(s))}catch(_){}}
  function limpaSessao(){try{localStorage.removeItem(SKEY)}catch(_){}}

  function cabecalhos(comAuth){
    var h={'apikey':CFG.chave,'Content-Type':'application/json'};
    var s=sessao();
    if(comAuth&&s&&s.access_token)h['Authorization']='Bearer '+s.access_token;
    return h;
  }

  function chamar(caminho,opcoes){
    opcoes=opcoes||{};
    return fetch(CFG.url+caminho,{
      method:opcoes.metodo||'GET',
      headers:Object.assign(cabecalhos(opcoes.auth!==false),opcoes.headers||{}),
      body:opcoes.corpo?JSON.stringify(opcoes.corpo):undefined
    }).then(function(r){
      return r.text().then(function(t){
        var d=null;try{d=t?JSON.parse(t):null}catch(_){d=t;}
        if(!r.ok){
          var e=new Error((d&&(d.msg||d.message||d.error_description||d.error))||('HTTP '+r.status));
          e.status=r.status;e.corpo=d;throw e;
        }
        return d;
      });
    });
  }

  /* ---------------------------------------------------------------- sessao */
  function aplicarSessao(d){
    if(!d||!d.access_token)return null;
    var u=d.user||{}, meta=u.user_metadata||{};
    guardaSessao({
      access_token:d.access_token, refresh_token:d.refresh_token,
      expira_em:Date.now()+((d.expires_in||3600)*1000),
      user:{id:u.id,email:u.email,nome:meta.nome||'',telefone:meta.telefone||u.phone||''}
    });
    /* mantem o formato que o resto do site ja le */
    try{
      var antigo=JSON.parse(localStorage.getItem('ed-user')||'null');
      localStorage.setItem('ed-user',JSON.stringify({
        nome:meta.nome||(u.email||'').split('@')[0], email:u.email||'',
        telefone:meta.telefone||u.phone||'', plano:null,
        viuTokens:!!(antigo&&antigo.viuTokens), criadoEm:Date.now()
      }));
    }catch(_){}
    return sessao();
  }

  function cadastrar(d){
    return chamar('/auth/v1/signup',{metodo:'POST',auth:false,corpo:{
      email:d.email, password:d.senha,
      data:{nome:d.nome, telefone:d.telefone}
    }}).then(function(r){
      /* com "Confirm email" ligado no painel, o Supabase devolve o usuario
         mas NAO devolve sessao: e preciso confirmar o e-mail antes. */
      if(!r||!r.access_token)return {ok:true, precisaConfirmar:true};
      aplicarSessao(r);
      return {ok:true, precisaConfirmar:false};
    });
  }

  function entrar(d){
    return chamar('/auth/v1/token?grant_type=password',{metodo:'POST',auth:false,
      corpo:{email:d.email,password:d.senha}
    }).then(function(r){aplicarSessao(r);return {ok:true};});
  }

  function sair(){
    var s=sessao();
    limpaSessao();
    try{localStorage.removeItem('ed-user')}catch(_){}
    if(!s)return Promise.resolve();
    return chamar('/auth/v1/logout',{metodo:'POST'}).catch(function(){});
  }

  /* --------------------------------------------------------------- tokens */
  function saldo(){
    return chamar('/rest/v1/carteiras?select=saldo').then(function(linhas){
      return (linhas&&linhas[0])?linhas[0].saldo:0;
    });
  }

  /* devolve {ok, saldo, motivo} — os mesmos motivos da funcao no banco:
     cobrado | ja-liberado | sem-saldo | gratis | desligado | sem-sessao */
  function gastar(tipo,itemId){
    return chamar('/rest/v1/rpc/gastar_token',{metodo:'POST',
      corpo:{p_tipo:tipo, p_item_id:String(itemId||'-')}
    }).then(function(r){
      var l=Array.isArray(r)?r[0]:r;
      return l||{ok:false,saldo:0,motivo:'sem-resposta'};
    });
  }

  function config(){
    return chamar('/rest/v1/config_tokens?select=*').then(function(l){
      var c=(l&&l[0])||{};
      return {ativo:c.ativo!==false, inicial:c.inicial, renovaMes:!!c.renova_mes,
              custo:{simulado:c.custo_simulado, aula:c.custo_aula, ia:c.custo_ia}};
    });
  }

  window.EDApi={
    ativo:function(){return !!CFG.ativo;},
    url:CFG.url,
    sessao:sessao, cadastrar:cadastrar, entrar:entrar, sair:sair,
    saldo:saldo, gastar:gastar, config:config
  };
})();
