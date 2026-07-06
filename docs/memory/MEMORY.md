# Project Memory — Stello

Portable, version-controlled, project-scoped memory. Read at session start; append durable project lessons here. Account-level/personal memory stays in ~/.claude and is never committed.

## Index

| Entry | Summary |
|---|---|
| [project_native_apple_app.md](project_native_apple_app.md) | Native SwiftUI app under apple/Stello — local-first SwiftData+CloudKit, on-device AFM enrichment, XcodeGen harness, macOS inset-glass header (Sketch pattern), seed dedupe + broken-shell ItemImage gotchas; quick-wins A–E shipped Jul 2026; timeline/header frozen until explicit OK (failed nudge session reverted) |
| [project_capture_pipeline.md](project_capture_pipeline.md) | Stello's capture flow as of PR #8 (Apr 2026) — capture opens the Item Panel immediately, enrichment streams candidates + screenshots into the same panel, user curates which images/snippets/reasons to keep |
| [project_desktop_context.md](project_desktop_context.md) | Local Mac context daemon (`com.stello.context`, port 8766) — watcher folder + Sketch + Safari → SQLite `/related`; localhost-only `desktop-context.js` stub; cards UI deferred (Jun 2026) |
| [project_login_auth_surface.md](project_login_auth_surface.md) | How login.html, the view-transition to /, the settings logout, the password reset flow, the in-flight error UX, and Resend custom SMTP are wired. Covers the cross-document morph, GSAP fallback for no-VT browsers (Firefox), ?welcome=1 stagger, in-flight button label + shake animation, pinned logout pattern, client-side password reset (login.html "Forgot?" + reset-password.html), and Supabase → Resend SMTP routing for the public signup flow. PR #4 (login morph) → PR #9 (password reset) → PR #10 (in-flight UX + Resend SMTP). |
| [project_multi_project_architecture.md](project_multi_project_architecture.md) | Arjun's project ecosystem — Tessor, Maree, Phlox Site, Stello — all imported and local-first as of 2026-04-03 |
| [project_multi_tenant_surface.md](project_multi_tenant_surface.md) | Stello is fully multi-tenant on Vercel+Supabase — Supabase is the ONLY data source, no filesystem fallbacks, legacy server.js + Python scripts retired (Apr 2026 PR #5) |
| [project_panel_slider_cover.md](project_panel_slider_cover.md) | The panel's image slider separates "what's previewed" from "what's the cover" (grid thumb). Reasoning + exact DOM/JS contract for the next time this is touched |
| [project_radix_theme_system.md](project_radix_theme_system.md) | How theme.css, ThemeManager, and accent/mode switching work. Read before touching colors, header, or theme UI. |
| [project_side_panel_architecture.md](project_side_panel_architecture.md) | How PanelManager, the flex-column masonry, the JS-driven --grid-cols, and the panel transitions fit together as of PR #11 (May 2026). Read before touching index.html / app.js / style.css. |
| [project_supabase_storage_rls.md](project_supabase_storage_rls.md) | Stello's item-images bucket policies live in schema.sql + migrations/2026-04-16-storage-policies.sql; the UPDATE half is easy to miss and causes silent "new row violates RLS" failures |
| [project_vision_enrichment.md](project_vision_enrichment.md) | Enrichment lives in src/routes/enrich.js (vision core `enrichItem`) + reprocess.js (`reprocessItem`) + a server-side `drainEnrichment` cron/trigger. Needs an Anthropic key (env.ANTHROPIC_API_KEY or user_settings) or vision silently no-ops — the post-CF-migration dead-vision cause. Status machine + drain caveats (Jun 2026, PR #22) |
