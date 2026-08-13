import { useEffect, useState, type ReactNode } from "react"

import { PixelSprite, type SpriteName } from "@/components/pixel-sprite"
import { cn } from "@/lib/utils"

/**
 * What Perch looks like, without installing Perch.
 *
 * The product lives in a place a screenshot cannot explain — a panel hanging off a physical
 * cutout, that appears when an agent needs something and gets out of the way when it does
 * not. So the page draws the laptop, puts the panel where it actually hangs, and plays the
 * four moments that matter through it.
 *
 * Everything below is drawn from the app's own tokens rather than captured: the colours are
 * `Theme.swift`, the face is Departure Mono, the creatures are the ones in `AgentGlyph`.
 * A screenshot would go stale the first time the panel changed; this cannot.
 */
const SCENES = [
  { id: "overview", label: "Vue d'ensemble" },
  { id: "approval", label: "Approbation" },
  { id: "ask", label: "Question" },
  { id: "jump", label: "Sauter à la session" },
] as const

type SceneId = (typeof SCENES)[number]["id"]

/** Long enough to read the diff, short enough that nobody leaves before the next scene. */
const DWELL_MS = 6_000

export function NotchDemo() {
  const [scene, setScene] = useState<SceneId>("overview")
  // Autoplay is a courtesy for someone who has not clicked yet. The first click is someone
  // deciding what they want to look at, and a carousel that keeps moving under them after
  // that is a carousel they have to fight.
  const [isAuto, setIsAuto] = useState(true)

  useEffect(() => {
    if (!isAuto) return
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    const timer = window.setTimeout(() => {
      const next = SCENES[(SCENES.findIndex((entry) => entry.id === scene) + 1) % SCENES.length]
      setScene(next.id)
    }, DWELL_MS)
    return () => window.clearTimeout(timer)
  }, [scene, isAuto])

  return (
    <section aria-label="Perch en fonctionnement">
      <MacBook>
        <Panel scene={scene} />
      </MacBook>

      <div className="mt-6 flex flex-wrap justify-center gap-1">
        {SCENES.map((entry) => (
          <button
            key={entry.id}
            type="button"
            onClick={() => {
              setScene(entry.id)
              setIsAuto(false)
            }}
            aria-pressed={scene === entry.id}
            className={cn(
              "rounded-lg px-3 py-1.5 font-mono text-xs transition-colors",
              scene === entry.id
                ? "bg-line-strong text-ink"
                : "text-ink-3 hover:bg-line hover:text-ink-2",
            )}
          >
            {entry.label}
          </button>
        ))}
      </div>
    </section>
  )
}

/**
 * The laptop.
 *
 * Drawn rather than photographed, for the same reason the creatures are: a photograph of
 * someone else's hardware is someone else's asset, and a lid is four rectangles.
 */
function MacBook({ children }: { children: ReactNode }) {
  return (
    <div className="mx-auto w-full max-w-3xl">
      <div className="rounded-[14px] border border-line-strong bg-raised-2 p-[6px] shadow-[0_40px_80px_-20px_rgb(0_0_0/0.9)] sm:rounded-[20px] sm:p-[10px]">
        {/* The lid holds its 16:10 from `sm` up. Below that the panel is in flow and the lid
            takes the height it needs: a laptop drawn 350px wide renders the panel's 9px type
            at four pixels, which is a picture of the product nobody can read. */}
        <div className="relative overflow-hidden rounded-[8px] bg-[radial-gradient(125%_115%_at_50%_-10%,#1b3a2e_0%,#0e1512_45%,#050505_100%)] pb-10 sm:aspect-16/10 sm:rounded-[11px] sm:pb-0">
          <div className="h-4 sm:h-[3.4%]">
            <MenuBar />
          </div>
          <Desktop />
          {/* The cutout. Square at the top because it is cut out of the screen edge, and the
              panel below hangs from it rather than floating near it. */}
          <div className="absolute top-0 left-1/2 z-10 h-4 w-[26%] -translate-x-1/2 rounded-b-[7px] bg-black sm:h-[3.4%] sm:w-[13%]" />
          <div className="relative z-20 mx-auto -mt-4 flex w-[94%] justify-center sm:absolute sm:top-0 sm:left-1/2 sm:mt-0 sm:w-[64%] sm:-translate-x-1/2">
            {children}
          </div>
        </div>
      </div>

      {/* Hinge and base: wider than the lid, and the only part with a highlight on it. The
          overhang is stated in pixels rather than in percent — as a percentage it grew with
          the page and pushed a horizontal scrollbar onto every narrow screen. */}
      <div className="-ml-3 h-[10px] w-[calc(100%+24px)] rounded-b-[10px] bg-gradient-to-b from-line-strong to-[#0b0b0b]">
        <div className="mx-auto h-[3px] w-[14%] rounded-b-[4px] bg-black/60" />
      </div>
    </div>
  )
}

function MenuBar() {
  return (
    <div className="flex h-full items-center justify-between bg-black/45 px-3 font-mono text-[7px] text-ink-3 backdrop-blur-sm">
      {/* Short enough that the panel does not clip it mid-word — a menu bar cut off at
          "Présenta" reads as a rendering fault rather than as a menu bar. */}
      <span className="hidden sm:inline">Finder Fichier Édition</span>
      <span />
      <span className="hidden sm:inline">100 % · ven. 13:37</span>
    </div>
  )
}

/**
 * The work the panel is hanging over.
 *
 * An empty desktop makes the panel look like a slide. What the product actually claims is
 * that you never leave what you were doing, and the cheapest way to say that is to draw the
 * thing you were doing underneath it. Deliberately contentless — grey bars, no readable
 * code — because it is scenery, and scenery that can be read competes with the panel.
 */
/** Enough lines to reach the bottom of the lid — a file that stops halfway looks unloaded. */
const CODE_WIDTHS = [
  46, 72, 58, 81, 34, 64, 76, 41, 68, 52, 79, 37, 61, 70, 55, 44, 83, 39, 66, 74, 48, 60, 35,
  77, 51, 69, 42, 58, 80, 36, 63, 71, 45, 74, 53, 67,
]
const INDENTS = [0, 8, 16, 16, 8, 0, 8, 16, 24, 16, 8]

function Desktop() {
  return (
    <div className="absolute inset-x-[7%] -bottom-px top-[15%] overflow-hidden rounded-t-[10px] border border-white/[0.06] bg-white/[0.02]">
      <div className="flex items-center gap-1.5 border-b border-white/[0.06] px-2.5 py-1.5">
        <span className="size-[5px] rounded-full bg-white/15" />
        <span className="size-[5px] rounded-full bg-white/15" />
        <span className="size-[5px] rounded-full bg-white/15" />
        <span className="ml-2 font-mono text-[7px] text-white/20">SoundPlayer.swift — perch</span>
      </div>

      <div className="flex h-full">
        <div className="flex w-[18%] flex-col gap-1.5 border-r border-white/[0.06] p-2.5">
          {[62, 84, 71, 50, 78, 66].map((width, index) => (
            <span key={index} className="h-[3px] rounded-full bg-white/[0.07]" style={{ width: `${width}%` }} />
          ))}
        </div>
        <div className="flex flex-1 flex-col gap-[8px] p-2.5">
          {CODE_WIDTHS.map((width, index) => (
            <span
              key={index}
              className="h-[3px] rounded-full bg-white/[0.06]"
              // The two lists are different lengths on purpose: cycling them together would
              // produce a staircase, and a staircase does not read as code.
              style={{ width: `${width}%`, marginLeft: `${INDENTS[index % INDENTS.length]}px` }}
            />
          ))}
        </div>
      </div>
    </div>
  )
}

/**
 * The panel itself, at the size it hangs at.
 *
 * Its height is fixed across the four scenes on purpose: in the app the panel resizes to
 * its content, but a demo that jumps by eighty pixels every six seconds reads as a layout
 * bug rather than as a product.
 */
function Panel({ scene }: { scene: SceneId }) {
  return (
    <div className="w-full rounded-b-2xl border border-t-0 border-line bg-black/95 px-3 pt-2 pb-3 font-mono text-ink shadow-[0_20px_50px_-12px_rgb(0_0_0/0.9)] backdrop-blur-xl">
      <Strip />
      <div
        key={scene}
        className="mt-2 min-h-[136px] duration-300 animate-in fade-in-0 slide-in-from-top-1"
      >
        {scene === "overview" ? <Overview /> : null}
        {scene === "approval" ? <Approval /> : null}
        {scene === "ask" ? <Ask /> : null}
        {scene === "jump" ? <Jump /> : null}
      </div>
    </div>
  )
}

/** The resting strip: what is on screen when nothing needs you. */
function Strip() {
  return (
    <div className="flex items-center gap-2 border-b border-line pb-2 text-[8px] text-ink-3">
      <div className="flex items-center gap-1.5">
        <PixelSprite name="claude" pixel={2} beat={0} />
        <PixelSprite name="codex" pixel={2} beat={1} />
        <PixelSprite name="opencode" pixel={2} beat={2} />
      </div>
      <span className="text-ink-2">3 sessions</span>
      <span className="ml-auto tabular">48,2K jetons · 1,84 $</span>
    </div>
  )
}

const SESSIONS: { agent: SpriteName; project: string; state: string; tone: string; tokens: string }[] =
  [
    { agent: "claude", project: "perch/apps/mac", state: "écrit des tests", tone: "text-active", tokens: "22,4K" },
    { agent: "codex", project: "atlas/api", state: "en attente · 2 min", tone: "text-claude", tokens: "18,1K" },
    { agent: "opencode", project: "site-vitrine", state: "au repos", tone: "text-ink-3", tokens: "7,7K" },
  ]

function Overview() {
  return (
    <div className="flex flex-col gap-1">
      {SESSIONS.map((session) => (
        <div
          key={session.project}
          className="flex items-center gap-2 rounded-lg bg-white/[0.03] px-2 py-1.5 text-[9px]"
        >
          <PixelSprite name={session.agent} pixel={2} beat={0} breathing={session.tone === "text-active"} />
          <span className="truncate text-ink-2">{session.project}</span>
          <span className={cn("truncate", session.tone)}>{session.state}</span>
          <span className="tabular ml-auto text-ink-3">{session.tokens}</span>
        </div>
      ))}
      <p className="mt-1 text-[8px] text-ink-3">
        Tout ce qui tourne, dans une seule barre. Un clic saute à la session.
      </p>
    </div>
  )
}

/** The card the whole product exists for. */
function Approval() {
  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center gap-2">
        <PixelSprite name="claude" pixel={2.5} />
        <span className="text-[10px] text-ink">Edit</span>
        <span className="truncate text-[9px] text-ink-3">Sources/PerchApp/SoundPlayer.swift</span>
        <span className="ml-auto shrink-0 rounded bg-white/[0.06] px-1.5 py-0.5 text-[8px]">
          <span className="text-active">+3</span> <span className="text-danger">−1</span>
        </span>
      </div>

      <div className="overflow-hidden rounded-md border border-line bg-white/[0.02] text-[8px] leading-[1.6]">
        <DiffLine number="41" kind="context" text="guard let sound = resolve(source) else { return }" />
        <DiffLine number="42" kind="removed" text="sound.volume = Float(settings.volume)" />
        <DiffLine number="42" kind="added" text="sound.volume = Float(min(max(settings.volume, 0), 1))" />
        <DiffLine number="43" kind="added" text="if sound.isPlaying { sound.stop() }" />
        <DiffLine number="44" kind="context" text="sound.play()" />
      </div>

      <div className="flex items-center gap-1.5">
        <Key label="Autoriser" hint="⏎" tone="active" />
        <Key label="Refuser" hint="esc" />
        <Key label="Toujours" hint="a" />
        <span className="ml-auto text-[8px] text-ink-3">sans quitter l'éditeur</span>
      </div>
    </div>
  )
}

function DiffLine({
  number,
  kind,
  text,
}: {
  number: string
  kind: "added" | "removed" | "context"
  text: string
}) {
  const sign = kind === "added" ? "+" : kind === "removed" ? "−" : " "

  return (
    <div
      className={cn(
        "flex gap-2 px-1.5",
        kind === "added" && "bg-active/10 text-active",
        kind === "removed" && "bg-danger/10 text-danger",
        kind === "context" && "text-ink-3",
      )}
    >
      <span className="tabular w-4 shrink-0 text-right text-ink-3/70">{number}</span>
      <span className="w-2 shrink-0">{sign}</span>
      <span className="truncate">{text}</span>
    </div>
  )
}

const OPTIONS = [
  "Postgres — déjà en place pour le reste",
  "SQLite — un fichier, zéro service",
  "Redis — le plus rapide, une dépendance de plus",
]

function Ask() {
  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center gap-2">
        <PixelSprite name="codex" pixel={2.5} />
        <span className="text-[10px] text-info">Quelle base pour le cache ?</span>
      </div>

      <div className="flex flex-col gap-1">
        {OPTIONS.map((option, index) => (
          <div
            key={option}
            className={cn(
              "flex items-center gap-2 rounded-md border px-2 py-1.5 text-[9px]",
              index === 1 ? "border-info/50 bg-info/10 text-ink" : "border-line text-ink-2",
            )}
          >
            <span className="rounded bg-white/[0.06] px-1 text-[8px] text-ink-3">{index + 1}</span>
            <span className="truncate">{option}</span>
          </div>
        ))}
      </div>

      <p className="text-[8px] text-ink-3">
        Autre — écris ta réponse. La question revient dans la session, pas dans un chat.
      </p>
    </div>
  )
}

function Jump() {
  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center gap-2">
        <PixelSprite name="opencode" pixel={2.5} />
        <span className="text-[10px] text-ink">site-vitrine</span>
        <span className="ml-auto text-[8px] text-ink-3">attend depuis 4 min</span>
      </div>

      <div className="rounded-md border border-line bg-white/[0.02] px-2 py-2 text-[9px] text-ink-2">
        <div className="flex items-center gap-2">
          <span className="size-1.5 rounded-full bg-active" />
          <span>Ghostty</span>
          <span className="text-ink-3">· cmux · volet 3</span>
        </div>
        <p className="mt-1.5 text-[8px] text-ink-3">
          Perch retrouve le terminal, l'onglet et le volet où l'agent tourne — puis le passe
          au premier plan.
        </p>
      </div>

      <div className="flex items-center gap-1.5">
        <Key label="Ouvrir la session" hint="⌘⏎" tone="active" />
        <Key label="Plus tard" hint="esc" />
      </div>
    </div>
  )
}

/** A button with its shortcut on it — the panel is meant to be driven without the mouse. */
function Key({ label, hint, tone }: { label: string; hint: string; tone?: "active" }) {
  return (
    <span
      className={cn(
        "flex items-center gap-1.5 rounded-md px-2 py-1 text-[9px]",
        tone === "active" ? "bg-active/15 text-active" : "bg-white/[0.06] text-ink-2",
      )}
    >
      {label}
      <kbd
        className={cn(
          "rounded px-1 text-[8px]",
          tone === "active" ? "bg-active/20" : "bg-white/[0.08] text-ink-3",
        )}
      >
        {hint}
      </kbd>
    </span>
  )
}
