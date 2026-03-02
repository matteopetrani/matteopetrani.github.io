# matteopetrani.github.io

Jekyll personal blog with bilingual support (Italian + English).

## Structure

```
it/          # Italian (source of truth)
  _posts/    # Blog posts in Italian
  about.md
  index.md
  now.md
  writings.md

en/          # English (translated from Italian)
  _posts/    # Blog posts in English
  about.md
  index.md
  now.md
  writings.md
```

## Bilingual sync rule

**Italian is the source of truth.** Whenever you create or edit a file under `it/`, you must translate and update (or create) the corresponding English version under `en/` before committing or pushing.

### Page files (`it/*.md` → `en/*.md`)

- Same filename, same frontmatter keys
- Change `permalink: /it/...` → `permalink: /en/...`
- Change `lang: it` → `lang: en`
- The English file also has `original: <filename>` in its frontmatter
- Translate all body content

### Blog posts (`it/_posts/YYYY-MM-DD-slug.md` → `en/_posts/YYYY-MM-DD-slug-en.md`)

- The date prefix stays the same
- Translate the slug to English (e.g. `dopamina.md` → `dopamine.md`)
- Same frontmatter keys; translate `title`, `description`, and any other text fields
- Translate all body content, preserving markdown formatting

### Commit convention

Always include both `it/` and `en/` files in the same commit. Commit message format:

```
<verb>: <short description>

Example: "translate: dopamina post to English"
```

## Deploy

Push to `main` deploys automatically via GitHub Pages.
