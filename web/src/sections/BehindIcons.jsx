import { useRef } from 'react'
import { motion, useScroll, useTransform, useReducedMotion } from 'framer-motion'
import { Search, Wifi, BatteryMedium, Menu, PictureInPicture2, SkipForward, Shuffle, Pause, Cog, Heart, Monitor, MonitorOff, VolumeX } from 'lucide-react'
import { SectionHead, Reveal, AmbientVideo } from '../components/Shared.jsx'
import { MEDIA, VERSION, FAVICON } from '../data/content.js'

/* ------------------------------------------------------------------ */
/* macOS desktop mockup: real wallpaper video, menubar, widgets +      */
/* a faithful replica of the menu-bar popover                          */
/* ------------------------------------------------------------------ */

function Menubar() {
  return (
    <div className="mb" aria-hidden="true">
      <div className="mb-left">
        <span className="mb-apple"></span>
        <span className="mb-strong">Finder</span>
        <span>File</span>
        <span>Edit</span>
        <span>View</span>
        <span>Window</span>
        <span>Help</span>
      </div>
      <div className="mb-right">
        <Search size={12} />
        <Wifi size={12} />
        <BatteryMedium size={13} />
        <span className="mb-clock">21:24</span>
      </div>
    </div>
  )
}

function WeatherWidget() {
  return (
    <div className="weather" aria-hidden="true">
      <div className="weather-main">
        <div>
          <p className="weather-city">Dehradun <span className="weather-air">➜</span></p>
          <p className="weather-temp">21&deg;</p>
        </div>
        <div className="weather-now">
          <p className="weather-cond">Cloudy</p>
          <p className="weather-hl">H:23&deg; L:17&deg;</p>
        </div>
      </div>
      <div className="weather-hours">
        {[
          ['5 PM', '21&deg;'],
          ['6 PM', '20&deg;'],
          ['7 PM', '20&deg;'],
          ['8 PM', '19&deg;'],
        ].map(([t, d]) => (
          <div key={t} className="weather-hour">
            <span>{t}</span>
            <span className="weather-dot">&bull;</span>
            <span>{d}</span>
          </div>
        ))}
      </div>
    </div>
  )
}

function LiveDot() {
  return <span className="live-dot" />
}

function Popover() {
  return (
    <div className="popover" aria-hidden="true">
      <div className="popover-head">
        <img src={FAVICON} alt="" className="popover-icon" width="128" height="128" />
        <span className="popover-title">Tangent</span>
        <span className="popover-spacer" />
        <span className="popover-grid"><Menu size={12} /></span>
        <span className="popover-live"><LiveDot /> Live</span>
      </div>

      <div className="popover-thumb">
        <AmbientVideo src={MEDIA.wallpaperVideo} poster={MEDIA.wallpaperPoster} preload="metadata" />
        <span className="chip chip--video">VIDEO</span>
        <div className="popover-thumb-meta">
          <strong>celestial-veil.3840x2160</strong>
          <span>Video</span>
        </div>
      </div>

      <div className="popover-actions">
        <span className="pbtn pbtn--primary"><Pause size={11} fill="currentColor" strokeWidth={0} /> Pause</span>
        <span className="pbtn"><SkipForward size={11} /></span>
        <span className="pbtn"><Shuffle size={11} /></span>
      </div>

      <div className="popover-labels">
        <span>Displays</span>
        <span className="popover-manage">Manage</span>
      </div>
      <div className="popover-display">
        <Monitor size={13} />
        <span>Built-in Retina Display</span>
        <span className="chip chip--blue">Pinned</span>
      </div>

      <div className="popover-switches">
        <div className="popover-switch">
          <PictureInPicture2 size={13} />
          <span>Pause Wallpaper</span>
          <span className="toggle is-off"><span className="toggle-knob" style={{ transform: 'none' }} /></span>
        </div>
        <div className="popover-switch popover-switch--muted">
          <VolumeX size={13} />
          <span>Mute Audio</span>
          <span className="toggle is-on"><span className="toggle-knob" style={{ transform: 'translateX(100%)' }} /></span>
        </div>
        <div className="popover-switch">
          <MonitorOff size={13} />
          <span>Hide Desktop Icons</span>
          <span className="toggle is-on"><span className="toggle-knob" style={{ transform: 'translateX(100%)' }} /></span>
        </div>
      </div>

      <div className="popover-foot">
        <span><Cog size={12} /> Preferences&hellip;</span>
        <span className="popover-foot-right"><Heart size={12} /> Quit</span>
      </div>
    </div>
  )
}

export default function BehindIcons() {
  const wrap = useRef(null)
  const reduce = useReducedMotion()
  const { scrollYProgress } = useScroll({ target: wrap, offset: ['start end', 'start 0.12'] })

  const scale = useTransform(scrollYProgress, [0, 1], [0.92, 1])
  const rotateX = useTransform(scrollYProgress, [0, 1], [7, 0])
  const y = useTransform(scrollYProgress, [0, 1], [70, 0])
  const glow = useTransform(scrollYProgress, [0, 1], [0.25, 0.8])

  return (
    <section id="behind-icons" className="section behind">
      <div className="kwrap">
        <SectionHead
          align="left"
          eyebrow="Hide desktop icons — no willpower required"
          title={<>Your desktop icons are ruining the wallpaper. Hide them.</>}
          lede="One switch in the popover or under Automation ▸ Shortcuts hides every icon, because a wallpaper you can’t see is just an expensive screensaver. Flip it on for a suspiciously calm desktop — and off when you need that one file you saved there three years ago. It’s not avoidance. It’s curation."
        />
      </div>

      <div className="kwrap">
        <div className="behind-stage" ref={wrap}>
          <motion.div
            className="glow"
            aria-hidden="true"
            style={reduce ? { opacity: 0.6 } : { opacity: glow }}
          />
          <motion.div
            className="desktop-mock"
            style={reduce ? {} : { scale, rotateX, y, transformPerspective: 1400 }}
          >
            <Menubar />
            <AmbientVideo
              className="desktop-wallpaper"
              src={MEDIA.wallpaperVideo}
              poster={MEDIA.wallpaperPoster}
              preload="auto"
            />
            <WeatherWidget />
          </motion.div>

          <motion.div
            className="behind-popover"
            initial={reduce ? {} : { opacity: 0, y: 40 }}
            whileInView={reduce ? {} : { opacity: 1, y: 0 }}
            viewport={{ once: true, margin: '-10% 0px' }}
            transition={{ duration: 1, delay: 0.35, ease: [0.22, 1, 0.36, 1] }}
          >
            <Popover />
          </motion.div>
        </div>

        <p className="mini-caption">
          The real menu-bar popover, playing the real wallpaper. Wallpapers shown here remain the
          property of their creators — see the attribution note in the footer.
        </p>
      </div>

      <div className="kwrap">
        <Reveal delay={0.1}>
          <div className="layer-stack" aria-label="Desktop layering diagram">
            <div className="layer-row">
              <span className="layer-bar">kCGDesktopWindowLevel · static desktop picture</span>
            </div>
            <div className="layer-row layer-row--hero">
              <span className="layer-bar">← Tangent&rsquo;s wallpaper window</span>
            </div>
            <div className="layer-row">
              <span className="layer-bar">kCGDesktopIconWindowLevel · your icons</span>
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  )
}
