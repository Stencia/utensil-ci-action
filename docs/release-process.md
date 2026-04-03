# CI Action Release Process

## Tags

Every release has two tags:

1. **Immutable version tag** (e.g. `v0.5.0-alpha`). Never moves. Customers who need reproducibility pin to this.
2. **`latest` tag**. Moves to each new release. Customers who want the newest version use this.

`latest` is honest about what it is. It communicates "this will change." A version tag like `v5` that silently moves is dishonest because it implies stability.

## Why `@latest` is safe for CI actions

A CI action is not a shipping dependency. If `lodash@latest` breaks, production crashes. If `utensil-ci-action@latest` breaks, a CI run fails and you retrigger. The blast radius is minutes, not an outage.

The action's contract with consumers: scan the repo, evaluate findings, post a comment, create a check run, upload results. As long as input/output schema stays backward compatible, `@latest` gives customers the best version automatically.

## Who uses what

| Consumer | Tag | Why |
|----------|-----|-----|
| Our repos (Utensil, utensil-web) | `@latest` | Always want the newest. No manual bumps. |
| External customers (default) | `@latest` | Best experience out of the box. |
| External customers (pinned) | `@v0.5.0-alpha` | Need reproducibility for compliance or audit. |

## Release steps

After merging a change to `main`:

```bash
cd /path/to/utensil-ci-action

# Fetch latest main
git fetch stencia main

# Create immutable version tag
git tag v0.X.0-alpha stencia/main

# Move latest to the same commit
git tag -f latest stencia/main

# Push both
git push stencia v0.X.0-alpha
git push stencia latest --force
```

The `--force` is only for the `latest` tag. Version tags are never force-pushed.

## Breaking changes

If a release removes or changes an input/output (breaking backward compatibility):

1. Document the breaking change in the PR description
2. Bump the major version (e.g. `v0.X` to `v1.0.0`)
3. Update `latest` as usual
4. Notify consumers in the release notes

Example: PR #7 removed the `github-comment` input. This is a breaking change. Consumers whose workflows set `github-comment: true` will get a YAML warning but the action still works (the input is ignored).

## Versioning scheme

- `v0.X.Y-alpha`: pre-1.0 releases. Breaking changes can happen between minor versions.
- `v1.0.0`: first stable release. Breaking changes only on major version bumps.
- Patch versions (`v1.0.1`) for bug fixes.
- Minor versions (`v1.1.0`) for new features (backward compatible).
