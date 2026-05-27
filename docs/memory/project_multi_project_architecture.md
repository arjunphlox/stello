---
name: Multi-project architecture
description: Arjun's project ecosystem — Tessor, Maree, Phlox Site, Stello — all imported and local-first as of 2026-04-03
type: project
---

Arjun has 4 interconnected projects, all migrated to local-first Claude Code workflow (completed 2026-04-03):

**Tessor** — Design System Workbench. Private repo at HueGrid/Tessor on GitHub. Source of truth for UI components, design tokens. Location: `~/Documents/HueGrid/Tessor/`

**Maree** — SVG pattern generator (React/Vite/Tailwind). Syncs UI layer from Tessor. Location: `~/Documents/HueGrid/Maree/`

**Phlox Site** — Tessor-powered portfolio (bento-grid, 4 pages, WebAuthn admin, markdown content). NOT the same as `arjunphlox/arjunphlox-site` on GitHub. Location: `~/Documents/Personal Projects/Phlox Site/`

**Stello** — Design knowledge base (3294+ items, vanilla JS, Node.js server). Location: `~/Documents/Personal Projects/Stello/`. GitHub: `arjunphlox/stello`

**How to apply:** Tessor integration is planned — design tokens → Stello CSS. Don't introduce a separate design system.
