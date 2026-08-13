import { cn } from "@/lib/utils"

/**
 * The app's creatures, on the web.
 *
 * The rows are the ones in `apps/mac/Sources/PerchApp/UI/AgentGlyph.swift`, and the colours
 * are the same hexes — a sprite drawn here from the same grid is the same mark, so the site
 * and the app agree about what a Claude session looks like. Both are ours, drawn from
 * nothing, which is the property that matters for something published on a public page.
 *
 * `x` is the body, `o` the accent, anything else is nothing.
 */
const ART = {
  claude: {
    rows: [
      "..xxx.....",
      ".xx.xx....",
      ".xxxxx...o",
      ".xxxxxx.oo",
      "..xxxxxoo.",
      "..xxxxx...",
      "..xxxxx...",
      ".xx..xx...",
      ".x....x...",
      "..........",
    ],
    body: "#d97757",
    accent: "#f59e0b",
  },
  codex: {
    rows: [
      "...xxx....",
      "..xx.xx...",
      "..xxxxx...",
      ".ooooooo..",
      "oxxxxxxxo.",
      "oxxxxxxxo.",
      ".ooooooo..",
      "..xx.xx...",
      "..x...x...",
      "..........",
    ],
    body: "#60a5fa",
    accent: "rgb(255 255 255 / 0.75)",
  },
  opencode: {
    rows: [
      "...xx.xx..",
      "..xxxxxxx.",
      ".xxxxxxxxo",
      ".xxxxxxxoo",
      ".xx.xx.xoo",
      ".xxxxxxx.o",
      "..xxxxxx..",
      "..xx..xx..",
      "..........",
      "..........",
    ],
    body: "#4ade80",
    accent: "rgb(255 255 255 / 0.85)",
  },
} as const

export type SpriteName = keyof typeof ART

/**
 * One creature, drawn as literal squares.
 *
 * `beat` staggers the breathing so a row of them reads as three animals rather than as one
 * animation played three times — the same trick the notch strip uses.
 */
export function PixelSprite({
  name,
  pixel = 3,
  beat = 0,
  breathing = true,
  className,
}: {
  name: SpriteName
  pixel?: number
  beat?: number
  breathing?: boolean
  className?: string
}) {
  const art = ART[name]

  return (
    <div
      aria-hidden
      className={cn("grid shrink-0", breathing && "breathe", className)}
      style={{
        gridTemplateColumns: `repeat(10, ${pixel}px)`,
        animationDelay: `${beat * 0.19}s`,
      }}
    >
      {art.rows.map((row, y) =>
        [...row].map((cell, x) => (
          <span
            key={`${x}-${y}`}
            style={{
              width: pixel,
              height: pixel,
              background: cell === "x" ? art.body : cell === "o" ? art.accent : "transparent",
            }}
          />
        )),
      )}
    </div>
  )
}
