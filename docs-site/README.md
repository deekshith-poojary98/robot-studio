# Robot Studio user guide

Astro + [Starlight](https://starlight.astro.build/) site published to GitHub Pages.

## Local development

```bash
cd docs-site
npm install
npm run dev
```

Open the URL printed in the terminal (usually `http://localhost:4321/robot-studio/`).

## Build

```bash
cd docs-site
npm run build
npm run preview
```

Output is written to `docs-site/dist/`.

## Deploy

Pushing changes under `docs-site/` to `main` runs [`.github/workflows/deploy-docs.yml`](../.github/workflows/deploy-docs.yml).

One-time GitHub setup:

1. Repo **Settings → Pages**
2. Set source to **GitHub Actions**

Site URL (project Pages):  
`https://deekshith-poojary98.github.io/robot-studio/`

## Content

Edit Markdown/MDX under `src/content/docs/`. Sidebar and branding live in `astro.config.mjs`. Theme tokens are in `src/styles/custom.css`.

Internal root-relative links (`/getting-started/...`) are rewritten for the `/robot-studio` base via `starlight-base-path`. For MDX component props (`LinkCard` `href`), use the `withBase()` helper on the homepage.
