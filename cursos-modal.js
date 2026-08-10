/* Seletor de cursos do Economia do Dia.
   Abre um pop-up com os cursos disponíveis e leva o usuário para a página do curso
   escolhido (curso.html), onde ele pode assistir a aula ou fazer o simulado.
   Uso: EDCursos.open('cursos') | EDCursos.open('simulados') */
(function(){
  var CURSOS=[
    {cert:'cnpi-cb', code:'CNPI · CB',  name:'Base do Mercado Financeiro',   desc:'Fase comum a todos os analistas: sistema financeiro, renda fixa, derivativos, ética e regulação.'},
    {cert:'cnpi-cg1',code:'CNPI · CG1', name:'Análise Fundamentalista',      desc:'Valuation, finanças corporativas e contabilidade para o analista de research.'},
    {cert:'cnpi-ct1',code:'CNPI · CT1', name:'Análise Técnica (Gráfica)',    desc:'Tendências, candles, indicadores e estratégias operacionais.'},
    {cert:'cfg',     code:'CFG',        name:'Gestão de Recursos e Fundos',  desc:'Certificação ANBIMA de Fundamentos em Gestão, porta de entrada para CGA e CGE.'}
  ];

  var CSS='.edcur-scrim{position:fixed;inset:0;background:rgba(4,5,7,.78);backdrop-filter:blur(6px);z-index:500;display:none;align-items:center;justify-content:center;padding:22px;opacity:0;transition:opacity .22s}'
    +'.edcur-scrim.show{display:flex;opacity:1}'
    +'.edcur{background:#0B0D10;border:1px solid rgba(212,164,55,.3);border-radius:20px;max-width:560px;width:100%;padding:30px 28px;position:relative;box-shadow:0 40px 100px rgba(0,0,0,.6);transform:translateY(12px);transition:transform .22s;max-height:88vh;overflow:auto}'
    +'[data-theme="light"] .edcur{background:#FFFFFF}'
    +'.edcur-scrim.show .edcur{transform:none}'
    +'.edcur .x{position:absolute;top:14px;right:14px;width:32px;height:32px;border-radius:9px;border:1px solid var(--border,rgba(255,255,255,.08));background:var(--overlay-soft,rgba(255,255,255,.05));color:var(--muted,#8A94A2);cursor:pointer;font-size:17px;line-height:1}'
    +'.edcur .x:hover{color:var(--head,#fff)}'
    +'.edcur .pe{font-family:"IBM Plex Mono",monospace;font-size:11px;letter-spacing:.12em;text-transform:uppercase;color:var(--gold-deep,#E6BE54);margin-bottom:8px}'
    +'.edcur h3{font-family:"Sora",sans-serif;font-size:22px;letter-spacing:-.3px;margin-bottom:6px;color:var(--head,#fff);line-height:1.25}'
    +'.edcur .sub{color:var(--muted,#8A94A2);font-size:14px;line-height:1.55}'
    +'.edcur-list{display:flex;flex-direction:column;gap:10px;margin-top:20px}'
    +'.edcur-item{display:flex;align-items:center;gap:14px;text-decoration:none;background:var(--panel,#101319);border:1px solid var(--border,rgba(255,255,255,.08));border-radius:13px;padding:14px 16px;transition:border-color .15s,transform .15s}'
    +'[data-theme="light"] .edcur-item{background:#F3F1EA}'
    +'.edcur-item:hover{border-color:rgba(212,164,55,.5);transform:translateY(-2px)}'
    +'.edcur-item .tag{flex:none;font-family:"IBM Plex Mono",monospace;font-weight:600;font-size:11px;color:#0B0D10;background:linear-gradient(180deg,#E6BE54,#D4A437);border-radius:7px;padding:6px 9px;min-width:74px;text-align:center}'
    +'.edcur-item .nm{font-family:"Sora",sans-serif;font-weight:600;font-size:15px;color:var(--head,#fff);line-height:1.3}'
    +'.edcur-item .dc{font-size:12.5px;color:var(--muted,#8A94A2);line-height:1.45;margin-top:3px}'
    +'.edcur-item .go{flex:none;color:var(--gold-deep,#E6BE54);font-size:18px}'
    +'@media(max-width:520px){.edcur{padding:26px 20px}.edcur-item{align-items:flex-start}.edcur-item .tag{min-width:0}}';

  var scrim=null;

  function build(){
    var st=document.createElement('style');st.textContent=CSS;document.head.appendChild(st);
    scrim=document.createElement('div');scrim.className='edcur-scrim';
    scrim.innerHTML='<div class="edcur" role="dialog" aria-modal="true">'
      +'<button class="x" aria-label="Fechar">×</button>'
      +'<div class="pe">Economia do Dia</div><h3></h3><div class="sub"></div>'
      +'<div class="edcur-list"></div></div>';
    document.body.appendChild(scrim);
    scrim.addEventListener('click',function(e){if(e.target===scrim)close();});
    scrim.querySelector('.x').addEventListener('click',close);
    document.addEventListener('keydown',function(e){if(e.key==='Escape')close();});
  }

  function close(){if(scrim)scrim.classList.remove('show');}

  function open(mode){
    if(!scrim)build();
    var sim=(mode==='simulados');
    scrim.querySelector('h3').textContent=sim?'Escolha o simulado':'Nossos cursos';
    scrim.querySelector('.sub').textContent=sim
      ? 'Estes são os cursos com simulados disponíveis. Escolha um e você vai para a página do curso, onde pode fazer o simulado ou assistir a aula.'
      : 'Escolha um curso para ver o conteúdo, os simulados e as aulas.';
    scrim.querySelector('.edcur-list').innerHTML=CURSOS.map(function(c){
      return '<a class="edcur-item" href="curso.html?cert='+c.cert+(sim?'#simulados':'')+'">'
        +'<span class="tag">'+c.code+'</span>'
        +'<span style="flex:1;min-width:0"><span class="nm" style="display:block">'+c.name+'</span><span class="dc" style="display:block">'+c.desc+'</span></span>'
        +'<span class="go">→</span></a>';
    }).join('');
    scrim.classList.add('show');
  }

  window.EDCursos={open:open,close:close,list:CURSOS};

  /* qualquer elemento com data-ed-cursos="cursos|simulados" abre o seletor */
  document.addEventListener('click',function(e){
    var t=e.target.closest?e.target.closest('[data-ed-cursos]'):null;
    if(!t)return;
    e.preventDefault();
    open(t.getAttribute('data-ed-cursos'));
  });
})();
