# Shubo Zhang — Personal Website

An English research portfolio for Shubo Zhang, covering electrical engineering projects, publications, experience, and a printable CV.

## Structure

The static website is in `dist/`:

- `index.html` — introduction and selected work
- `projects.html` — project details
- `publications.html` — papers and patent application
- `cv.html` — printable CV without a phone number

The public contact address is `hvo480262@gmail.com`. The source CV PDF is intentionally excluded from the website because it includes a phone number.

## GitHub Pages

The workflow in `.github/workflows/deploy-pages.yml` deploys `dist/` after a push to `main`. In the repository settings, set **Pages → Build and deployment → Source** to **GitHub Actions**.

All internal links are relative, so the site works at either a repository Pages URL or a custom domain.
