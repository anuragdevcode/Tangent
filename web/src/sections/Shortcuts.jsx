import { SectionHead, Reveal, ShortcutRow } from '../components/Shared.jsx'

const SHORTCUTS = [
  { keys: ['⌃', '⌥', 'Space'], label: 'Pause / Resume', desc: 'Mid-flow, mid-anything' },
  { keys: ['⌃', '⌥', '→'], label: 'Next wallpaper', desc: 'Cycle the library' },
  { keys: ['⌃', '⌥', 'L'], label: 'Open the library', desc: 'Where all of this happens' },
  { keys: ['⌃', '⌥', '.'], label: 'Stop the wallpaper', desc: 'Full commitment issues' },
]

export default function Shortcuts() {
  return (
    <section className="section shortcuts-sec">
      <div className="kwrap shortcuts-grid">
        <div className="shortcuts-copy">
          <SectionHead
            align="left"
            size="md"
            eyebrow="Global shortcuts"
            title={<>Zero permission slips required.</>}
            lede="Shortcuts work while another app is frontmost. They're classic Carbon RegisterEventHotKey bindings — no Accessibility or Input Monitoring permission prompts, no scary dialogs, no “let Tangent watch you” pitch. Turn them on when you want them, rebind them per key, flip them off when you don't."
          />
          <Reveal delay={0.2}>
            <p className="section-foot">
              Bindings persist in UserDefaults. Every binding must include Control or Option — so a
              global hotkey can never shadow your app shortcuts. Off by default, because
              cold-calling your keyboard is rude.
            </p>
          </Reveal>
        </div>

        <div className="shortcuts-list">
          <ul>
            {SHORTCUTS.map((s, i) => (
              <ShortcutRow key={s.label} keys={s.keys} label={s.label} desc={s.desc} index={i} />
            ))}
          </ul>
        </div>
      </div>
    </section>
  )
}
