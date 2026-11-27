# Project Memory — Stello

Portable, version-controlled, project-scoped memory. Read at session start; append durable project lessons here. Account-level/personal memory stays in ~/.claude and is never committed.

## Index

| Entry | Summary |
|---|---|
| [project_native_apple_app.md](project_native_apple_app.md) | Native SwiftUI app under apple/Stello — local-first SwiftData+CloudKit, on-device AFM enrichment, JSON .xcproj project (XcodeGen retired 2026-11-05), macOS inset-glass header (Sketch pattern), seed dedupe + broken-shell ItemImage gotchas; quick-wins A–E shipped Jul 2026 + PR #30 fix round (cached-@State staleness trap, `.task(id:)` over `.onAppear` in persistent panels, in-memory-only screenshot fixtures, structural classifier signals); timeline/header frozen until explicit OK (failed nudge session reverted) |
| [project_desktop_context.md](project_desktop_context.md) | Local Mac context daemon (`com.stello.context`, port 8766) — watcher folder + Sketch + Safari → SQLite `/related`; localhost-only `desktop-context.js` stub; cards UI deferred (Jun 2026) |
| [project_panel_slider_cover.md](project_panel_slider_cover.md) | The panel's image slider separates "what's previewed" from "what's the cover" (grid thumb). Reasoning + exact DOM/JS contract for the next time this is touched |
| [project_radix_theme_system.md](project_radix_theme_system.md) | How theme.css, ThemeManager, and accent/mode switching work. Read before touching colors, header, or theme UI. |
| [project_side_panel_architecture.md](project_side_panel_architecture.md) | How PanelManager, the flex-column masonry, the JS-driven --grid-cols, and the panel transitions fit together as of PR #11 (May 2026). Read before touching index.html / app.js / style.css. |
| [project_vision_enrichment.md](project_vision_enrichment.md) | Enrichment lives in src/routes/enrich.js (vision core `enrichItem`) + reprocess.js (`reprocessItem`) + a server-side `drainEnrichment` cron/trigger. Needs an Anthropic key (env.ANTHROPIC_API_KEY or user_settings) or vision silently no-ops — the post-CF-migration dead-vision cause. Status machine + drain caveats (Jun 2026, PR #22) |
| [feedback_working_contract.md](feedback_working_contract.md) | Standing working contract: ask before gaps bite, delegate execution by task shape (Opus 5.5 / Sonnet 5.5 / Haiku 4.5 / Grok 4.7 closed-scope only), echo exact model ids; Grok brief rules summary (2026-10-05) |
