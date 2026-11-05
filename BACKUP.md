# Stello backup

Stello's library lives in your private iCloud database (the Mac/iPhone apps'
SwiftData + CloudKit store). iCloud keeps it across devices, and the web app
reads it with Apple ID sign-in.

For a local copy, use the Mac app's export (`apple/Stello/Stello/Export/ItemBundleExporter.swift`).

## Supabase-era archive

Supabase was retired on 2026-11-05. The full library at that date (3,605
items, tags, snippets, image paths) is in
`/mnt/project-files/stello/export/stello-library-2026-11-05.json`. Image paths
(`/img/<key>`) are served from R2 by the Worker until the import into iCloud
is done.
