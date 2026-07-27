---
name: wave-badges-setup
description: Wire Wave Terminal status badges into this machine's Devin CLI (and optionally opencode). Run when the user asks to set up wave badges, Wave Terminal agent indicators, or agent status notifications.
---

# Wave badges setup

Set up Wave Terminal status badges for Devin CLI on this machine.

1. Locate or fetch the wave-plugins repo:
   - If a local clone exists (check `~/nextagencyio/wave-plugins` or ask the user), use it.
   - Otherwise: `git clone https://github.com/nextagencyio/wave-plugins /tmp/wave-plugins` and use that.
2. Run the installer: `<repo>/plugins/wave-badges/install-devin.sh`
   - Requires `jq`. It symlinks `wave-badge` to `~/.local/bin/` and merges hook
     entries into `~/.config/devin/config.json` idempotently.
3. If the user also uses opencode, run `<repo>/plugins/wave-badges/install-opencode.sh`.
4. Tell the user to restart their Devin sessions inside Wave Terminal blocks.

The badge script is a no-op outside Wave, so this is safe on machines that
also use other terminals.
