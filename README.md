# Economia do Dia — Home Portal

Landing page (Home Portal) da plataforma **Economia do Dia**, preparatório para a certificação **CNPI** (CB · CG1 · CT1) e **CFG**.

Site estático de página única (HTML + CSS, sem build), recriado a partir do design handoff. Tema escuro/claro com toggle, e a experiência interativa do professor (Fred) que revela os badges de certificação no hover.

## Rodar localmente
Abra `index.html` no navegador, ou sirva a pasta:

```bash
npx serve .
```

## Deploy
Site 100% estático — qualquer host serve. Na Vercel, faça *Import* deste repositório (sem framework, output = raiz).

## Estrutura
- `index.html` — página completa (A1 Nav → A10 Footer), CSS embutido.
- `assets/fred-idle.png`, `assets/fred-point.png` — imagens do professor (estado neutro / apontando).
