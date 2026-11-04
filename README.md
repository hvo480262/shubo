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

## PMSM fault-diagnosis research

[Explore the project, MATLAB source, Simulink model, and saved simulation evidence](projects/pmsm-fault-diagnosis/README.md).

The public snapshot covers six single-switch and fifteen double-switch configurations, reports both correctness and decision timing, and treats the exploratory sensor-gain prototype separately. It includes a CSV-only reproduction script and documents the limits of the inherited evaluation split.

