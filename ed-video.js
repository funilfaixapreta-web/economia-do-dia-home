/* ============================================================================
   Economia do Dia · o video da aula
   ----------------------------------------------------------------------------
   Duas coisas, usadas pelo app.html (aluno) e pelo adm.html (pre-visualizacao
   do painel). Antes cada um tinha a sua copia: embutir() aqui e ytEmbedUrl()
   lá, o mesmo regex escrito duas vezes -- e so um dos dois recebia correcao.

     EDVideo.embutir(url)      link -> endereco que da para por num iframe
     EDVideo.seguro(html)      codigo de incorporacao -> iframe confiavel

   POR QUE seguro() EXISTE
   O campo "Vídeo por incorporação" recebe HTML colado a mao, e os dois lados
   faziam innerHTML com ele, cru. Em producao isso e ruim por dois motivos:

     1. um script no meio do que foi colado roda na pagina do aluno, com a
        sessao dele. O campo hoje so e gravavel por admin (publicar_conteudo
        exige eh_admin), entao nao e brecha aberta -- mas e uma brecha a uma
        conta de distancia, e nao custa fechar;
     2. colar errado quebrava a tela em silencio. Copiar a pagina inteira em
        vez do iframe, ou o iframe sem allowfullscreen, dava player preto ou
        video que nao abre em tela cheia, sem dizer nada a ninguem.

   seguro() resolve os dois: pega SO o primeiro <iframe> (ou <video>), mantem
   uma lista curta de atributos, exige https, e garante a tela cheia. O que
   nao for isso e descartado e a funcao devolve null -- e quem chamou mostra
   um aviso em vez de um buraco.

   Serve para qualquer player que entregue iframe: VEED, Vimeo, YouTube,
   Panda, Bunny, Loom. Nenhum deles precisa de tratamento proprio.
   ============================================================================ */
(function(){

  /* ------------------------------------------------------------- por LINK --
     Converte o endereco que a pessoa copia da barra do navegador para o
     endereco de incorporacao do player. Só YouTube e Vimeo: os dois tem
     formato publico e estavel.

     Para os outros (VEED incluso) nao da para adivinhar o formato, e adivinhar
     errado produz player preto. Entao devolve null, e quem chamou cai para
     <video src>, que funciona com arquivo direto (.mp4) e falha de forma
     visivel com pagina de compartilhamento -- que e o certo: o caminho desses
     players e o campo de incorporacao, nao o de link.                       */
  function embutir(u){
    u=String(u||'');
    var y=u.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/)([\w-]{6,})/);
    if(y)return 'https://www.youtube.com/embed/'+y[1];
    var v=u.match(/vimeo\.com\/(?:video\/)?(\d+)/);
    if(v)return 'https://player.vimeo.com/video/'+v[1];
    return null;
  }

  /* Um link de pagina nao e um arquivo de video. Serve para o painel avisar
     "isso aqui vai dar player preto" ANTES de publicar, em vez de o aluno
     descobrir. .mp4/.webm/.ogg/.mov tocam direto no <video>; o resto, nao. */
  function pareceArquivoDeVideo(u){
    return /\.(mp4|webm|ogg|ogv|mov|m3u8)(\?|#|$)/i.test(String(u||''));
  }

  /* --------------------------------------------------- por INCORPORACAO --
     Atributos que podem passar. Tudo fora desta lista cai, inclusive
     on* (onload, onerror) -- que e por onde entraria script sem tag script. */
  var OK_IFRAME=['src','title','allow','allowfullscreen','loading','referrerpolicy','name'];
  var OK_VIDEO =['src','poster','controls','preload','playsinline','muted','loop'];

  function seguro(html){
    html=String(html||'').trim();
    if(!html)return null;

    /* O parser do navegador faz o trabalho pesado e nao executa nada: um
       <template> nao roda script nem busca imagem. Fazer isto com regex
       seria fragil justamente nos casos que importam. */
    var tpl=document.createElement('template');
    tpl.innerHTML=html;

    var el=tpl.content.querySelector('iframe,video');
    if(!el)return null;                 /* colou outra coisa: avisa, nao finge */

    var tag=el.tagName.toLowerCase();
    var permitidos=(tag==='iframe')?OK_IFRAME:OK_VIDEO;

    var limpo=document.createElement(tag);
    for(var i=0;i<el.attributes.length;i++){
      var a=el.attributes[i];
      if(permitidos.indexOf(a.name.toLowerCase())>=0)
        limpo.setAttribute(a.name,a.value);
    }

    var src=limpo.getAttribute('src')||'';
    /* src vazio ou javascript:/data: nao entra. Exigir https tambem evita o
       aviso de conteudo misto, que no Chrome simplesmente bloqueia o video. */
    if(!/^https:\/\//i.test(src))return null;

    if(tag==='iframe'){
      /* tela cheia e o minimo para assistir aula; varios players entregam o
         iframe sem isso e o aluno fica preso num retangulo pequeno */
      limpo.setAttribute('allowfullscreen','');
      var allow=limpo.getAttribute('allow')||'';
      if(allow.indexOf('fullscreen')<0)
        limpo.setAttribute('allow',(allow?allow+'; ':'')+'fullscreen; picture-in-picture');
      if(!limpo.getAttribute('loading'))limpo.setAttribute('loading','lazy');
      if(!limpo.getAttribute('title'))limpo.setAttribute('title','Vídeo da aula');
    }else{
      limpo.setAttribute('controls','');
      if(!limpo.getAttribute('preload'))limpo.setAttribute('preload','metadata');
    }
    /* largura e altura saem: o CSS do player manda (100% dentro de 16/9).
       Deixar os valores fixos do player quebra no celular. */
    limpo.removeAttribute('width');limpo.removeAttribute('height');

    return limpo.outerHTML;
  }

  /* De onde o player tira o host, so para o painel poder dizer "VEED" em vez
     de repetir a URL inteira. Nao decide nada -- e rotulo de tela. */
  function host(html){
    var m=String(html||'').match(/src\s*=\s*["']https:\/\/([^\/"']+)/i);
    return m?m[1].replace(/^www\./,''):null;
  }

  window.EDVideo={embutir:embutir, seguro:seguro, host:host,
                  pareceArquivoDeVideo:pareceArquivoDeVideo};
})();
