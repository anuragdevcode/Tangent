import { motion, useReducedMotion } from 'framer-motion'
import { Pin, PowerOff, Repeat2 } from 'lucide-react'
import { SectionHead, Reveal } from '../components/Shared.jsx'
import { MEDIA } from '../data/content.js'

const SCREENS = [
  {
    name: 'Built-in Retina Display',
    state: 'Main',
    wallpaper: MEDIA.wallpaperPoster,
    cls: '',
    delay: 0,
  },
  {
    name: 'External Display',
    state: 'Pinned',
    wallpaper: null,
    cls: 'is-plain',
    delay: 0.14,
  },
  {
    name: 'Second Display',
    state: 'Turned off',
    wallpaper: null,
    cls: 'is-off',
    delay: 0.28,
  },
]

export default function Displays() {
  const reduce = useReducedMotion()
  return (
    <section className="section displays-sec">
      <div className="kwrap">
        <SectionHead
          align="left"
          eyebrow="Displays"
          title={<>Every display gets its own opinion.</>}
          lede="Each connected screen runs its own desktop-level window and its own player. Follow the wallpaper applied globally, pin one display to its own wallpaper, or turn a screen off entirely. Assignments are keyed by CGDirectDisplayID, so they survive restarts and reconnects."
        />
      </div>

      <div className="kwrap">
        <div className="displays-grid">
          {SCREENS.map((s) => (
            <motion.div
              key={s.name}
              className={`display-card ${s.cls}`}
              initial={reduce ? {} : { opacity: 0, y: 34 }}
              whileInView={reduce ? {} : { opacity: 1, y: 0 }}
              viewport={{ once: true, margin: '-10% 0px' }}
              transition={{ duration: 0.8, delay: s.delay, ease: [0.22, 1, 0.36, 1] }}
            >
              <div className="display-screen">
                {s.wallpaper ? <img src={s.wallpaper} alt="" width="1280" height="720" loading="lazy" decoding="async" /> : null}
                {!s.wallpaper && s.cls === 'is-plain' && <div className="display-plain" />}
                <span className="display-menubar" />
              </div>
              <div className="display-meta">
                <strong>{s.name}</strong>
                <span className={`chip ${s.cls === 'is-off' ? 'chip--dim' : 'chip--blue'}`}>
                  {s.cls === 'is-off' ? <PowerOff size={10} /> : s.cls === 'is-plain' ? <Pin size={10} /> : null}
                  {s.state}
                </span>
              </div>
            </motion.div>
          ))}
        </div>

        <Reveal delay={0.2}>
          <p className="section-foot displays-foot">
            <Repeat2 size={15} />
            One wallpaper per display — spanning across monitors is deliberately out of scope.
            Use the same wallpaper on each screen for a cloned look; per-display wallpapers for
            everything less boring.
          </p>
        </Reveal>
      </div>
    </section>
  )
}
