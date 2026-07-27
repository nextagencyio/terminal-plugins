// Wave Terminal status badges for opencode sessions.
// Install: symlink or copy into ~/.config/opencode/plugins/ (see install-opencode.sh).
// No-op outside Wave (WAVETERM_BLOCKID unset).
export const WaveBadges = async ({ $ }) => {
  if (!process.env.WAVETERM_BLOCKID) return {};
  const wb = `${process.env.HOME}/.local/bin/wave-badge`;
  let last = null;
  const set = async (state) => {
    // tool events fire constantly; only re-assert "working" on a state change
    if (state === "working" && last === "working") return;
    last = state;
    try {
      await $`echo '{}' | ${wb} opencode ${state}`.quiet();
    } catch {}
  };
  return {
    "session.created": () => set("start"),
    "tool.execute.before": () => set("working"),
    "permission.asked": () => set("attention"),
    "permission.replied": () => set("working"),
    "session.idle": () => set("done"),
    "session.error": () => set("error"),
  };
};
