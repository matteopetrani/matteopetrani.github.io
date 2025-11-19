# Minimal Jekyll Blog

Un blog minimale basato su Jekyll, progettato per essere leggero e accessibile.

## Struttura

- `_layouts/`: Template HTML per le pagine.
- `assets/css/`: Stili CSS minimali.
- `_posts/`: Articoli del blog (formato YYYY-MM-DD-titolo.md).
- `index.md`: Homepage.
- `about.md`: Pagina "Chi sono".
- `now.md`: Pagina "Cosa sto facendo".

## Come aggiungere contenuti

### Nuovo Post
Crea un file in `_posts/` con il formato `YYYY-MM-DD-titolo-del-post.md`.
Esempio di contenuto:

```markdown
---
layout: post
title: "Titolo del Post"
date: 2024-03-20 10:00:00 +0100
categories: categoria
---

Testo del post qui...
```

### Nuova Pagina
Crea un file `.md` nella root directory.
Esempio:

```markdown
---
layout: page
title: Titolo Pagina
permalink: /titolo-pagina/
---

Contenuto della pagina...
```

## Installazione Locale

Assicurati di avere Ruby installato.

1. Installa le dipendenze:
   ```bash
   bundle install
   ```

2. Avvia il server locale:
   ```bash
   bundle exec jekyll serve
   ```

## Deploy su GitHub Pages

1. Carica questo repository su GitHub.
2. Vai nelle impostazioni del repository -> Pages.
3. Seleziona il branch `main` (o `master`) come sorgente.
4. Il sito sarà pubblicato automaticamente.
