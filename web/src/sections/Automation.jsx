import { motion, useReducedMotion } from 'framer-motion'
import { Zap, Fullscreen, BatteryCharging, Lock, Command } from 'lucide-react'
import { SectionHead, Reveal, Toggle } from '../components/Shared.jsx'

const RULES = [
  {
    icon: Fullscreen,
    title: 'Pause for Fullscreen Apps',
    desc: 'Stop rendering while an app covers the main display.',
    on: true, delay: 0.25,
  },
  {
    icon: BatteryCharging,
    title: 'Pause on Battery',
    desc: 'Save power when the Mac is unplugged.',
    on: true, delay: 0.45,
  },
  {
    icon: Lock,
    title: 'Pause When the Screen Locks',
    desc: 'Stop decoding while the display is asleep or locked.',
    on: true, delay: 0.65,
  },
]

export default function Automation() {
  const reduce = useReducedMotion()
  return (
    <section id="automation" className="section automation-sec">
      <div className="kwrap">
        <SectionHead
          align="center"
          eyebrow="Playback rules"
          title={<>Smart enough to shut up when you&rsquo;re working.</>}
          lede="Tangent can step out of the way automatically. These rules apply to every display — and they pause only the wallpaper, never your applications."
        />
      </div>

      <div className="kwrap">
        <Reveal>
          <div className="autom-card mac-window">
            <div className="autom-status">
              <span className="autom-status-icon"><Zap size={15} /></span>
              <div>
                <strong>Rendering live</strong>
                <span>Wallpapers are playing normally.</span>
              </div>
              <span className="chip chip--live"><i className="live-dot" /> Live</span>
            </div>

            <p className="autom-label">Playback rules</p>
            {RULES.map((r, i) => (
              <motion.div
                key={r.title}
                className="autom-row"
                initial={reduce ? {} : { opacity: 0, y: 18 }}
                whileInView={reduce ? {} : { opacity: 1, y: 0 }}
                viewport={{ once: true, margin: '-10% 0px' }}
                transition={{ duration: 0.6, delay: i * 0.14, ease: [0.22, 1, 0.36, 1] }}
              >
                <span className="autom-row-icon"><r.icon size={14} /></span>
                <div className="autom-row-text">
                  <strong>{r.title}</strong>
                  <span>{r.desc}</span>
                </div>
                <Toggle on={r.on} animate delay={r.delay} />
              </motion.div>
            ))}

            <p className="autom-label">Shortcuts</p>
            <motion.div
              className="autom-row"
              initial={reduce ? {} : { opacity: 0, y: 18 }}
              whileInView={reduce ? {} : { opacity: 1, y: 0 }}
              viewport={{ once: true, margin: '-10% 0px' }}
              transition={{ duration: 0.6, delay: 0.5, ease: [0.22, 1, 0.36, 1] }}
            >
              <span className="autom-row-icon"><Command size={14} /></span>
              <div className="autom-row-text">
                <strong>Global Shortcuts</strong>
                <span>Off by default — enable them to control Tangent from any app.</span>
              </div>
              <Toggle on={false} />
            </motion.div>
          </div>
        </Reveal>

        <Reveal delay={0.15}>
          <p className="section-foot autom-foot">
            Rules are independent: closing a fullscreen app will not undo a manual pause. Changes
            apply immediately and are remembered between launches. Your render loop just quietly
            stops. Nothing else even notices.
          </p>
        </Reveal>
      </div>
    </section>
  )
}
