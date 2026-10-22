/* ============================================================================
   Economia do Dia · ver a senha
   ----------------------------------------------------------------------------
   Sete campos de senha no site, em tres arquivos: o login e o cadastro
   (login.html), a redefinicao (senha.html), o login do painel e o campo de
   senha generico das gavetas (adm.html). Nenhum deixava conferir o que foi
   digitado.

   Isso nao e enfeite: senha de 8+ caracteres digitada no escuro, duas vezes
   ("repita a senha"), em celular com teclado que erra -- e a pessoa so
   descobre o erro quando o login falha. E quem nao consegue entrar nao vira
   aluno.

   Em vez de sete copias, este arquivo acha os campos sozinho e cuida de
   todos. Campos que aparecem depois (a gaveta do painel monta o HTML na hora)
   tambem sao pegos, por MutationObserver.

   DECISOES QUE IMPORTAM

   type="button" e obrigatorio. Botao dentro de <form> sem type explicito e
   type="submit": o olho enviaria o formulario. Os cinco campos que importam
   estao dentro de <form>.

   Volta a esconder ao enviar. Deixar a senha legivel na tela depois do envio
   e como deixar o papel com a senha na mesa -- e em tela compartilhada ou
   gravacao de reuniao, pior.

   Nao mexe no autocomplete. Trocar type de password para text faz alguns
   gerenciadores de senha pararem de oferecer o preenchimento; por isso o
   atributo autocomplete e preservado na troca, e o campo volta a password
   assim que perde o interesse.
   ============================================================================ */
(function(){

  var OLHO_ABERTO =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">'
    + '<path d="M1.8 12s3.6-7 10.2-7 10.2 7 10.2 7-3.6 7-10.2 7S1.8 12 1.8 12z"/><circle cx="12" cy="12" r="3"/></svg>';
  var OLHO_FECHADO =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">'
    + '<path d="M9.9 5.2A9.8 9.8 0 0 1 12 5c6.6 0 10.2 7 10.2 7a18 18 0 0 1-2.7 3.6M6.3 6.4A17.6 17.6 0 0 0 1.8 12s3.6 7 10.2 7a9.7 9.7 0 0 0 4-.8"/>'
    + '<path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/><path d="M2 2l20 20"/></svg>';

  function css(){
    if(document.getElementById('ed-senha-css'))return;
    var e=document.createElement('style');
    e.id='ed-senha-css';
    e.textContent=
      '.ed-senha{position:relative;display:block}'
      /* o padding so na direita: mexer no resto mudaria a altura do campo e
         desalinharia dos outros campos do formulario */
    + '.ed-senha > input{padding-right:46px!important}'
    + '.ed-senha-olho{position:absolute;top:0;right:0;height:100%;width:44px;'
    +   'display:flex;align-items:center;justify-content:center;'
    +   'background:none;border:0;padding:0;margin:0;cursor:pointer;'
    +   'color:currentColor;opacity:.52;transition:opacity .15s}'
    + '.ed-senha-olho:hover{opacity:.95}'
    + '.ed-senha-olho:focus-visible{outline:2px solid currentColor;outline-offset:-3px;border-radius:8px;opacity:1}'
    + '.ed-senha-olho svg{width:19px;height:19px;display:block}'
      /* o olho do Edge/Chrome faria dois olhos no mesmo campo */
    + '.ed-senha > input::-ms-reveal,.ed-senha > input::-ms-clear{display:none}';
    (document.head||document.documentElement).appendChild(e);
  }

  function esconder(inp,btn){
    inp.type='password';
    btn.innerHTML=OLHO_ABERTO;
    btn.setAttribute('aria-label','Mostrar a senha');
    btn.setAttribute('aria-pressed','false');
    btn.title='Mostrar a senha';
  }
  function mostrar(inp,btn){
    inp.type='text';
    btn.innerHTML=OLHO_FECHADO;
    btn.setAttribute('aria-label','Esconder a senha');
    btn.setAttribute('aria-pressed','true');
    btn.title='Esconder a senha';
  }

  function equipar(inp){
    if(!inp||inp.dataset.edSenha)return;
    if(inp.type!=='password')return;
    inp.dataset.edSenha='1';

    /* embrulha o proprio campo, sem tocar no resto do formulario: assim a
       moldura serve para o login, para a gaveta do painel e para qualquer
       campo novo, sem cada tela precisar de CSS proprio */
    var capa=document.createElement('span');
    capa.className='ed-senha';
    inp.parentNode.insertBefore(capa,inp);
    capa.appendChild(inp);

    var btn=document.createElement('button');
    btn.type='button';                  /* senao envia o formulario */
    btn.className='ed-senha-olho';
    btn.tabIndex=0;
    esconder(inp,btn);
    capa.appendChild(btn);

    btn.addEventListener('click',function(ev){
      ev.preventDefault();
      var fim=inp.selectionStart, ini=inp.selectionEnd;
      if(inp.type==='password')mostrar(inp,btn); else esconder(inp,btn);
      /* trocar o type move o cursor para o fim; devolve onde estava, senao
         quem esta no meio da senha perde o lugar */
      try{inp.focus();inp.setSelectionRange(fim,ini);}catch(_){inp.focus();}
    });

    /* some ao enviar: senha legivel na tela depois do envio e papel com a
       senha em cima da mesa */
    var form=inp.form;
    if(form&&!form.dataset.edSenhaForm){
      form.dataset.edSenhaForm='1';
      form.addEventListener('submit',function(){
        var l=form.querySelectorAll('.ed-senha > input[type="text"]');
        for(var i=0;i<l.length;i++){
          var b=l[i].parentNode.querySelector('.ed-senha-olho');
          if(b)esconder(l[i],b);
        }
      });
    }
  }

  function varrer(raiz){
    css();
    var l=(raiz||document).querySelectorAll('input[type="password"]');
    for(var i=0;i<l.length;i++)equipar(l[i]);
  }

  function ligar(){
    varrer(document);
    /* a gaveta do painel e o senha.html montam o HTML depois; sem observar,
       o olho apareceria so nos campos que ja estavam na pagina */
    try{
      new MutationObserver(function(muts){
        for(var i=0;i<muts.length;i++){
          var add=muts[i].addedNodes;
          for(var k=0;k<add.length;k++){
            var n=add[k];
            if(n.nodeType!==1)continue;
            if(n.matches&&n.matches('input[type="password"]'))equipar(n);
            else if(n.querySelectorAll)varrer(n);
          }
        }
      }).observe(document.documentElement,{childList:true,subtree:true});
    }catch(_){}
  }

  if(document.readyState==='loading')
    document.addEventListener('DOMContentLoaded',ligar);
  else ligar();

  window.EDSenha={varrer:varrer};
})();
