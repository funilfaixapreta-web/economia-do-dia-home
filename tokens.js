/* ============================================================
   Tokens do Economia do Dia  ·  decisão da reunião de 05/08
   ------------------------------------------------------------
   Todo usuário ganha um saldo de tokens no primeiro login e gasta
   esse saldo para fazer simulados, assistir aulas e consultar a IA.
   Quando zera, bloqueia e oferece os cursos.

   ATENÇÃO: protótipo. O saldo mora no localStorage, igual ao resto
   do sistema hoje. Isso valida a experiência, mas NÃO é um controle
   real: limpar o navegador zera o contador. O controle de verdade
   (conta, saldo e validação por código) exige backend.
   ============================================================ */
(function(){
  var UKEY='ed-user', WKEY='ed-wallet';

  /* ---------- configuração (editável em Admin › Sistema › Tokens) ---------- */
  var PADRAO={
    ativo:true,
    inicial:10,        // saldo no primeiro login
    renovaMes:false,   // repor o saldo todo mês
    custo:{simulado:10, aula:2, ia:1}
  };
  function cfg(){
    var c={};try{var db=JSON.parse(localStorage.getItem('eda-db'));c=(db&&db.tokens)||{};}catch(_){}
    return {
      ativo:c.ativo==null?PADRAO.ativo:!!c.ativo,
      inicial:c.inicial==null?PADRAO.inicial:+c.inicial,
      renovaMes:c.renovaMes==null?PADRAO.renovaMes:!!c.renovaMes,
      custo:{
        simulado:(c.custo&&c.custo.simulado!=null)?+c.custo.simulado:PADRAO.custo.simulado,
        aula:(c.custo&&c.custo.aula!=null)?+c.custo.aula:PADRAO.custo.aula,
        ia:(c.custo&&c.custo.ia!=null)?+c.custo.ia:PADRAO.custo.ia
      }
    };
  }

  /* ---------- sessão ---------- */
  function user(){try{return JSON.parse(localStorage.getItem(UKEY))||null}catch(_){return null}}
  function setUser(u){try{localStorage.setItem(UKEY,JSON.stringify(u))}catch(_){}}
  function logout(){try{localStorage.removeItem(UKEY)}catch(_){}}

  /* ---------- carteira ---------- */
  function competencia(d){d=d||new Date();return d.getFullYear()+'-'+(d.getMonth()+1);}
  function wallet(){
    var c=cfg(), w=null;
    try{w=JSON.parse(localStorage.getItem(WKEY))}catch(_){}
    if(!w||typeof w.saldo!=='number'){
      w={saldo:c.inicial,liberado:{},criadaEm:Date.now(),mes:competencia()};saveW(w);
    }
    if(!w.liberado)w.liberado={};
    /* recarga mensal, quando ligada no admin: repõe o saldo uma vez por mês
       (nunca reduz, se o aluno recebeu tokens extras do comercial) */
    if(c.renovaMes&&w.mes!==competencia()){
      w.mes=competencia();
      if(w.saldo<c.inicial)w.saldo=c.inicial;
      saveW(w);
    }
    return w;
  }
  function saveW(w){try{localStorage.setItem(WKEY,JSON.stringify(w))}catch(_){}}
  function saldo(){return wallet().saldo;}
  function creditar(n){var w=wallet();w.saldo+=(+n||0);saveW(w);return w.saldo;}

  /* Um item já liberado não cobra de novo: rever a mesma aula é grátis. */
  function chaveDe(tipo,id){return tipo+':'+(id||'-');}
  function liberado(tipo,id){return !!wallet().liberado[chaveDe(tipo,id)];}

  /* Tenta pagar. Devolve {ok:true} ou {ok:false,motivo:'sem-saldo',falta:N} */
  function cobrar(tipo,id){
    var c=cfg();
    if(!c.ativo)return {ok:true,gratis:true};
    if(liberado(tipo,id))return {ok:true,jaLiberado:true};
    var preco=c.custo[tipo]||0, w=wallet();
    if(preco<=0){w.liberado[chaveDe(tipo,id)]=Date.now();saveW(w);return {ok:true,gratis:true};}
    if(w.saldo<preco)return {ok:false,motivo:'sem-saldo',falta:preco-w.saldo,preco:preco,saldo:w.saldo};
    w.saldo-=preco;w.liberado[chaveDe(tipo,id)]=Date.now();saveW(w);
    return {ok:true,cobrado:preco,saldo:w.saldo};
  }
  function preco(tipo){var c=cfg();return c.ativo?(c.custo[tipo]||0):0;}

  /* ---------- estilos compartilhados dos avisos ---------- */
  var CSS='.edtk-scrim{position:fixed;inset:0;background:rgba(4,5,7,.78);backdrop-filter:blur(6px);z-index:600;display:none;align-items:center;justify-content:center;padding:22px;opacity:0;transition:opacity .22s}'
    +'.edtk-scrim.show{display:flex;opacity:1}'
    +'.edtk{background:#0B0D10;border:1px solid rgba(212,164,55,.3);border-radius:20px;max-width:460px;width:100%;padding:30px 28px;position:relative;box-shadow:0 40px 100px rgba(0,0,0,.6);transform:translateY(12px);transition:transform .22s;max-height:88vh;overflow:auto}'
    +'[data-theme="light"] .edtk{background:#FFFFFF}'
    +'.edtk-scrim.show .edtk{transform:none}'
    +'.edtk .x{position:absolute;top:14px;right:14px;width:32px;height:32px;border-radius:9px;border:1px solid var(--border,rgba(255,255,255,.08));background:var(--overlay-soft,rgba(255,255,255,.05));color:var(--muted,#8A94A2);cursor:pointer;font-size:17px;line-height:1}'
    +'.edtk .pe{font-family:"IBM Plex Mono",monospace;font-size:11px;letter-spacing:.12em;text-transform:uppercase;color:var(--gold-deep,#E6BE54);margin-bottom:8px}'
    +'.edtk h3{font-family:"Sora",sans-serif;font-size:22px;letter-spacing:-.3px;margin-bottom:8px;color:var(--head,#fff);line-height:1.25}'
    +'.edtk p{color:var(--muted,#8A94A2);font-size:14.5px;line-height:1.6;margin-bottom:10px}'
    +'.edtk .coin{display:inline-flex;align-items:center;gap:9px;background:linear-gradient(180deg,#E6BE54,#D4A437);color:#0B0D10;border-radius:999px;padding:9px 17px;font-family:"Sora",sans-serif;font-weight:700;font-size:15px;margin:6px 0 14px}'
    +'.edtk ul{list-style:none;margin:14px 0 4px}'
    +'.edtk li{display:flex;align-items:center;gap:10px;font-size:13.5px;color:var(--text,#E7EAEF);padding:8px 0;border-top:1px solid var(--border-soft,rgba(255,255,255,.06))}'
    +'.edtk li .pz{margin-left:auto;font-family:"IBM Plex Mono",monospace;font-size:12px;color:var(--gold-deep,#E6BE54)}'
    +'.edtk .acts{display:flex;gap:10px;flex-wrap:wrap;margin-top:20px}'
    +'.edtk .b{display:inline-flex;align-items:center;justify-content:center;gap:8px;font-family:inherit;font-weight:600;font-size:14px;border-radius:11px;padding:11px 18px;cursor:pointer;border:1px solid transparent;text-decoration:none}'
    +'.edtk .b.g{background:linear-gradient(180deg,#E6BE54,#D4A437);color:#0B0D10}'
    +'.edtk .b.o{background:var(--overlay-soft,rgba(255,255,255,.05));border-color:var(--overlay-bd,rgba(255,255,255,.14));color:var(--text,#E7EAEF)}';
  var styled=false, scrim=null;
  function ensure(){
    if(!styled){var st=document.createElement('style');st.textContent=CSS;document.head.appendChild(st);styled=true;}
    if(!scrim){
      scrim=document.createElement('div');scrim.className='edtk-scrim';
      scrim.innerHTML='<div class="edtk" role="dialog" aria-modal="true"><button class="x" aria-label="Fechar">×</button><div class="body"></div></div>';
      document.body.appendChild(scrim);
      scrim.addEventListener('click',function(e){if(e.target===scrim)fechar();});
      scrim.querySelector('.x').addEventListener('click',fechar);
    }
  }
  function abrir(html){ensure();scrim.querySelector('.body').innerHTML=html;scrim.classList.add('show');}
  function fechar(){if(scrim)scrim.classList.remove('show');}

  /* ---------- pop-up de boas-vindas (primeiro login) ---------- */
  function boasVindas(){
    var c=cfg();if(!c.ativo)return;
    var u=user();if(!u||u.viuTokens)return;
    var w=wallet();
    abrir('<div class="pe">Economia do Dia</div>'
      +'<h3>Bem-vindo! Você ganhou tokens para explorar.</h3>'
      +'<span class="coin">◉ '+w.saldo+' tokens</span>'
      +'<p>Use como quiser para conhecer a plataforma por dentro: faça o simulado, assista às aulas e converse com a nossa IA de estudos.</p>'
      +'<ul>'
        +'<li>Simulado completo, com correção <span class="pz">'+c.custo.simulado+' tokens</span></li>'
        +'<li>Aula do curso <span class="pz">'+c.custo.aula+' tokens</span></li>'
        +'<li>Pergunta para a IA de estudos <span class="pz">'+c.custo.ia+' token'+(c.custo.ia===1?'':'s')+'</span></li>'
      +'</ul>'
      +'<p style="font-size:13px;margin-top:12px">Você só paga de novo se voltar a um conteúdo diferente: rever o que já abriu não gasta token.</p>'
      +'<div class="acts"><button class="b g" data-tk-close>Começar a explorar</button></div>');
    scrim.querySelector('[data-tk-close]').addEventListener('click',function(){
      var uu=user();if(uu){uu.viuTokens=true;setUser(uu);}
      fechar();
    });
  }

  /* ---------- pop-up de saldo esgotado ---------- */
  function semSaldo(r){
    abrir('<div class="pe">Seus tokens acabaram</div>'
      +'<h3>Para continuar, escolha um curso.</h3>'
      +'<p>Você usou os tokens gratuitos. Com o curso você libera todos os simulados, o gabarito comentado em áudio, as aulas e a IA de estudos sem limite.</p>'
      +(r&&r.preco?('<p style="font-size:13px">Este conteúdo custa <b style="color:var(--gold-deep,#E6BE54)">'+r.preco+' tokens</b> e você tem '+(r.saldo||0)+'.</p>'):'')
      +'<div class="acts"><a class="b g" href="index.html#cursos">Ver cursos e planos</a>'
      +'<button class="b o" data-tk-close>Agora não</button></div>');
    scrim.querySelector('[data-tk-close]').addEventListener('click',fechar);
  }

  /* ---------- portão: exige login e cobra o token ---------- */
  /* destino = URL para onde voltar depois do login */
  function exigirLogin(destino){
    location.href='login.html?next='+encodeURIComponent(destino||(location.pathname.split('/').pop()+location.search+location.hash));
  }
  function liberar(tipo,id,destino){
    if(!user()){exigirLogin(destino);return false;}
    var r=cobrar(tipo,id);
    if(!r.ok){semSaldo(r);return false;}
    return true;
  }

  window.EDTokens={
    cfg:cfg, user:user, setUser:setUser, logout:logout,
    saldo:saldo, creditar:creditar, cobrar:cobrar, preco:preco, liberado:liberado,
    liberar:liberar, exigirLogin:exigirLogin,
    boasVindas:boasVindas, semSaldo:semSaldo, fechar:fechar
  };

  /* mostra as boas-vindas assim que houver sessão nova */
  if(document.readyState!=='loading')setTimeout(boasVindas,400);
  else document.addEventListener('DOMContentLoaded',function(){setTimeout(boasVindas,400);});
})();
