/* Popup de captura/aviso do Economia do Dia, compartilhado pelas páginas do site.
   Lê os popups ativos do admin (localStorage eda-db). Sem eda-db, usa um padrão.
   Respeita o que o admin configurou:
     onde       → pages: quais páginas exibem este popup (vazio = todas)
     em que caso→ trigger: entrada | tempo | rolagem | saida
     quanto     → delay (segundos) e scrollPct (% da página)
     frequência → freq: sessao | dia | sempre                                   */
(function(){
  var CSS='.edpop-scrim{position:fixed;inset:0;background:rgba(6,8,11,.72);backdrop-filter:blur(5px);z-index:400;display:none;align-items:center;justify-content:center;padding:22px;opacity:0;transition:opacity .25s}'
    +'.edpop-scrim.show{display:flex;opacity:1}'
    +'.edpop{background:#0B0D10;border:1px solid var(--gold-soft-bd,rgba(212,164,55,.3));border-radius:20px;max-width:440px;width:100%;padding:32px 30px;position:relative;box-shadow:0 40px 100px rgba(0,0,0,.55);transform:translateY(12px);transition:transform .25s}'
    +'[data-theme="light"] .edpop{background:#FFFFFF}'
    +'.edpop-scrim.show .edpop{transform:none}'
    +'.edpop .x{position:absolute;top:14px;right:14px;width:32px;height:32px;border-radius:9px;border:1px solid var(--border,rgba(255,255,255,.08));background:var(--overlay-soft,rgba(255,255,255,.05));color:var(--muted,#8A94A2);cursor:pointer;font-size:17px;line-height:1}'
    +'.edpop .x:hover{color:var(--head,#fff)}'
    +'.edpop .pe{font-family:"IBM Plex Mono",monospace;font-size:11px;letter-spacing:.12em;text-transform:uppercase;color:var(--gold-deep,#E6BE54);margin-bottom:8px}'
    +'.edpop h3{font-family:"Sora",sans-serif;font-size:23px;letter-spacing:-.3px;margin-bottom:8px;color:var(--head,#fff);line-height:1.25}'
    +'.edpop .pc{color:var(--text,#E7EAEF);font-size:15px;line-height:1.65}.edpop .pc p{margin:6px 0}.edpop .pc a{color:var(--gold-deep,#E6BE54)}'
    +'.edpop .pcta{margin-top:20px;display:flex;gap:10px;flex-wrap:wrap;align-items:center}'
    +'.edpop .plink{background:none;border:none;color:var(--muted,#8A94A2);font-family:inherit;font-size:13.5px;cursor:pointer;padding:6px}.edpop .plink:hover{color:var(--head,#fff)}'
    +'.edpop .edbtn{display:inline-flex;align-items:center;gap:8px;font-family:inherit;font-weight:600;font-size:14px;border-radius:11px;padding:11px 18px;cursor:pointer;border:1px solid transparent;text-decoration:none;background:var(--gold-grad,linear-gradient(180deg,#E6BE54,#D4A437));color:#0B0D10}';
  var st=document.createElement('style');st.textContent=CSS;document.head.appendChild(st);

  var DEFAULT_POPUP={id:'po1',title:'Faça um simulado grátis',content:'<p>Teste seus conhecimentos com um simulado gratuito, com correção comentada e gabarito em áudio.</p>',
    cta:'Escolher meu simulado',ctaUrl:'#simulados',pages:[],trigger:'saida',delay:25,scrollPct:40,freq:'sessao',active:true};

  /* qual página é esta, para casar com o "onde" do admin */
  function paginaAtual(){
    var f=(location.pathname.split('/').pop()||'index.html').toLowerCase().replace(/\.html$/,'');
    if(f===''||f==='index')return 'home';
    if(f==='curso')return 'cursos';
    if(f==='artigos')return 'artigos';
    if(f==='artigo')return 'artigo';
    if(f==='pagina')return 'pagina';
    return f;
  }
  function valeAqui(p){
    var ps=p.pages;
    if(!ps||!ps.length)return true;          /* vazio = todas as páginas */
    return ps.indexOf(paginaAtual())>=0;
  }

  /* escolhe o primeiro popup ativo que vale para esta página */
  function load(){
    try{
      var db=JSON.parse(localStorage.getItem('eda-db'));
      if(db&&db.popups){
        var a=db.popups.filter(function(p){return p.active&&valeAqui(p);});
        return a.length?a[0]:null;
      }
    }catch(_){}
    return valeAqui(DEFAULT_POPUP)?DEFAULT_POPUP:null;
  }
  var pop=load();if(!pop)return;
  if(!(pop.cta&&pop.ctaUrl)&&pop.id===DEFAULT_POPUP.id){pop.cta=DEFAULT_POPUP.cta;pop.ctaUrl=DEFAULT_POPUP.ctaUrl;}

  /* frequência: já foi visto? */
  var freq=pop.freq||'sessao', chave='ed-popup-'+pop.id;
  function jaViu(){
    try{
      if(freq==='sempre')return false;
      if(freq==='dia'){
        var d=localStorage.getItem(chave+'-dia');
        return d===new Date().toDateString();
      }
      return !!sessionStorage.getItem(chave);
    }catch(_){return false;}
  }
  function marcaVisto(){
    try{
      if(freq==='sempre')return;
      if(freq==='dia')localStorage.setItem(chave+'-dia',new Date().toDateString());
      else sessionStorage.setItem(chave,'1');
    }catch(_){}
  }
  if(jaViu())return;

  function build(){
    var scrim=document.createElement('div');scrim.className='edpop-scrim';
    var cta=(pop.cta&&pop.ctaUrl)?('<a class="edbtn" href="'+pop.ctaUrl+'">'+pop.cta+'</a>'):'';
    scrim.innerHTML='<div class="edpop"><button class="x" aria-label="Fechar">×</button><div class="pe">Economia do Dia</div><h3></h3><div class="pc"></div><div class="pcta">'+cta+'<button class="plink pclose">Agora não</button></div></div>';
    scrim.querySelector('h3').textContent=pop.title||'';
    scrim.querySelector('.pc').innerHTML=pop.content||'';
    document.body.appendChild(scrim);

    var shown=false;
    function show(){if(shown)return;shown=true;scrim.classList.add('show');marcaVisto();}
    function close(){scrim.classList.remove('show');}
    scrim.addEventListener('click',function(e){if(e.target===scrim)close();});
    scrim.querySelector('.x').addEventListener('click',close);
    scrim.querySelector('.pclose').addEventListener('click',close);

    /* '#simulados' / '#cursos' abrem o seletor de cursos em vez de navegar */
    var btn=scrim.querySelector('.edbtn');
    if(btn&&/^#(simulados|cursos)$/.test(pop.ctaUrl||'')){
      btn.addEventListener('click',function(e){
        if(!window.EDCursos)return;
        e.preventDefault();close();
        window.EDCursos.open(pop.ctaUrl.slice(1));
      });
    }

    var t=pop.trigger||'tempo';
    var seg=(pop.delay==null?null:+pop.delay);
    if(t==='entrada'){
      setTimeout(show,(seg==null?1:seg)*1000);
    }else if(t==='tempo'){
      setTimeout(show,(seg==null?8:seg)*1000);
    }else if(t==='rolagem'){
      var alvo=Math.min(100,Math.max(1,+pop.scrollPct||40))/100;
      var os=function(){
        var h=document.documentElement,max=h.scrollHeight-h.clientHeight;
        if(max>0&&h.scrollTop/max>alvo){show();window.removeEventListener('scroll',os);}
      };
      window.addEventListener('scroll',os,{passive:true});
    }else{
      document.addEventListener('mouseout',function(e){if(!shown&&e.clientY<=0&&!e.relatedTarget)show();});
      var limite=(seg==null?25:seg);
      if(limite>0)setTimeout(show,limite*1000);   /* 0 = só na intenção de saída */
    }
  }
  if(document.body)build();else document.addEventListener('DOMContentLoaded',build);
})();
