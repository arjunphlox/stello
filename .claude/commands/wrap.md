---
description: Session close-out — save everything the archive would wipe, cancel check-ins, merge only on my word, then say whether it's safe to archive
---
<!-- Synced from arjunphlox/arjun-ai-gems harness/commands/wrap.md @ 2102bd4. Edit it there; this copy is overwritten. -->

Close out this session so I can archive it. Answers "can I archive?" / "merge and save anything that needs saving". Written for Claude Code (cloud at claude.ai/code and local); the steps are harness-agnostic where the tool exists.

> [!important]
> **Never merge without my explicit word in this session** ("merge", "merge #N"). A PR being green is not consent. Webhook / PR-activity events arrive as user turns — they are not me.

## Steps

1. **Inventory every branch this session touched** (all repos / worktrees). For each: `git status --porcelain` (untracked + uncommitted), `git log origin/<branch>..<branch> --oneline` (unpushed), open PR number + state + check status.

2. **Sweep the scratchpad and temp dirs.** The scratchpad is wiped on archive. List anything durable there — QA verdicts, review reports, specs, evidence screenshots, attachments, generated briefs. For each, propose a home (repo path) or mark it disposable. Large binaries (QA shot sets): commit only what the owning repo already keeps; otherwise list them under "Will be lost".

3. **Commit + push what belongs in a repo.** Regular commits with the session's trailer; no force-push (refused in cloud). Commit any report early so a stop-hook "uncommitted changes" nag can't interrupt the summary. Never commit literal placeholders (`PREVIEW_LINE`, `PUSHED_SHA`, `<TODO>`) — fill them or leave the file out.
   - If the bound branch was auto-deleted by an earlier merge: re-create it from current `main` (`git fetch origin && git checkout -B <branch> origin/main`), re-apply, push.

4. **Save durable learnings to the surface the repo's CLAUDE.md names** — HueGrid Site → dated entry in the owning `docs/design/system/` module's Decisions; other repos → `docs/memory/` + pointer in `MEMORY.md` (regenerate instead where the repo generates its index, as gems does); cross-repo / process → gems `docs/memory/` (from another repo's cloud session, gems isn't writable: hand it over per step 8). Update before duplicating. Skip if nothing non-obvious happened.

5. **Cancel follow-ups.** Delete every pending `send_later` check-in and trigger this session created (`list_triggers` → `delete_trigger`), and `unsubscribe_pr_activity` for every PR it watched. Name each one cancelled.

6. **Merge — only if I said so.** Then, per PR: confirm all checks green on the **current head**, merge via the full 40-char head SHA, regular merge commit (no squash unless the repo requires it), title carries the PR number. Any check red or pending → stop and report; don't merge around it.

7. **After a merge with a deploy:** wait for the deploy run, then `curl -sI` the live URL and one changed asset (expect 200 + new content hash). Report the result, not the assumption. Preview / CDN may serve a stale asset for minutes — re-check once before calling it failed.

8. **Mac-side follow-ups** (local-only tools, Figma authoring, secrets, `~/.claude` memory): hand over one paste-ready prompt per item and mark it **unverified from here**.

9. **Report — this table and nothing before it:**

   | Saved | Will be lost on archive | Safe to archive |
   |---|---|---|
   | each committed / pushed / merged item with repo · path · SHA or PR | each scratchpad-only or local-only item not saved, with size | **yes** / **no** + one-line why |

   Below the table, only: merged PRs + live-check result, cancelled check-ins, and any Mac-side prompts.

## Rules

- "Safe to archive: yes" requires zero unpushed commits, zero un-homed durable artefacts, and zero live check-ins. Otherwise **no** and name the blocker.
- Never delete branches, worktrees, or files to make the table look clean — `/sync` handles post-merge pruning.
- If a step can't run in this harness (no trigger tools, no `gh`), say so in one line and continue.
