# Release automation

The plugin pins the `mdp` CLI version in [`mdp-version.txt`](../mdp-version.txt).
`lua/md-preview/install.lua` reads that file and passes `MDP_VERSION=<tag>` to
`install.sh`, so whenever a user updates the plugin, `:MdPreviewInstall` pulls
the binary at the pinned tag.

The pin is kept in sync automatically: whenever `aldevv/md-preview` cuts a
release, a `repository_dispatch` event fires this repo's
[`bump-cli`](workflows/bump-cli.yml) workflow, which rewrites
`mdp-version.txt`, patch-bumps the plugin's own tag, and publishes a GitHub
release.

## CLI-side wiring (required)

Add a dispatch step to `aldevv/md-preview`'s release workflow so the plugin
hears about new CLI releases:

```yaml
# .github/workflows/release.yml in aldevv/md-preview
jobs:
  goreleaser:
    # … existing steps …

  notify-plugin:
    needs: goreleaser
    runs-on: ubuntu-latest
    steps:
      - name: Fire repository_dispatch at md-preview.nvim
        env:
          GH_TOKEN: ${{ secrets.PLUGIN_BUMP_TOKEN }}
          VERSION:  ${{ github.ref_name }}
        run: |
          gh api repos/aldevv/md-preview.nvim/dispatches \
            -f event_type=cli-release \
            -f "client_payload[version]=$VERSION"
```

`PLUGIN_BUMP_TOKEN` is a fine-grained PAT (or classic token) with **Contents:
write** permission on `aldevv/md-preview.nvim`. The default `GITHUB_TOKEN`
can't cross repo boundaries, which is why a PAT is required here.

## Manual trigger

The workflow also accepts `workflow_dispatch` with a `version` input, so you
can re-run it from the Actions tab if the cross-repo dispatch ever misses.
