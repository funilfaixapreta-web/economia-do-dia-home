/* ============================================================================
   Economia do Dia · o audio do gabarito comentado
   ----------------------------------------------------------------------------
   As gravacoes das questoes moram no SoundCloud e chegaram do sistema antigo
   com o player em tamanhos diferentes: 4.169 no classico de 166px, 214 no
   "visual" de 300px (capa enorme), e alguns de 160, 300 e 60. Na tela da
   questao isso empurrava a revisao para baixo e cada questao tinha uma cara.

   Aqui o player sai SEMPRE no formato mini do SoundCloud (20px de altura):
   play, barra de progresso e titulo numa linha so. A regra vale na exibicao,
   entao o que esta no banco nao muda e uma faixa colada nova ja nasce mini.

     EDAudio.player(url, embed)   -> HTML do player mini, ou null

   Recebe o audio_url e/ou o audio_embed da questao e acha o id da faixa em
   qualquer um dos dois. Se nao for SoundCloud (ou nao tiver id de faixa),
   devolve null e quem chamou usa o que tinha antes.

   Usado pelo simulado.html, app.html (revisao) e adm.html (pre-visualizacao).
   ============================================================================ */
(function(){
  var ALTURA = 20;

  function idDaFaixa(s){
    if(!s) return null;
    s = String(s);
    try { s = decodeURIComponent(s); } catch(e){}
    if(!/soundcloud\.com/i.test(s)) return null;
    var m = s.match(/api\.soundcloud\.com\/tracks\/(\d+)/i);
    return m ? m[1] : null;
  }

  function player(url, embed){
    var id = idDaFaixa(url) || idDaFaixa(embed);
    if(!id) return null;
    var src = 'https://w.soundcloud.com/player/?url='
      + encodeURIComponent('https://api.soundcloud.com/tracks/' + id)
      + '&color=%23d4a437&auto_play=false&hide_related=true&show_comments=false'
      + '&show_user=false&show_reposts=false&show_teaser=false&visual=false';
    /* o mini do SoundCloud escreve o titulo em cinza fixo: no tema escuro ele
       some no fundo preto, por isso a faixa clara em volta */
    return '<div class="ed-audio-mini" style="background:#f6f3ea;border-radius:8px;padding:5px 10px">'
      + '<iframe width="100%" height="' + ALTURA + '" '
      + 'style="display:block;border:0;width:100%;height:' + ALTURA + 'px" '
      + 'scrolling="no" frameborder="no" allow="autoplay" loading="lazy" '
      + 'title="Gabarito comentado em áudio" src="' + src + '"></iframe></div>';
  }

  window.EDAudio = { player: player, idDaFaixa: idDaFaixa, ALTURA: ALTURA };
})();
