# Pushing this repo to GitHub or GitLab

The repo is already initialised, on branch `main`, with one commit containing all 32 files. Nothing is staged or pending — you only need to add a remote and push.

I can't create the remote for you: that needs your account credentials, and you should never hand those to a model. Below is every command you need.

---

## GitHub

### Option A — `gh` CLI (fastest)

```bash
cd prisoner-to-king
gh auth login                              # once, if you haven't
gh repo create prisoner-to-king --private --source=. --remote=origin --push
```

One command creates the repo, wires `origin`, and pushes. Swap `--private` for `--public` if you want it open.

### Option B — web UI

1. github.com → **New repository** → name it `prisoner-to-king`.
2. **Do not** tick "Add a README", "Add .gitignore", or "Choose a license" — this repo already has them, and an initialised remote will force you into a merge on your first push.
3. Then:

```bash
cd prisoner-to-king
git remote add origin https://github.com/<you>/prisoner-to-king.git
git push -u origin main
```

---

## GitLab

```bash
cd prisoner-to-king
git remote add origin https://gitlab.com/<you>/prisoner-to-king.git
git push -u origin main
```

Create the project on gitlab.com first with **"Initialize repository with a README" unchecked**, for the same reason.

Note: the CI config in `.github/workflows/ci.yml` is GitHub Actions only. On GitLab it's inert — harmless, but you'd want a `.gitlab-ci.yml` to get the same parse check. Ask and I'll write one.

---

## Recommended repo settings

**Keep it private until launch.** Not because the code is secret, but because a public repo of an unreleased Roblox game invites clones before you've proven the loop. Open it up after launch if you want.

Once pushed:

- **Branch protection on `main`** — require the CI check to pass. It takes 30 seconds to set up and stops a parse error from ever reaching a playtest.
- **Never commit a `.rbxl`.** Already gitignored. If someone force-adds one, the whole "source of truth is `src/`" model collapses and you lose reviewable diffs.
- **Never commit Open Cloud API keys or DataStore dumps.** `.env`, `*.key`, and `secrets*.json` are gitignored as a backstop, but the real defence is not putting them in the working tree.

---

## Day-to-day loop once it's up

```bash
git switch -c m1/extraction-tuning     # branch per change
# edit src/...
rojo serve                             # Studio picks up saves live
git add -A && git commit -m "Lower death loss to 50% for A/B test"
git push -u origin m1/extraction-tuning
```

Then open a PR. Because the map is generated from code rather than hand-built in a place file, a balance change like the one above shows up as a **one-line diff in `GameConfig.luau`** — which is exactly what you want when you start running the A/B tests from blueprint §55.
