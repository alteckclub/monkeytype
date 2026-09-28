# monkeytype (fork)

Static, anonymous, Nix-packaged build of the [Monkeytype](https://github.com/monkeytypegame/monkeytype)
frontend.

`upstream` is [monkeytypegame/monkeytype](https://github.com/monkeytypegame/monkeytype).
This fork tracks it, but **diverges on purpose** — see below. The pinned upstream
revision this was forked from is `4bd46c6` (v26.32.0).

## What this fork is for

Self-hosting the typing test for a household, with no backend and no accounts:
results and preferences live in the browser. The output is a static site that
nginx can serve directly.

```bash
nix build            # -> ./result, the site root
nix run .#monkeytype-frontend   # not a binary; use a static server
```

## Why it diverges from upstream

Upstream builds with pnpm in a pnpm/turbo monorepo that also contains the
backend (Express + MongoDB + Redis). None of that is needed here, and the pnpm
tree could not be made reproducible in Nix: repeated `pnpm install` runs
produced different bytes (intermittently mangled files, and wall-clock stamps in
`.modules.yaml` / `.pnpm-workspace-state-v1.json`), and pnpm 11's
`store/v11/index.db` is a SQLite file that cannot serve as a hash-pinned
fixed-output derivation.

So the build was converted to npm, which is bit-reproducible.

### Changes

- **Backend removed**, along with `frontend/storybook`, `packages/release`,
  `packages/oxlint-config`, `docs/`, `docker/`, and the turbo/knip/stylelint/
  commitlint/husky tooling. The frontend needs only `packages/{tsup-config,
  schemas, util, contracts, challenges, funbox}`.
- **pnpm → npm**: root `package.json` declares npm `workspaces`,
  `workspace:*` specifiers became `*`, and installs use `--legacy-peer-deps`
  (pnpm only warns about the vite 8 peer ranges that several dev plugins still
  declare). `pnpm-lock.yaml` is replaced by a committed `package-lock.json`.
  Dependency count went from ~1776 to 644, and every remaining package is pure
  JavaScript — the native modules (`bcrypt`, `re2`, `ssh2`, `msgpackr-extract`,
  `@parcel/watcher`, `cpu-features`, `protobufjs`) all came from the backend.
- **`oxlintChecker` removed** from `frontend/vite.config.ts`. It shelled out to
  `npx oxlint` from `buildStart()` and aborted the build on lint errors, which
  both breaks hermetic builds and drags in a `@typescript-eslint` version that
  does not exist on the registry.
- **`vite-plugin-inspect` removed** — it peers on `vite <= 7` while the project
  is on vite 8, and is dev-only.
- **`RECAPTCHA_SITE_KEY` is no longer required** to build. env-config already
  defaulted it to an empty string, and recaptcha only serves the account
  password-reset flow, which this deployment does not have.
- **`BACKEND_URL=/api` at build time.** Without it the production build bakes
  `https://api.monkeytype.com` into the bundle, so a self-hosted instance would
  silently call Monkeytype's hosted API. `/api` is same-origin and is not
  proxied, so account actions simply fail.
- **Firebase config files are now committed source**
  (`frontend/src/ts/constants/firebase-config{,-live}.ts`, empty values,
  un-ignored in `.gitignore`). Upstream generates them in their Dockerfile;
  the production build aliases `firebase-config` to `firebase-config-live`, so
  both must exist. The import is lazy inside a `try`/`catch`, so empty values
  are inert.
- **`madge` dropped** from the build scripts and devDependencies. Its
  `detective-typescript` dependency is what pulled in the broken
  `@typescript-eslint` chain.
- Preconnects to `api.monkeytype.com` and Firebase removed from
  `frontend/src/html/head.html`.
- Added `flake.nix`.

## Keeping up with upstream

```bash
git fetch upstream
git log --oneline HEAD..upstream/master        # what changed
git merge upstream/master                      # expect conflicts in:
                                              #   package.json (workspaces)
                                              #   frontend/vite.config.ts
                                              #   frontend/package.json
                                              #   .gitignore
# then re-run: npm install --legacy-peer-deps && nix build
# and update the FOD hash in flake.nix if package-lock.json changed
```

The upstream revision is not pinned by a flake input, so a `nix flake update` is
not involved; the fork's own commits are the source of truth.
