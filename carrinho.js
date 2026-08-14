/* ============================================================================
   Economia do Dia · carrinho de compras
   ----------------------------------------------------------------------------
   Carrinho como o de loja grande: fica no canto da barra com o contador, abre
   numa gaveta lateral, guarda o que a pessoa escolheu mesmo se ela fechar o
   navegador, e leva para o checkout.

   O carrinho mora no navegador de proposito — e rascunho, o cliente mexe a
   vontade e nada disso vale dinheiro. O que vale e o PEDIDO, e o pedido nasce
   no banco (criar_pedido), que busca o preco na tabela em vez de acreditar no
   que o navegador mandou.

   Este arquivo se instala sozinho: injeta o proprio CSS, o botao na barra e os
   botoes de comprar nos cartoes de plano. Basta incluir o <script>.
   ============================================================================ */
(function(){

  var CHAVE='ed-carrinho';

  /* ------------------------------------------------------------- dinheiro */
  /* "R$ 2.997" -> 299700 · "R$ 1.234,56" -> 123456 · 997 -> 99700 */
  function paraCentavos(v){
    if(typeof v==='number')return Math.round(v*100);
    var s=String(v||'').replace(/[^\d.,]/g,'');
    if(!s)return 0;
    if(s.indexOf(',')>=0) s=s.replace(/\./g,'').replace(',','.');
    else                  s=s.replace(/\./g,'');      /* ponto e milhar aqui */
    var n=parseFloat(s);
    return isNaN(n)?0:Math.round(n*100);
  }
  function emReais(c){
    return 'R$ '+(c/100).toLocaleString('pt-BR',{minimumFractionDigits:2,maximumFractionDigits:2});
  }

  /* -------------------------------------------------------- os produtos */
  /* Planos de reserva: batem com os cartoes da home. Se o painel tiver algo
     salvo, ou se o banco responder, esses valem mais que estes.            */
  var PADRAO=[
    {id:'completo',       nome:'CNPI · Curso Completo',   preco:'R$ 2.997', validade:'acesso por 2 anos'},
    {id:'fundamentalista',nome:'CNPI · Fundamentalista',  preco:'R$ 2.197', validade:'acesso por 1 ano'},
    {id:'tecnico',        nome:'CNPI · Técnico',          preco:'R$ 2.197', validade:'acesso por 1 ano'},
    {id:'valuation',      nome:'Valuation na Prática',    preco:'R$ 997',   validade:'acesso por 1 ano'}
  ];

  function planos(){
    /* 1. banco, se o catalogo ja chegou */
    try{
      var cat=window.EDConteudo&&EDConteudo.doBanco&&EDConteudo.doBanco();
      if(cat&&cat.planos&&cat.planos.length)
        return cat.planos.map(function(p){
          return {id:p.id, nome:p.nome, centavos:p.preco_centavos||0,
                  validade:p.validade_meses?('acesso por '+(p.validade_meses>=24
                    ? Math.round(p.validade_meses/12)+' anos' : p.validade_meses+' meses')):''};
        });
    }catch(_){}
    /* 2. o que o painel salvou */
    try{
      var db=JSON.parse(localStorage.getItem('eda-db')||'null');
      if(db&&db.plans&&db.plans.length)
        return db.plans.map(function(p){
          return {id:p.id, nome:p.name, centavos:paraCentavos(p.price),
                  validade:(p.benefits||[]).filter(function(b){return /acesso/i.test(b)})[0]||''};
        });
    }catch(_){}
    /* 3. reserva */
    return PADRAO.map(function(p){
      return {id:p.id, nome:p.nome, centavos:paraCentavos(p.preco), validade:p.validade};
    });
  }
  function plano(id){
    var l=planos(), i;
    for(i=0;i<l.length;i++)if(l[i].id===id)return l[i];
    return null;
  }

  /* -------------------------------------------------------------- estado */
  function ler(){
    try{var c=JSON.parse(localStorage.getItem(CHAVE));return Array.isArray(c)?c:[];}
    catch(_){return [];}
  }
  function gravar(c){
    try{localStorage.setItem(CHAVE,JSON.stringify(c));}catch(_){}
    pintar();
  }
  /* Junta o que esta guardado com o preco de AGORA: se o admin mudou o preco
     enquanto o carrinho estava parado, vale o preco novo. */
  function itens(){
    return ler().map(function(l){
      var p=plano(l.id);
      return p?{id:p.id, nome:p.nome, centavos:p.centavos, validade:p.validade,
                quantidade:Math.max(1,l.quantidade||1)}:null;
    }).filter(Boolean);
  }
  function total(){
    return itens().reduce(function(s,i){return s+i.centavos*i.quantidade;},0);
  }
  function contagem(){
    return itens().reduce(function(s,i){return s+i.quantidade;},0);
  }

  function adicionar(id,silencioso){
    var p=plano(id); if(!p)return false;
    var c=ler(), achou=false;
    c.forEach(function(l){if(l.id===id){l.quantidade=(l.quantidade||1)+1;achou=true;}});
    if(!achou)c.push({id:id,quantidade:1});
    gravar(c);
    if(!silencioso)abrir();
    return true;
  }
  function definirQtd(id,n){
    n=Math.max(0,parseInt(n,10)||0);
    var c=ler().map(function(l){return l.id===id?{id:id,quantidade:n}:l;})
               .filter(function(l){return l.quantidade>0;});
    gravar(c);
  }
  function remover(id){definirQtd(id,0);}
  function limpar(){gravar([]);}

  /* ----------------------------------------------------------------- CSS */
  var CSS=''
  +'.ed-cart-btn{position:relative;display:inline-flex;align-items:center;justify-content:center;'
  +'width:38px;height:38px;border-radius:10px;border:1px solid var(--border,rgba(255,255,255,.08));'
  +'background:transparent;color:var(--text,#E7EAEF);cursor:pointer;transition:border-color .15s,color .15s}'
  +'.ed-cart-btn:hover{color:var(--gold-deep,#E6BE54);border-color:var(--gold-soft-bd,rgba(212,164,55,.34))}'
  +'.ed-cart-btn .n{position:absolute;top:-6px;right:-6px;min-width:19px;height:19px;padding:0 5px;'
  +'border-radius:999px;background:var(--gold,#D4A437);color:#0B0D10;font:600 11px/19px "IBM Plex Mono",monospace;'
  +'text-align:center;display:none}'
  +'.ed-cart-btn.tem .n{display:block}'
  +'.ed-cart-scrim{position:fixed;inset:0;background:rgba(0,0,0,.55);opacity:0;pointer-events:none;'
  +'transition:opacity .22s;z-index:998}'
  +'.ed-cart-scrim.on{opacity:1;pointer-events:auto}'
  +'.ed-cart{position:fixed;top:0;right:0;height:100%;width:min(420px,100%);z-index:999;display:flex;'
  +'flex-direction:column;background:var(--panel,#101319);border-left:1px solid var(--border,rgba(255,255,255,.08));'
  +'transform:translateX(100%);transition:transform .26s cubic-bezier(.4,0,.2,1);box-shadow:-24px 0 60px rgba(0,0,0,.4)}'
  +'.ed-cart.on{transform:none}'
  +'.ed-cart h3{margin:0;font-size:17px;color:var(--head,#fff);letter-spacing:-.2px}'
  +'.ed-cart-h{display:flex;align-items:center;gap:10px;padding:20px 22px;border-bottom:1px solid var(--border,rgba(255,255,255,.08))}'
  +'.ed-cart-x{margin-left:auto;background:none;border:0;color:var(--muted,#8A94A2);font-size:24px;line-height:1;cursor:pointer}'
  +'.ed-cart-x:hover{color:var(--head,#fff)}'
  +'.ed-cart-b{flex:1;overflow:auto;padding:8px 22px}'
  +'.ed-cart-i{display:flex;gap:12px;padding:16px 0;border-bottom:1px solid var(--border-soft,rgba(255,255,255,.06))}'
  +'.ed-cart-i .nm{font-size:14.5px;font-weight:600;color:var(--head,#fff);line-height:1.35}'
  +'.ed-cart-i .vl{font-size:12.5px;color:var(--muted,#8A94A2);margin-top:3px}'
  +'.ed-cart-i .pr{font-family:"IBM Plex Mono",monospace;font-size:14px;color:var(--head,#fff);white-space:nowrap}'
  +'.ed-qtd{display:inline-flex;align-items:center;gap:0;margin-top:9px;border:1px solid var(--border,rgba(255,255,255,.08));border-radius:8px;overflow:hidden}'
  +'.ed-qtd button{width:28px;height:26px;background:none;border:0;color:var(--muted,#8A94A2);cursor:pointer;font-size:15px}'
  +'.ed-qtd button:hover{color:var(--gold-deep,#E6BE54);background:rgba(212,164,55,.08)}'
  +'.ed-qtd span{min-width:26px;text-align:center;font:600 13px/26px "IBM Plex Mono",monospace;color:var(--head,#fff)}'
  +'.ed-cart-rm{background:none;border:0;color:var(--faint,#5B6573);font-size:12.5px;cursor:pointer;margin-top:9px;margin-left:10px;text-decoration:underline}'
  +'.ed-cart-rm:hover{color:#E0533D}'
  +'.ed-cart-f{padding:18px 22px;border-top:1px solid var(--border,rgba(255,255,255,.08))}'
  +'.ed-cart-t{display:flex;align-items:baseline;margin-bottom:14px}'
  +'.ed-cart-t span{color:var(--muted,#8A94A2);font-size:14px}'
  +'.ed-cart-t b{margin-left:auto;font-family:"IBM Plex Mono",monospace;font-size:22px;color:var(--head,#fff);font-weight:600}'
  +'.ed-cart-go{display:block;width:100%;padding:13px;border:0;border-radius:11px;background:var(--gold,#D4A437);'
  +'color:#0B0D10;font-size:14.5px;font-weight:600;cursor:pointer;text-align:center;text-decoration:none}'
  +'.ed-cart-go:hover{background:var(--gold-bright,#E6BE54)}'
  +'.ed-cart-go[disabled]{opacity:.45;pointer-events:none}'
  +'.ed-cart-vazio{padding:56px 22px;text-align:center;color:var(--muted,#8A94A2);font-size:14px}'
  +'.ed-cart-seg{font-size:12px;color:var(--faint,#5B6573);text-align:center;margin-top:11px}'
  +'.cur-btns{display:flex;gap:8px;margin-top:auto}'
  +'.cur-btns .cur-btn{flex:1;margin-top:0}'
  +'@media(max-width:900px){.ed-cart{width:100%}}';

  function injetarCSS(){
    if(document.getElementById('ed-cart-css'))return;
    var s=document.createElement('style');
    s.id='ed-cart-css'; s.textContent=CSS;
    document.head.appendChild(s);
  }

  /* --------------------------------------------------------------- gaveta */
  var gaveta, scrim;
  var ICONE='<svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="20" r="1.4"/><circle cx="18" cy="20" r="1.4"/><path d="M2 3h3l2.4 12.2a1.6 1.6 0 0 0 1.6 1.3h8.2a1.6 1.6 0 0 0 1.6-1.3L21 7H6"/></svg>';

  function montar(){
    if(gaveta)return;
    injetarCSS();
    scrim=document.createElement('div');
    scrim.className='ed-cart-scrim';
    scrim.addEventListener('click',fechar);

    gaveta=document.createElement('aside');
    gaveta.className='ed-cart';
    gaveta.setAttribute('aria-label','Carrinho de compras');
    gaveta.innerHTML='<div class="ed-cart-h">'+ICONE+'<h3>Seu carrinho</h3>'
      +'<button class="ed-cart-x" aria-label="Fechar">&times;</button></div>'
      +'<div class="ed-cart-b" id="ed-cart-b"></div>'
      +'<div class="ed-cart-f" id="ed-cart-f"></div>';
    gaveta.querySelector('.ed-cart-x').addEventListener('click',fechar);

    document.body.appendChild(scrim);
    document.body.appendChild(gaveta);
    document.addEventListener('keydown',function(e){
      if(e.key==='Escape'&&gaveta.classList.contains('on'))fechar();
    });
  }

  function desenhar(){
    if(!gaveta)return;
    var l=itens(), b=gaveta.querySelector('#ed-cart-b'), f=gaveta.querySelector('#ed-cart-f');
    if(!l.length){
      b.innerHTML='<div class="ed-cart-vazio">Seu carrinho está vazio.<br>'
        +'<a href="index.html#cursos" style="color:var(--gold-deep,#E6BE54)">Ver os cursos →</a></div>';
      f.innerHTML='';
      return;
    }
    b.innerHTML=l.map(function(i){
      return '<div class="ed-cart-i"><div style="flex:1">'
        +'<div class="nm">'+esc(i.nome)+'</div>'
        +(i.validade?'<div class="vl">'+esc(i.validade)+'</div>':'')
        +'<div><span class="ed-qtd">'
          +'<button type="button" data-menos="'+esc(i.id)+'" aria-label="Menos um">−</button>'
          +'<span>'+i.quantidade+'</span>'
          +'<button type="button" data-mais="'+esc(i.id)+'" aria-label="Mais um">+</button>'
        +'</span><button type="button" class="ed-cart-rm" data-rm="'+esc(i.id)+'">remover</button></div>'
        +'</div><div class="pr">'+emReais(i.centavos*i.quantidade)+'</div></div>';
    }).join('');
    f.innerHTML='<div class="ed-cart-t"><span>Total</span><b>'+emReais(total())+'</b></div>'
      +'<a class="ed-cart-go" href="checkout.html">Finalizar compra</a>'
      +'<div class="ed-cart-seg">Pagamento em ambiente seguro · acesso liberado após a confirmação</div>';

    b.querySelectorAll('[data-mais]').forEach(function(el){
      el.onclick=function(){adicionar(el.getAttribute('data-mais'),true);};});
    b.querySelectorAll('[data-menos]').forEach(function(el){
      el.onclick=function(){var id=el.getAttribute('data-menos');
        var a=itens().filter(function(x){return x.id===id;})[0];
        definirQtd(id,(a?a.quantidade:1)-1);};});
    b.querySelectorAll('[data-rm]').forEach(function(el){
      el.onclick=function(){remover(el.getAttribute('data-rm'));};});
  }

  function abrir(){montar();desenhar();scrim.classList.add('on');gaveta.classList.add('on');}
  function fechar(){if(!gaveta)return;scrim.classList.remove('on');gaveta.classList.remove('on');}

  /* ------------------------------------------------------- botao da barra */
  function botao(){
    var b=document.createElement('button');
    b.type='button'; b.className='ed-cart-btn'; b.id='ed-cart-btn';
    b.setAttribute('aria-label','Abrir carrinho');
    b.innerHTML=ICONE+'<span class="n">0</span>';
    b.addEventListener('click',abrir);
    return b;
  }
  /* Cada pagina tem um topo diferente: a home usa .nav-actions, curso.html e
     artigos.html usam header.top > .wrap. Procura na ordem e para na primeira
     que existir. */
  function instalarBotao(){
    if(document.getElementById('ed-cart-btn'))return;
    var acoes=document.querySelector('.nav-actions');
    if(acoes){acoes.insertBefore(botao(),acoes.firstChild);return;}
    var topo=document.querySelector('header.top > .wrap')||document.querySelector('.nav-inner');
    if(!topo)return;
    var b=botao();
    b.style.marginLeft='4px';
    topo.appendChild(b);
  }

  function pintar(){
    var n=contagem(), b=document.getElementById('ed-cart-btn');
    if(b){b.classList.toggle('tem',n>0);b.querySelector('.n').textContent=n>99?'99+':n;}
    desenhar();
  }

  /* ---------------------------------------------- botao de comprar nos cards */
  /* Os cartoes da home ja tem data-ed-plan. Em vez de repetir HTML em quatro
     lugares, o botao de comprar entra por aqui — do mesmo jeito que o nome e o
     preco desses cartoes ja sao preenchidos por script. */
  function instalarNosCards(){
    document.querySelectorAll('[data-ed-plan]').forEach(function(card){
      if(card.querySelector('[data-ed-comprar]'))return;
      var id=card.getAttribute('data-ed-plan');
      if(!plano(id))return;
      var ver=card.querySelector('.cur-btn');
      var linha=document.createElement('div');
      linha.className='cur-btns';

      var comprar=document.createElement('button');
      comprar.type='button';
      comprar.className='cur-btn gold';
      comprar.setAttribute('data-ed-comprar',id);
      comprar.textContent='Comprar';
      comprar.addEventListener('click',function(e){
        e.preventDefault(); e.stopPropagation(); adicionar(id);
      });

      if(ver){
        ver.parentNode.insertBefore(linha,ver);
        ver.classList.remove('gold'); ver.classList.add('ghost');
        linha.appendChild(ver); linha.appendChild(comprar);
      }else{
        linha.appendChild(comprar);
        card.appendChild(linha);
      }
    });
  }

  /* Na pagina do curso, o "Comprar curso" do topo passa a por no carrinho o
     plano que cobre aquela certificacao. O de-para sai da propria descricao
     dos planos: fundamentalista = CB + CG1, tecnico = CB + CT1. Certificacao
     sem plano proprio continua indo para a lista de cursos. */
  var PLANO_DA_CERT={'cnpi-cb':'completo','cnpi-cg1':'fundamentalista','cnpi-ct1':'tecnico'};
  function instalarBotaoDoCurso(){
    var b=document.getElementById('buy-btn'); if(!b)return;
    var cert=(location.search.match(/[?&]cert=([\w-]+)/)||[])[1]||'';
    var id=PLANO_DA_CERT[cert];
    if(!id||!plano(id))return;              /* sem plano: segue para #cursos */
    b.addEventListener('click',function(e){e.preventDefault();adicionar(id);});
  }

  function esc(s){return String(s==null?'':s)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');}

  /* ------------------------------------------------------------------ boot */
  function iniciar(){
    injetarCSS(); instalarBotao(); instalarNosCards(); instalarBotaoDoCurso(); pintar();
    /* carrinho aberto em outra aba: mantem as duas iguais */
    window.addEventListener('storage',function(e){if(e.key===CHAVE)pintar();});
  }
  if(document.readyState==='loading')
    document.addEventListener('DOMContentLoaded',iniciar);
  else iniciar();

  window.EDCarrinho={
    itens:itens, total:total, contagem:contagem, planos:planos, plano:plano,
    adicionar:adicionar, remover:remover, definirQtd:definirQtd, limpar:limpar,
    abrir:abrir, fechar:fechar, emReais:emReais, paraCentavos:paraCentavos,
    instalar:iniciar
  };
})();
