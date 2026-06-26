# Developer Setup

This guide gets you from "I want to contribute to EllesmereUI" to a live
development environment where your code edits are picked up by the game on a
`/reload` — no copying files, no rebuilds.

It covers: forking the repo, wiring up the upstream remote, restoring the
libraries (which aren't in git), and junction-linking your checkout into your
WoW `AddOns` folder.

> **Windows / PowerShell.** The setup helper is a PowerShell script and uses
> directory **junctions**, so no Administrator rights or Developer Mode are
> needed.

---

## How the repo maps to AddOns

EllesmereUI ships as one main addon plus several sub-addons. In the repo they
live like this:

```
EllesmereUI\                     <- the main addon (EllesmereUI.toc at the root)
├─ EllesmereUIActionBars\        <- a sub-addon (its own .toc)
├─ EllesmereUIUnitFrames\        <- a sub-addon
├─ ... (15 more sub-addons)
├─ Libs\                         <- libraries (gitignored, see below)
├─ Locales\  media\  ...         <- part of the main addon, not separate addons
```

When you develop, **each addon is linked into `AddOns` as its own folder**:

```
AddOns\EllesmereUI            -> <repo root>          (the main addon)
AddOns\EllesmereUIActionBars  -> <repo root>\EllesmereUIActionBars
AddOns\EllesmereUIUnitFrames  -> <repo root>\EllesmereUIUnitFrames
... one junction per sub-addon
```

The `move-folders` step in `.pkgmeta` (which flattens sub-addons into siblings)
only happens when the packager builds a *release*. For development you don't run
the packager — the setup script makes the same layout with live junctions.

---

## About the libraries (`Libs`)

The libraries are **not committed to git**. They're declared as packager
externals in `.pkgmeta` and pulled in at release time, so `.gitignore` excludes:

- `Libs/` (belongs to the main addon)
- `EllesmereUIUnitFrames/Libs/` (the `oUF` external)

A fresh clone is therefore **missing these and won't run** until you restore
them. Two ways to do that:

1. **Lift them from your existing install (recommended).** If you already *play*
   with EllesmereUI installed, your installed copy already has working libs. The
   setup script copies them into your checkout automatically the first time it
   replaces your real installed folders (see step 4). Nothing extra to do.
2. **Fresh machine / never installed it.** Download the latest packaged release
   zip (CurseForge or the GitHub release) — it ships with fully-populated `Libs`
   folders — and copy its `Libs\` and `EllesmereUIUnitFrames\Libs\` into your
   checkout.

> **Ordering matters for method 1:** clone first and run the script **while your
> normal install is still in place**. Don't uninstall EllesmereUI beforehand, or
> there'll be nothing to lift the libs from.

---

## Setup

> Prerequesite - Install git
> https://git-scm.com/install/windows

### 1. Fork and clone

Fork `EllesmereGaming/EllesmereUI` on GitHub, then clone **your fork** to your
dev folder:

```powershell
git clone git@github.com:<your-username>/EllesmereUI.git F:\dev\EllesmereUI
cd F:\dev\EllesmereUI
```

### 2. Add the upstream remote

This lets you pull in the owner's changes later. `origin` stays pointed at your
fork (where you push); `upstream` is the source of truth (read-only for you).

```powershell
git remote add upstream git@github.com:EllesmereGaming/EllesmereUI.git
git fetch upstream
```

Verify:

```powershell
git remote -v
# origin    git@github.com:<your-username>/EllesmereUI.git (fetch/push)
# upstream  git@github.com:EllesmereGaming/EllesmereUI.git (fetch/push)
```

### 3. Preview the link (dry run)

Always look before you leap — `-WhatIf` shows exactly what would be created,
replaced, and which libs would be preserved, **without changing anything**:

```powershell
.\.tools\Link-AddOns.ps1 "<path-to-your>\_retail_\Interface\AddOns" "F:\dev\EllesmereUI" -Force -WhatIf
```

Example AddOns path:
`F:\games\World of Warcraft\_retail_\Interface\AddOns`

### 4. Link it in

When the preview looks right, run it for real:

```powershell
.\.tools\Link-AddOns.ps1 "<path-to-your>\_retail_\Interface\AddOns" "F:\dev\EllesmereUI" -Force
```

What `-Force` does to each existing addon folder in `AddOns`:

- **A real installed folder** → its `Libs` is copied into your checkout (if your
  checkout is missing them), then the folder is deleted and replaced with a
  junction.
- **A junction from a previous run** → simply re-pointed (your dev files are
  never touched).

Without `-Force`, existing folders are left alone and skipped.

### 5. Confirm in-game

Launch WoW (or `/reload` if it's running). On the AddOns list you should see
EllesmereUI and its modules loading from your checkout. Edit a `.lua`, `/reload`,
and your change is live.

---

## Daily workflow

```powershell
# Start a feature from up-to-date upstream
git fetch upstream
git switch -c my-feature upstream/main      # or upstream/<default-branch>

# ...edit code, test in-game with /reload...

git add -A
git commit -m "Describe your change"
git push -u origin my-feature
```

Then open a Pull Request from `your-username:my-feature` into
`EllesmereGaming:main`.

**Keep your branch current:**

```powershell
git fetch upstream
git rebase upstream/main
```

---

## Notes & troubleshooting

- **Re-running is safe.** The script is idempotent — running it again just
  re-points existing junctions; it won't re-copy libs over a checkout that
  already has them.
- **Only some folders get linked.** A subfolder is treated as a sub-addon only
  if it contains a matching `<name>.toc`. `Libs`, `Locales`, and `media` are part
  of the main addon and are intentionally *not* linked separately.
- **"Cannot create a file when that file already exists."** You ran without
  `-Force` against existing folders. Re-run with `-Force` (preview with `-WhatIf`
  first).
- **Game shows no addons / Lua errors about missing libraries.** Your `Libs`
  didn't get restored (e.g. you uninstalled before linking). Use method 2 in
  [About the libraries](#about-the-libraries-libs).
- **Wrong folder linked.** Junctions are safe to delete in Explorer or with
  `Remove-Item` — deleting a junction removes only the link, not your dev files.
- **The setup script** lives at `.tools\Link-AddOns.ps1` and is the one tracked
  `.ps1` in the repo (all other `*.ps1` are gitignored). It's excluded from
  release builds via `.pkgmeta`.
