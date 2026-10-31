import { useRef } from 'react'
import { motion, useScroll, useTransform, useReducedMotion } from 'framer-motion'
import {
  Search, LayoutGrid, Star, Film, Globe, Image as ImageIcon, Monitor, ExternalLink,
  FolderPlus, RefreshCw, Plus, PanelRight, Info, Settings, Check, Play, FolderOpen,
  MinusCircle, PanelLeft, Zap,
} from 'lucide-react'
import { SectionHead, Reveal } from '../components/Shared.jsx'
import { MEDIA, VERSION } from '../data/content.js'

/* ------------------------------------------------------------------ */
/* The real library window, rebuilt in DOM: sidebar + gallery grid     */
/* + inspector — Room for the true screenshot composition              */
/* ------------------------------------------------------------------ */

const SIDE = [
  { icon: LayoutGrid, label: 'All Wallpapers', badge: '2', active: true },
  { icon: Star, label: 'Favorites' },
  { icon: Film, label: 'Video', badge: '2' },
  { icon: Globe, label: 'Web' },
  { icon: ImageIcon, label: 'Images' },
]

export default function Library() {
  const wrap = useRef(null)
  const reduce = useReducedMotion()
  const { scrollYProgress } = useScroll({ target: wrap, offset: ['start end', 'start 0.15'] })
  const y = useTransform(scrollYProgress, [0, 1], [90, 0])
  const scale = useTransform(scrollYProgress, [0, 1], [0.95, 1])
  const rotateX = useTransform(scrollYProgress, [0, 1], [6, 0])

  return (
    <section id="library" className="section library-sec">
      <div className="kwrap">
        <SectionHead
          align="left"
          eyebrow="The library"
          title={<>A real library. Not a folder you&rsquo;re afraid to open.</>}
          lede="Point Tangent at your pack folders — they're referenced in place, never copied or locked away. Search across titles, authors, summaries and tags, favourite the good ones, peek a muted live preview on hover, and apply with intent: double-click, Return, or the card menu."
        />
      </div>

      <div className="kwrap" ref={wrap}>
        <motion.div
          className="mac-window library-window"
          style={reduce ? {} : { y, scale, rotateX, transformPerspective: 1600 }}
          aria-hidden="true"
        >
          <div className="mw-bar">
            <span className="mw-dots" aria-hidden="true"><i /><i /><i /></span>
            <span className="mw-side-btn"><PanelLeft size={13} /></span>
            <span className="mw-toolbar">
              <span className="mw-tool"><Plus size={13} /></span>
              <span className="mw-tool mw-tool--accent"><FolderPlus size={13} /></span>
              <span className="mw-tool"><RefreshCw size={13} /></span>
            </span>
            <span className="mw-transparent" />
            <span className="mw-panel-btn"><PanelRight size={13} /></span>
          </div>

          <div className="mw-body">
            {/* Sidebar */}
            <aside className="mw-side" aria-hidden="true">
              <div className="mw-search"><Search size={12} /> <span>Search wallpapers</span></div>
              <p className="mw-side-label">Library</p>
              {SIDE.map((s) => (
                <div key={s.label} className={`mw-side-item ${s.active ? 'is-active' : ''}`}>
                  <s.icon size={13} />
                  <span>{s.label}</span>
                  {s.badge && <span className="mw-side-badge">{s.badge}</span>}
                </div>
              ))}
              <p className="mw-side-label">System</p>
              <div className="mw-side-item"><Monitor size={13} /> <span>Displays</span></div>
              <div className="mw-side-item"><Zap size={13} /> <span>Automation</span></div>
              <div className="mw-side-spacer" />
              <p className="mw-side-label">About</p>
              <div className="mw-side-item"><Info size={13} /> <span>About Tangent</span></div>
              <div className="mw-foot"><Settings size={12} /> <span>Tangent {VERSION}</span></div>
            </aside>

            {/* Gallery */}
            <div className="mw-gallery" aria-hidden="true">
              <div className="mw-gallery-head">
                <div>
                  <h3>All Wallpapers</h3>
                  <p>2 wallpapers &middot; referenced in place</p>
                </div>
                <span className="chip chip--live"><i className="live-dot" /> Live</span>
              </div>
              <div className="mw-grid">
                <motion.div
                  className="mw-card is-current"
                  initial={reduce ? {} : { opacity: 0, y: 30 }}
                  whileInView={reduce ? {} : { opacity: 1, y: 0 }}
                  viewport={{ once: true }}
                  transition={{ duration: 0.8, delay: 0.25, ease: [0.22, 1, 0.36, 1] }}
                >
                  <div className="mw-card-thumb">
                    <img src={MEDIA.wallpaperPoster} alt="" width="1280" height="720" loading="lazy" decoding="async" />
                    <span className="chip chip--video">VIDEO</span>
                    <Star size={13} className="mw-card-star" />
                    <span className="chip chip--current"><Check size={10} /> Current Desktop</span>
                  </div>
                  <div className="mw-card-meta">
                    <strong>celestial-veil.3840x2160</strong>
                    <span>Video</span>
                  </div>
                </motion.div>

                <motion.div
                  className="mw-card"
                  initial={reduce ? {} : { opacity: 0, y: 30 }}
                  whileInView={reduce ? {} : { opacity: 1, y: 0 }}
                  viewport={{ once: true }}
                  transition={{ duration: 0.8, delay: 0.4, ease: [0.22, 1, 0.36, 1] }}
                >
                  <div className="mw-card-thumb mw-card-thumb--plain">
                    <div className="mw-card-plain" />
                    <span className="chip chip--video">VIDEO</span>
                    <Star size={13} className="mw-card-star" />
                  </div>
                  <div className="mw-card-meta">
                    <strong>LiveWallpaper</strong>
                    <span>Video</span>
                  </div>
                </motion.div>
              </div>

              <div className="mw-hintbar">
                <span>Double-click to apply &middot; Space for live preview</span>
                <span className="mw-hint-keys">&#8984;1 Library &nbsp; &#8984;2 Displays</span>
              </div>
            </div>

            {/* Inspector */}
            <aside className="mw-inspector" aria-hidden="true">
              <div className="mw-insp-head">
                <span>Inspector</span>
                <span className="mw-insp-icons"><Star size={12} /><PanelRight size={12} /></span>
              </div>
              <div className="mw-insp-preview">
                <img src={MEDIA.wallpaperPoster} alt="" width="1280" height="720" loading="lazy" decoding="async" />
                <span className="mw-insp-preview-pill"><Play size={10} fill="currentColor" strokeWidth={0} /> Preview</span>
              </div>
              <div className="mw-insp-chips">
                <span className="chip chip--video">Video</span>
                <span className="chip chip--current"><Check size={10} /> Current</span>
              </div>
              <p className="mw-insp-title">celestial-veil.3840x2160</p>
              <button className="mw-insp-btn mw-insp-btn--primary" tabIndex={-1}>
                <Monitor size={12} /> Set for This Screen
              </button>
              <button className="mw-insp-btn" tabIndex={-1}>
                <Monitor size={12} /> Set for All Screens
              </button>
              <button className="mw-insp-btn" tabIndex={-1}>
                <FolderOpen size={12} /> Show in Finder
              </button>
              <p className="mw-insp-label">Details</p>
              <dl className="mw-insp-details">
                <div><dt>Type</dt><dd>Video</dd></div>
                <div><dt>Size</dt><dd>16.6 MB</dd></div>
                <div><dt>Version</dt><dd>—</dd></div>
                <div><dt>Location</dt><dd>~/Downloads/cele&hellip;l.3840x2160.mp4</dd></div>
              </dl>
              <p className="mw-insp-remove"><MinusCircle size={12} /> Remove from Library&hellip;</p>
            </aside>
          </div>
        </motion.div>
      </div>

      <div className="kwrap">
        <Reveal delay={0.1}>
          <p className="section-foot">
            Editing a wallpaper while it&rsquo;s live? It stays edited — the library references your
            files, it doesn&rsquo;t kidnap them. Removing from the library never deletes anything;
            hidden packs can be restored in Settings.
          </p>
        </Reveal>
      </div>
    </section>
  )
}
