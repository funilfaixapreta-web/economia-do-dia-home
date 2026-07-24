/* Faixa de redes sociais (logos) no rodape, compartilhada pelas paginas do site.
   Injeta a linha de icones em qualquer footer/.foot que ainda nao tenha redes. */
(function(){
  var CSS='.edsoc{display:flex;gap:8px;justify-content:center;margin-top:16px}'
    +'.edsoc a{width:34px;height:34px;border-radius:9px;border:1px solid var(--border,rgba(255,255,255,.08));background:var(--overlay-soft,rgba(255,255,255,.05));display:inline-flex;align-items:center;justify-content:center;color:var(--muted,#8A94A2);text-decoration:none}'
    +'.edsoc a:hover{color:var(--gold-deep,#E6BE54);border-color:var(--gold-soft-bd,rgba(212,164,55,.3))}'
    +'.edsoc svg{width:17px;height:17px}';
  var st=document.createElement('style');st.textContent=CSS;document.head.appendChild(st);
  var IG='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2.5" y="2.5" width="19" height="19" rx="5.5"/><circle cx="12" cy="12" r="4"/><circle cx="17.6" cy="6.4" r="1.1" fill="currentColor" stroke="none"/></svg>';
  var YT='<svg viewBox="0 0 24 24" fill="currentColor"><path d="M23 12s0-3.2-.4-4.7a2.5 2.5 0 0 0-1.8-1.8C19.3 5 12 5 12 5s-7.3 0-8.8.5A2.5 2.5 0 0 0 1.4 7.3C1 8.8 1 12 1 12s0 3.2.4 4.7a2.5 2.5 0 0 0 1.8 1.8C4.7 19 12 19 12 19s7.3 0 8.8-.5a2.5 2.5 0 0 0 1.8-1.8C23 15.2 23 12 23 12zM9.8 15.3V8.7l5.7 3.3-5.7 3.3z"/></svg>';
  var HTML='<a href="https://www.instagram.com/economiadodia_" target="_blank" rel="noopener" title="Instagram" aria-label="Instagram">'+IG+'</a>'
    +'<a href="https://www.youtube.com/@economiadodia6682" target="_blank" rel="noopener" title="YouTube" aria-label="YouTube">'+YT+'</a>';
  function run(){
    var foots=document.querySelectorAll('footer, .foot');
    Array.prototype.forEach.call(foots,function(f){
      if(f.querySelector('.social')||f.querySelector('.edsoc'))return;
      var wrap=f.querySelector('.wrap')||f;
      var row=document.createElement('div');row.className='edsoc';row.innerHTML=HTML;
      wrap.appendChild(row);
    });
  }
  if(document.body)run();else document.addEventListener('DOMContentLoaded',run);
})();
