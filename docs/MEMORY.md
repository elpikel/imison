# Decision log

Dated decision log: what, why, what was rejected.

- 2026-11-11: Claude kit set up (copied from ether). Repo is a plain Mix library, not a Phoenix app; web and DB rows in `.claude/project.md` point at the host app and the future `dev/` app.
- 2026-11-11: Design adopted from "Imision: architecture and user stories" (`docs/PROJECT.md`). Name is Imision: renamed the `mix new` skeleton from `Imison`/`:imison`. ADRs 0001–0003 accepted; 0004 (built-in login) and 0005 (no hard Oban dependency) proposed until the open decisions are settled.
- 2026-11-11: Tooling: Styler formatter plugin, Credo `--strict` with the ExSlop plugin.
- 2026-11-11: Work tracking: no issue tracker; plans and tasks live in `.claude/work/<slug>/`; `/implement` needs a feature branch off `main`.
- 2026-11-11: Dashboard design added as static mockups in `docs/design/` (`app.css` + one HTML page per screen). LiveViews reuse its markup and class names. `app.css` moved to `priv/static/app.css`, the shipped asset, and the mockups link to it.
- 2026-11-11: Fonts bundled instead of loaded from Google Fonts, so host apps' dashboards make no third-party requests and pass strict CSP. Instrument Sans (variable, 400–700) and JetBrains Mono (400, 600), latin + latin-ext WOFF2 from Fontsource 5.3.0, in `priv/static/fonts/` with their OFL 1.1 licenses, which the OFL requires when redistributing. Rejected: system font stack (loses the design's look).
- 2026-11-11: Backlog in `docs/STORIES.md`: the design's 36 stories with IDs, build order, dependencies and "done when" lines, plus DEV-01 (test database) and DEV-02 (`dev/` host app) as setup. Replaces the story table in `PROJECT.md` so there is one list.
- 2026-11-11: `mix check` alias runs in the test env: `compile --warnings-as-errors --force`, `deps.unlock --check-unused`, `format --check-formatted` (Styler), `credo --strict` (ExSlop), `test`. It stops at the first failure.
