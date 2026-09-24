/** @jsxImportSource @opentui/solid */
import type { TuiPlugin, TuiPluginModule, TuiSlotPlugin } from "@opencode-ai/plugin/tui"

// Hoplon home-screen wordmark. The host renders the home route with the logo
// inside `<Slot name="home_logo" mode="replace">`, so registering this slot
// replaces the default OpenCode logo with the Hoplon banner.
const WORDMARK = [
  "█  █ ████ ████ █    ████ █  █",
  "█  █ █  █ █  █ █    █  █ ██ █",
  "████ █  █ ████ █    █  █ █ ██",
  "█  █ █  █ █    █    █  █ █  █",
  "█  █ ████ █    ████ ████ █  █",
]

const LAMBDA = "\u039b"

const brand: TuiSlotPlugin = {
  order: 0,
  slots: {
    home_logo(ctx) {
      const t = ctx.theme.current
      return (
        <box flexDirection="column">
          {WORDMARK.map((line) => (
            <text fg={t.accent}>{line}</text>
          ))}
          <text fg={t.textMuted}>
            <span style={{ fg: t.primary }}>{LAMBDA} </span>offensive security console
          </text>
        </box>
      )
    },
  },
}

const tui: TuiPlugin = async (api, options) => {
  if (options?.enabled === false) return
  api.slots.register(brand)
}

const plugin: TuiPluginModule & { id: string } = {
  id: "hoplon-brand",
  tui,
}

export default plugin
