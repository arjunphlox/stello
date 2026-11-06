---
name: project_icloud_data
description: Since Nov 2026 Stello's only data home is iCloud — apps via SwiftData+CloudKit, web via CloudKit JS + Apple ID, web writes through the StelloInbox zone; Supabase removed
type: project
---

**Decided 2026-11-05 (Arjun).** Supabase (auth, Postgres, RLS) and the Worker API were removed. The library lives only in the user's private iCloud database.

- **Apps (Mac/iPhone):** SwiftData + CloudKit, container `iCloud.com.arjunphlox.Stello` (IDs renamed from `phloxpage` the same day, so this container started empty). Login = the device's iCloud account.
- **Web:** `icloud-client.js` (CloudKit JS). Apple ID sign-in via CloudKit's own button, forwarded from Stello's styled button (login.html, Settings → Sign out). Reads the SwiftData mirror zone `com.apple.coredata.cloudkit.zone` with `fetchRecordZoneChanges` + a sync token, cached in IndexedDB (`stello-icloud`). Record types `CD_Item`, `CD_Tag`, `CD_ItemImage`, `CD_Snippet`; fields `CD_<attribute>`; to-one `CD_item` holds the parent's record name. Image bytes load lazily per card (`CD_data` inline or `CD_data_ckAsset`).
- **Web writes never touch CD_ records** (SwiftData's layout is internal). Saves/edits/deletes/re-tag go to a `StelloInbox` record in the `StelloInbox` zone (`action` + JSON `payload` + optional `image` asset). `apple/Stello/Stello/Sync/WebInboxProcessor.swift` subscribes to the zone (silent push, `CKRecordZoneSubscription`), applies each request through CaptureService/EnrichmentService, then deletes it. Web shows "Processing…" cards until the real item syncs back.
- Images are matched app-side by fingerprint (width, height, source, role) since SwiftData hides CloudKit record names.
- **Worker:** static files + legacy `/img/*` from R2 only. `/img` + R2 stay until the Supabase export (`/mnt/project-files/stello/export/stello-library-2026-11-05.json`, 3,605 items) is imported into iCloud.
- CloudKit JS needs an API token from CloudKit Console (sign-in callback postMessage; origins = the Worker URL + localhost) pasted into `icloud-client.js`. Environment is `development` until the schema is deployed to Production.

**Why:** one Apple-first stack with nothing to run server-side; the apps already enrich on-device.
**How to apply:** don't reintroduce a server database or Supabase. Web features that change data must go through the inbox and need a matching handler in WebInboxProcessor.
