---
name: Stello login + auth surface architecture
description: How login.html, the view-transition to /, the settings logout, the password reset flow, the in-flight error UX, and Resend custom SMTP are wired. Covers the cross-document morph, GSAP fallback for no-VT browsers (Firefox), ?welcome=1 stagger, in-flight button label + shake animation, pinned logout pattern, client-side password reset (login.html "Forgot?" + reset-password.html), and Supabase → Resend SMTP routing for the public signup flow. PR #4 (login morph) → PR #9 (password reset) → PR #10 (in-flight UX + Resend SMTP).
type: project
originSessionId: f0a1e58c-ad51-4fde-bfd9-8c9c2eddcfae
---
**Login page shape** (`login.html`):
The login page reuses the same `.header` rule as the app — `<header class="header login-header" data-mode="choose">`. The shared class picks up `view-transition-name: app-header` so the browser can morph between `/login.html` and `/` automatically. `.login-header` overrides with `flex: 1; min-height: 0; padding: 24px` to make it fill the viewport instead of being a 120px sticky bar.

Layout is driven by `data-mode` on the header (`choose` vs `email`):
- Choose mode → two buttons (Apple/Email) bottom-right
- Email mode → inline `[email][password][Sign in]` row at the same spot
- Top-left `← Sign in options` back link, top-right `Create account` toggle (both absolutely positioned, only visible in email mode)
- Wordmark bottom-left, superscript cycles poetic verbs (wander, linger, gather, savor…)

**Mobile login layout** (container-query at 640px):
`.login-header .header-row` stacks to column; h1 grows to 100% width with a 1px divider (`border-bottom: color-mix(accent-contrast, 15%, transparent)`) and 24px above/below. Controls keep their 36px height via `flex: 0 0 auto` because the form's `flex: 1` would otherwise collapse them in column mode.

**Generic header stack breakpoint** is 200px, not 520px (dropped in PR #4). The Stello wordmark + 3 icon buttons fit comfortably on all real phone widths. Only a pathological 3-panel squeeze would trigger column stacking in the main app.

**Cross-document header morph:**
`@view-transition { navigation: auto }` + shared `view-transition-name: app-header` on `.header` morphs the header between pages automatically. Custom timing via `::view-transition-old(app-header)` / `::view-transition-new(app-header)` at 0.275s (halved from 0.55s in a later commit). No JS orchestration — just navigate and it works.

**GSAP fallback for no-VT browsers** (added post-PR #4, currently on main):
Firefox and older Chromium don't support cross-document view transitions, so the morph is backed up with a GSAP 3.12.5 timeline (loaded from jsDelivr, matches the Supabase CDN pattern).
- **Synchronous `<head>` gate** in `index.html` flips `html.arriving-from-login` before first paint when `?welcome=1` is set AND `!(CSS.supports('(view-transition-name: none)') && 'onpagereveal' in window)`. Combined check is stronger than either alone — Chrome 126+/Safari 18.2+ ship both; Firefox ships neither.
- **CSS hero-state block** near `.header` paints the compact sticky bar in the login-hero footprint (`height: calc(100vh - 48px)`, relative, 24px padding) while the class is present.
- **`runLoginArrivalFallback()`** in `app.js` (defined just above DOM refs, called from the `?welcome=1` block in `init()`) measures the natural compact height by briefly removing the class, then tweens header height+padding over 275ms and body opacity 0→1 over 225ms in parallel — identical timings to the native `::view-transition-*`. `onComplete` does `gsap.set([header, body], { clearProps: 'all' })` and removes the class so sticky behaviour resumes.
- Reduced-motion OR missing-gsap both short-circuit to an instant snap (class removed, no timeline created).
- Runs *before* `document.body.classList.add('just-logged-in')` so the stagger timers tick against the hero state. Stagger plays through the body fade on the fallback path — acceptable, not perfect.

**Debugging gotcha:** the Claude Code preview panel sets `document.hidden: true`, which pauses GSAP's RAF ticker. Tweens initialize but never advance. Verified the fallback by scrubbing `timeline.progress(0.5)` and `progress(1)` manually — real browsers drive it normally.

**Post-login stagger reveal:**
`login.html` sign-in success → `window.location.href = '/?welcome=1'`. `api/auth-callback.js` (Apple OAuth) → `res.writeHead(302, { Location: '/?welcome=1' })`. `app.js init()` reads `URLSearchParams`, adds `body.just-logged-in` class, strips the param via `history.replaceState`, then removes the class after 900ms. CSS cascades via `--idx` custom property applied per-card in `renderGrid()`; delays are 60/90/110ms for chrome + 150ms+30ms*idx for cards (cap 8). `prefers-reduced-motion` disables it entirely.

**Login error line:**
The `<p class="login-error">` lives INSIDE the form (not as a sibling), absolute-positioned with `bottom: calc(100% + 6px); right: 0; margin: 0`. Takes no flow space → form stays pinned to the same bottom Y as the login-options row in choose mode. Appears above the form when populated without shifting anything. Sized at `0.875rem / weight 500 / #e5484d` for legibility (was 0.8rem in PR #4–#9).

**In-flight + error-visibility UX** (PR #10, Apr 2026):
The submit handler swaps the button label to `Creating account…` / `Signing in…` while the request is in flight, restores the idle label on completion, and replays a `.shake` keyframe animation on every error so consecutive failures still register. `showError(text, accent)` helper toggles the class off, forces a reflow via `void $error.offsetWidth`, then re-adds the class — lets the animation re-fire without `requestAnimationFrame` plumbing. Triggered after a real-world bug where Supabase's default SMTP silently 429'd signups and the user saw "button disables, nothing happens" — the error string was reaching the DOM but the 0.8rem right-aligned banner was easy to miss.

**Sign-out path:**
`supabase-client.js#signOut` does `auth.signOut()` then `window.location.href = '/login.html'` — triggers the same view-transition in reverse (app header → login header). The Log out button lives in the `#tpl-settings` template at the bottom of the settings panel body, styled `.settings-footer` with `margin: auto -16px -16px; padding: 16px; border-top: 1px solid var(--border)`. `margin-top: auto` absorbs remaining space in the flex-column `.panel-body`; negative side margins cancel the panel-body padding so the divider bleeds edge-to-edge. Red `#e5484d` outline matches the existing error color — no new palette entry.

**Font self-hosting quirk** (`server.js`):
`server.js` uses Node's default URL parsing which doesn't decode pathnames, so a file named `Aribau Grotesk Regular.otf` requested as `Aribau%20Grotesk%20Regular.otf` 404s (the server tries to open a file with literal `%20` chars). Solution: keep font filenames kebab-case (`aribau-grotesk-regular.otf`). Lives in `fonts/` with `@font-face` declarations at the top of `style.css`. `.otf`/`.ttf` added to the MIME map at `server.js:28`.

**Apple icon caveat:**
Phosphor's apple-logo-fill is a stylized silhouette with stem notches and no leaf/bite — at 16px it reads as a bean. Use the canonical bitten-apple mark (Simple Icons path) on the Sign in with Apple button instead.

**Password reset flow** (Apr 2026, PR #9):
Fully client-side via `auth.resetPasswordForEmail` + `auth.updateUser` — adds zero serverless functions, which matters because we're at the 12-fn Hobby cap. `supabase-client.js` exposes `requestPasswordReset(email)` and `updatePassword(newPassword)` thin wrappers.

- **Trigger** — small "Forgot?" ghost-link button between Password and Sign in on `login.html`. Hidden in sign-up mode (toggled via `$forgot.style.display` in the sign-in/sign-up switch handler). Reuses the floating `.login-error` slot to surface "Check your email for a reset link" in `--accent-contrast` color (same pattern as the sign-up confirmation toast).
- **Landing** — `reset-password.html` mirrors login.html's header layout (random accent on each load, Stello wordmark, top-left back link). The back link is an `<a>` here (not a `<button>` like login.html), so `text-decoration: none` lives in the shared `.login-back-link` rule to prevent the default underline bleeding through.
- **Recovery hash handling** — supabase-js auto-parses the URL hash on init and emits a `PASSWORD_RECOVERY` auth event. Listen via `auth.onAuthStateChange`, then enable submit. There's a 600ms `setTimeout` fallback that checks for an existing session and surfaces "This reset link is invalid or has expired" if neither path materialized — better than a silently-disabled form for users who land on the page directly.
- **Required Supabase config** — the reset-link redirect URL must be allowlisted in Authentication → URL Configuration → Redirect URLs. Site URL is `https://stello.arjunphlox.com`, allowlist uses wildcard entries `https://stello.arjunphlox.com/**` and `http://localhost:8080/**` (one wildcard covers `/reset-password.html`, `/api/auth-callback`, `/?welcome=1` in a single rule). Without it the email's link won't resolve.
- **What "Invalid login credentials" actually meant** — the lockout that triggered this PR turned out to be a plain password mismatch, not the legacy-JWT-keys issue from `reference_supabase_key_migration.md`. Worth keeping the JWT-keys hypothesis in the diagnostic checklist, but the more boring "user forgot the password" was the real cause.

**Auth email delivery — Resend custom SMTP** (PR #10, Apr 2026):
Supabase Auth routes confirmation/reset/magic-link emails through Resend, NOT the Supabase default SMTP. The default SMTP is capped at ~4 emails/hour project-wide, which silently 429'd public signups with `over_email_send_rate_limit` once any handful of users tried to sign up.

- **Sender** — `Stello <noreply@stello.arjunphlox.com>`. The `stello.arjunphlox.com` domain is verified in Resend (DNS SPF/DKIM/MX records).
- **SMTP creds** — host `smtp.resend.com`, port `465`, username `resend`, password = a send-only Resend API key. **Lives only in Supabase's dashboard** (Authentication → Emails → SMTP Settings). Never committed to the repo or any `.env`.
- **First-line diagnostics for "signup is broken"** — (1) Resend dashboard → Logs (any send failures, bounces, suppressions); (2) Supabase Auth → Logs (was the email even attempted?); (3) `client.auth.signUp` directly in a browser console against the project — if it returns `{ data: { user: null }, error: { code: 'over_email_send_rate_limit' } }`, SMTP got reverted to default; (4) Resend domain verification status (pending/failing DNS revokes the sender).
- **Key rotation** — when an API key is exposed (e.g. pasted into chat for Claude to use), regenerate in Resend → API Keys, paste the new value into Supabase SMTP password field, save. The Supabase dashboard accepts the change without restarting Auth.
