# Landing page

Single-page marketing site for OpenWispr. Plain HTML + CSS, no build
step, no JavaScript framework.

## Publishing to GitHub Pages

Two ways to serve this directory on GitHub Pages:

### Option 1: from a subdirectory (recommended)

1. In the GitHub repo, go to **Settings → Pages**.
2. Source: **Deploy from a branch**.
3. Branch: `main`, folder: `/docs` is not what you want here —
   instead, set up a GitHub Actions workflow that copies
   `docs/site/` into the Pages artifact. Example:

   ```yaml
   # .github/workflows/pages.yml
   name: Deploy landing page
   on:
     push:
       branches: [main]
       paths: ['docs/site/**']
   jobs:
     deploy:
       runs-on: ubuntu-latest
       permissions:
         pages: write
         id-token: write
       steps:
         - uses: actions/checkout@v4
         - uses: actions/configure-pages@v4
         - uses: actions/upload-pages-artifact@v3
           with:
             path: docs/site
         - uses: actions/deploy-pages@v4
   ```

### Option 2: move the site to /docs/

If you'd rather skip the Actions workflow, move `docs/site/index.html`
and `docs/site/style.css` up to `docs/index.html` and `docs/style.css`,
then enable GitHub Pages with source = `main` branch, folder = `/docs`.
You'll need to nest the rest of the markdown docs into a subfolder
(e.g. `docs/dev/`) to keep the landing page at the root.

## Local preview

```bash
cd docs/site
python3 -m http.server 8000
# then open http://localhost:8000
```

## What to customize later

- `© 2026 OpenWispr contributors` in `index.html` footer if you want
  a specific copyright holder.
- Hero image / screenshot: currently text-only. Drop a PNG into
  `docs/site/` and reference it in the hero section.
- If you fork to a different org, search-replace
  `github.com/seeknull/openwispr` with your repo URL.
