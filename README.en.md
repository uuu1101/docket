*[한국어](README.md) · English*

# Docket

A macOS dashboard that lives in the menu bar. The Jira tickets assigned to you — and the
Slack threads, pull requests, Figma files and comments attached to them — in one place,
with status changes done right there.

To install without building, see [INSTALL.en.md](INSTALL.en.md). Licensed under
[MIT](LICENSE).

## Running

You need [Tuist](https://tuist.dev) (`brew install tuist` or `mise install tuist`).

```bash
tuist generate          # creates Docket.xcworkspace
open Docket.xcworkspace
```

Run the `Docket` scheme in Xcode. It shows up in the menu bar only, with no Dock icon
(`LSUIElement`). Tests are ⌘U on the `DocketKit` scheme.

Set **your own team** under Signing & Capabilities in Xcode and keychain access survives
rebuilds. Without it the ad-hoc signature changes every build, and each one asks for token
access again.

## Setup

### Jira

1. https://id.atlassian.com → Security → **Create API token**
2. In the app's settings → Jira tab, enter the site address
   (`https://your-team.atlassian.net`), your email and the token
3. Confirm with **Test connection**

### Which tickets to show

Pick in Settings → General.

| Choice | JQL |
|---|---|
| Assigned to me, open *(default)* | `assignee = currentUser() AND statusCategory != Done` |
| Assigned to me · include last 7 days done | `assignee = currentUser() AND (statusCategory != Done OR resolutiondate >= -7d)` |
| Reported by me, open | `reporter = currentUser() AND statusCategory != Done` |
| Watching | `watcher = currentUser() AND statusCategory != Done` |
| Custom | JQL you write yourself |

Every query gets `ORDER BY updated DESC`. Picking a preset shows its actual JQL below,
and switching to custom starts you from that JQL instead of an empty box. **Validate
query** fetches a single result to tell a valid query from a typo — so a typo cannot
quietly empty the dashboard.

An empty custom query falls back to the default preset. An empty JQL is never sent.

### GitHub

Needed for the pull request buttons. Leave it out and only that part stays empty.

1. github.com → Settings → Developer settings → **Personal access tokens**.
   Reading private repositories takes the `repo` scope.
2. In settings → GitHub tab, enter the token and the repositories (`owner/repo`), then
   **Test connection**

A pull request is found when the ticket key appears in **its title or its branch name**.
The app lists each configured repository's recent pull requests once and matches every
ticket against that one list, which also keeps the token scoped to exactly those
repositories.

### Slack

Threads are read with a **user token** — your own permissions, no bot to invite into
channels. Authentication is PKCE OAuth: there is no client secret, so there is no backend
either.

The repository ships with a default Slack app's client ID, so **most people just press
Connect Slack in settings → Slack tab.** Follow the steps below only when your workspace
blocks that app or you want to run your own.

1. https://api.slack.com/apps → **Create New App** → **From a manifest** → pick your
   workspace → paste `slack-app-manifest.yml`.
2. Open **OAuth & Permissions** and check three things yourself — the manifest sometimes
   fails to apply `redirect_urls`:
   - **PKCE is on.** With it off, Slack refuses to even save an `http://localhost`
     redirect. Turn PKCE on **first**, then add the redirects.
   - **All three Redirect URLs are present.** Add any that are missing and press
     **Save URLs**.
     ```
     http://localhost:53682/slack/callback
     http://localhost:53683/slack/callback
     http://localhost:53684/slack/callback
     ```
   - **All seven User Token Scopes are present** — the manifest sometimes fails to apply
     `scopes`: `channels:history`, `groups:history`, `im:history`, `mpim:history`,
     `users:read`, `channels:read`, `groups:read`. Each conversation type needs its own
     history scope — without one, threads of that type cannot be read. `search:read` is
     no longer used.

With PKCE on, Slack issues **rotating tokens even when `token_rotation_enabled` is
`false`** (the docs describe this only for custom URI schemes, but PKCE itself is the
trigger). The app is built around that — tokens live about 12 hours, renew 5 minutes
before expiry, and a rejected request renews once and retries. The refresh token lives in
the Keychain.

Only if Slack demands a `client_secret` for renewal, enter it under Slack tab →
**Advanced**. It is stored in the Keychain only and never ships in the binary.

3. Put **Basic Information → Client ID** into `SlackClientID` in `Project.swift`, run
   `tuist generate` and rebuild. The client ID is not a secret.
4. Docket settings → Slack tab → **Connect Slack**. Approve in the browser and it is done.

Do not press "Install to Workspace" on the app dashboard — the OAuth flow in step 4
installs it.

**Redirects for public distribution**: Slack requires every redirect URL to be https
before public distribution can be enabled. The distributed app therefore registers the
static page in `docs/slack-callback/` (hosted on GitHub Pages) and carries its address in
`SlackRedirectURL` in `Project.swift`. The page just reads the loopback port off the
state's suffix and bounces the browser to `http://localhost:<port>`, storing nothing.
Leave `SlackRedirectURL` empty and the browser comes straight back to localhost — the
combination a personal app made from the manifest uses.

The token carries your own permissions, so only public channels plus the private channels
and DMs you are in can be read. If OAuth is impossible in your environment, an `xoxp-`
token can be entered directly under Slack tab → **Advanced**.

Jira works fine with Slack never configured.

## Behavior

- **Refresh**: automatic on the configured interval (10 minutes by default), immediate via
  the ↻ button in the header.
- **Changing status**: click the status badge in the detail and the moves the workflow
  allows appear; picking one applies immediately. A move that demands required fields such
  as a resolution cannot finish here, so it defers to Jira with an explanation. A status
  you changed yourself is never counted as an unseen change.
- **Description and comments**: the detail renders the Jira description (ADF) and shows
  the latest ten comments — automation bots hidden, tables deferring to Jira. Comments
  are fetched when opened and never stored.
- **Images in the description**: screenshots embedded in the description draw right in
  the detail window; click to zoom. They are as sensitive as the ticket, so they are
  **never cached to disk** — memory only, bounded by decoded size.
- **Open in the desktop app**: Slack and Figma links open the installed native apps
  (`slack://`, `figma://`) instead of the browser, falling back to the original link
  when the app is missing.
- **Slack threads**: no searching. Paste a Slack message link into **Add thread** on a
  ticket's detail and that thread attaches (right-click a message in Slack → Copy link).
  A reply's link walks up to the thread root. Attached threads refresh their reply count
  and last activity on every sync; remove one via right-click on its card.
- **Links attach without Slack**: pasting works before connecting, and in workspaces that
  never approve the app. The card keeps just the link — **Open in Slack** and nothing
  else — and connecting later fills the same card in on the next refresh.
- **Auto-attach from the Jira description**: the issue description (ADF) is walked for
  links. A `figma.com` link becomes the detail's **Open in Figma** button and Slack
  message links attach as threads. It only adds the `description` field to a request the
  app already makes, so **API usage does not grow.** Link marks, inline cards and bare
  pasted URLs are all recognized.
- **Connected pull requests**: recent pull requests of the configured repositories whose
  title or branch name carries the ticket key become buttons on the detail. Settings →
  GitHub needs a personal access token and the repositories (`owner/repo`). The Jira
  development panel (`dev-status`) was tried too, but it **only reports counts — no
  titles, no URLs** — so it was unusable.
- **Figma links**: enter one by hand when nothing was detected or you want a different
  file. The hand-entered link wins; clearing it falls back to detection.
- **Removing a thread depends on where it came from**: a pasted thread is deleted for
  good. One found in the Jira description is only hidden — the link is still in Jira, so
  deleting it would just invite it back on the next refresh.
- **Launch at login**: a toggle in Settings → General. The state is read from macOS rather
  than remembered, because the user can switch it off in System Settings. When macOS wants
  approval, the app says so and links straight to the right pane. **The app must live in
  Applications**: registration records the path at the time, so moving the app later
  breaks it.
- **The menu bar mark**: tickets that are newly assigned, changed status since last
  viewed, or carry unread Slack replies are counted next to the icon (`☑ 3`); with none,
  the icon stands alone. The list marks those tickets with a dot too.
  **Only opening the ticket's detail clears it** — clearing on merely opening the popover
  would drop marks for things never actually read, which costs trust. Thread replies clear
  separately when their card is expanded.
- **Failure handling**: Jira and Slack fail independently. Either one dying never clears
  the cache — a banner appears instead.
- **Token renewal**: PKCE apps get rotating tokens. Renewed 5 minutes before expiry; a
  rejected request renews once and retries.

## Structure

```
DocketKit/          all the logic — tested without launching the app
  Core/               language, strings, errors, status categories
  Credentials/        Keychain
  Jira/               REST v3 — search, transitions, comments, ADF rendering
  Slack/              PKCE OAuth, conversations.replies, rate limiter
  Matching/           link extraction from descriptions, reply→root recovery, dedup
  Store/              SwiftData models, sync engine, dashboard store
Docket/             SwiftUI — the popover and the window share the same list
```

Tokens live in the Keychain, other settings in UserDefaults, and the ticket/thread cache
in SwiftData.
