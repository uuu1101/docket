*[한국어](INSTALL.md) · English*

# Installing Docket

A macOS menu bar app that puts the Jira tickets assigned to you — and the Slack threads,
Figma files and pull requests attached to them — in one place.

---

## 1. Install

1. Download **`Docket 1.0.dmg`** and open it
2. **Drag the app onto the `Applications` folder** shown beside it
3. Launch it. A checklist icon appears in your menu bar.

The build is notarized by Apple, so it opens without any extra approval step.

**Keep the app in Applications.** Run it from Downloads and "launch at login" will remember
that path, so the feature breaks quietly the moment you tidy the folder up.

---

## 2. Set up

Open the menu bar icon and click the gear. **Jira is required; Slack and GitHub are
optional** — everything else keeps working without them.

### Jira (required)

1. Go to https://id.atlassian.com/manage-profile → **Security → API tokens** → create a token
2. In Settings → **Jira**, enter your **site address** (e.g. `https://your-site.atlassian.net`),
   your **email** and the **API token**.
3. Click **Test connection**

### Slack (optional — for threads)

Settings → **Slack** → click **Connect Slack** → approve in your browser.

There is no token to create. The Slack integration ships inside the app, so approving in
the browser is all it takes. It will show `Docket is connected` when it is done.

> If your workspace requires admin approval for apps, the request goes to an admin first.
> Where the Connect button is blocked, you can also paste your own Slack app's token under
> Settings → Slack → Advanced — see "paste your own app's token" in the README.
> Pasting thread links works without connecting too — the card keeps just the link, without
> the message or reply count, and fills in automatically once you connect.

### GitHub (optional — for pull request buttons)

1. github.com → Settings → Developer settings → **Personal access tokens (classic)**
2. Check **`repo` only**. Its sub-items get checked automatically; that is expected.
3. Paste the token in Settings → **GitHub** and click **Test connection**

> `repo` is what reading a private repository takes. A classic token has no read-only
> equivalent for private repositories, so the scope cannot be narrowed further — setting a
> short expiry is worth doing.

---

## 3. Using it

**The number beside the menu bar icon** counts tickets you have not looked at — newly
assigned, moved to a different status since you last opened them, or carrying unread Slack
replies. **Opening a ticket's detail** clears it.

**Ordering** — soonest Target end first, then highest priority. Finished tickets sink to the
bottom. The `D-3` badge is how long is left; it turns red once the date has passed.

**Click a ticket** to open its detail, where you get:

- **Change status** — click the status badge to move the ticket to any status its
  workflow allows.
- **Description and comments** — the Jira description and the latest comments (minus
  automation bots) show right in the detail.
- **Pull request, Jira and Figma buttons** — links written into the Jira description are
  picked up automatically. A pull request matches when the ticket key appears in its title
  or its branch name.
- **Slack threads** — Slack links in the Jira description attach themselves. Otherwise use
  **Add thread** and paste a Slack message link (right-click a message in Slack → Copy
  link). A link to a reply attaches the whole thread.
- **Add Figma link** — for when nothing was detected, or you want a different file.

**Settings → General** covers language (English/한국어), how often it refreshes, which
tickets to show, and **launch at login**.

---

## 4. If something goes wrong

| Symptom | Cause and fix |
|---|---|
| No pull request buttons | The ticket key is in neither the title nor the branch name, or the token cannot reach the repository |
| A `SAML enforcement` error from GitHub | Open your token list, click `Configure SSO` and authorize the organisation |
| Slack threads never attach | Settings → Slack → **Disconnect**, then connect again |
| Launch at login does nothing | Check System Settings → General → Login Items and allow it |
| No tickets at all | Check **Tickets to show** in Settings → General, and the Jira connection test |

If the cause is not obvious, run this and share the output:

```bash
log show --predicate 'subsystem == "dev.taetae.docket"' --last 30m
```

---

## 5. Your data

**Everything stays on your Mac.** There is no server, so nothing is sent anywhere.

- Tokens: the macOS keychain
- Ticket and thread cache: `~/Library/Application Support/Docket/`
- Slack is read **with your own permissions** — public channels, plus the private channels
  and DMs you are already in

---

## Changelog

| Version | Date | Notes |
|---|---|---|
| 1.0 | 2026-08-19 | First release |
