import { useRef, useState } from 'react'
import { motion, useScroll, useTransform, useReducedMotion } from 'framer-motion'
import {
  Search,
  LayoutGrid,
  Star,
  Film,
  Globe,
  Image as ImageIcon,
  Monitor,
  FolderPlus,
  RefreshCw,
  Plus,
  PanelRight,
  Info,
  Settings,
  Check,
  Play,
  FolderOpen,
  MinusCircle,
  PanelLeft,
  Zap,
} from 'lucide-react'
import { SectionHead, Reveal } from '../components/Shared.jsx'
import { MEDIA, VERSION } from '../data/content.js'

/* ------------------------------------------------------------------ */
/* The real library window, rebuilt in DOM: sidebar + gallery grid     */
/* + inspector — Interactive desktop sandbox                          */
/* ------------------------------------------------------------------ */

const SIDE = [
  { icon: LayoutGrid, label: 'All Wallpapers', badge: '2' },
  { icon: Star, label: 'Favorites' },
  { icon: Film, label: 'Video', badge: '2' },
  { icon: Globe, label: 'Web' },
  { icon: ImageIcon, label: 'Images' },
]

const WALLPAPERS = {
  celestial: {
    id: 'celestial',
    title: 'celestial-veil.3840x2160',
    type: 'Video',
    size: '16.6 MB',
    version: '—',
    location: '~/Downloads/cele…l.3840x2160.mp4',
    hasPoster: true,
  },
  live: {
    id: 'live',
    title: 'LiveWallpaper',
    type: 'Video',
    size: '34.2 MB',
    version: '—',
    location: '~/Wallpapers/LiveWallpaper.mp4',
    hasPoster: false,
  },
}

export default function Library() {
  const wrap = useRef(null)
  const reduce = useReducedMotion()
  const [selectedId, setSelectedId] = useState('celestial')
  const [currentDesktopId, setCurrentDesktopId] = useState('celestial')
  const [activeSide, setActiveSide] = useState('All Wallpapers')
  const [appliedNotice, setAppliedNotice] = useState(false)

  const { scrollYProgress } = useScroll({ target: wrap, offset: ['start end', 'start 0.15'] })
  const y = useTransform(scrollYProgress, [0, 1], [90, 0])
  const scale = useTransform(scrollYProgress, [0, 1], [0.95, 1])
  const rotateX = useTransform(scrollYProgress, [0, 1], [6, 0])

  const selectedItem = WALLPAPERS[selectedId]

  const applyWallpaper = () => {
    setCurrentDesktopId(selectedId)
    setAppliedNotice(true)
    setTimeout(() => setAppliedNotice(false), 2200)
  }

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
          aria-label="Tangent Library interface preview"
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
            <aside className="mw-side">
              <div className="mw-search"><Search size={12} /> <span>Search wallpapers</span></div>
              <p className="mw-side-label">Library</p>
              {SIDE.map((s) => (
                <div
                  key={s.label}
                  className={`mw-side-item ${activeSide === s.label ? 'is-active' : ''}`}
                  onClick={() => setActiveSide(s.label)}
                  role="button"
                  tabIndex={0}
                >
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
            <div className="mw-gallery">
              <div className="mw-gallery-head">
                <div>
                  <h3>{activeSide}</h3>
                  <p>2 wallpapers &middot; referenced in place</p>
                </div>
                <span className="chip chip--live"><i className="live-dot" /> Live</span>
              </div>
              <div className="mw-grid">
                {/* Celestial Card */}
                <motion.div
                  className={`mw-card ${selectedId === 'celestial' ? 'is-selected' : ''} ${currentDesktopId === 'celestial' ? 'is-current' : ''}`}
                  onClick={() => setSelectedId('celestial')}
                  role="button"
                  tabIndex={0}
                  initial={reduce ? {} : { opacity: 0, y: 30 }}
                  whileInView={reduce ? {} : { opacity: 1, y: 0 }}
                  viewport={{ once: true }}
                  transition={{ duration: 0.8, delay: 0.25, ease: [0.22, 1, 0.36, 1] }}
                >
                  <div className="mw-card-thumb">
                    <img src={MEDIA.wallpaperPoster} alt="celestial veil wallpaper" width="1280" height="720" loading="lazy" decoding="async" />
                    <span className="chip chip--video">VIDEO</span>
                    <Star size={13} className="mw-card-star" />
                    {currentDesktopId === 'celestial' && (
                      <span className="chip chip--current"><Check size={10} /> Current Desktop</span>
                    )}
                  </div>
                  <div className="mw-card-meta">
                    <strong>celestial-veil.3840x2160</strong>
                    <span>Video</span>
                  </div>
                </motion.div>

                {/* Live Wallpaper Card */}
                <motion.div
                  className={`mw-card ${selectedId === 'live' ? 'is-selected' : ''} ${currentDesktopId === 'live' ? 'is-current' : ''}`}
                  onClick={() => setSelectedId('live')}
                  role="button"
                  tabIndex={0}
                  initial={reduce ? {} : { opacity: 0, y: 30 }}
                  whileInView={reduce ? {} : { opacity: 1, y: 0 }}
                  viewport={{ once: true }}
                  transition={{ duration: 0.8, delay: 0.4, ease: [0.22, 1, 0.36, 1] }}
                >
                  <div className="mw-card-thumb mw-card-thumb--plain">
                    <div className="mw-card-plain" />
                    <span className="chip chip--video">VIDEO</span>
                    <Star size={13} className="mw-card-star" />
                    {currentDesktopId === 'live' && (
                      <span className="chip chip--current"><Check size={10} /> Current Desktop</span>
                    )}
                  </div>
                  <div className="mw-card-meta">
                    <strong>LiveWallpaper</strong>
                    <span>Video</span>
                  </div>
                </motion.div>
              </div>

              <div className="mw-hintbar">
                <span>Click cards to inspect &middot; Double-click to apply</span>
                <span className="mw-hint-keys">&#8984;1 Library &nbsp; &#8984;2 Displays</span>
              </div>
            </div>

            {/* Inspector */}
            <aside className="mw-inspector">
              <div className="mw-insp-head">
                <span>Inspector</span>
                <span className="mw-insp-icons"><Star size={12} /><PanelRight size={12} /></span>
              </div>
              <div className="mw-insp-preview">
                {selectedItem.hasPoster ? (
                  <img src={MEDIA.wallpaperPoster} alt={selectedItem.title} width="1280" height="720" loading="lazy" decoding="async" />
                ) : (
                  <div className="mw-card-plain" style={{ height: '100%', minHeight: 90 }} />
                )}
                <span className="mw-insp-preview-pill"><Play size={10} fill="currentColor" strokeWidth={0} /> Preview</span>
              </div>
              <div className="mw-insp-chips">
                <span className="chip chip--video">Video</span>
                {currentDesktopId === selectedId && (
                  <span className="chip chip--current"><Check size={10} /> Current</span>
                )}
              </div>
              <p className="mw-insp-title">{selectedItem.title}</p>
              <button
                type="button"
                className="mw-insp-btn mw-insp-btn--primary"
                onClick={applyWallpaper}
              >
                {appliedNotice ? <Check size={12} /> : <Monitor size={12} />}
                <span>{appliedNotice ? 'Applied to Screen' : 'Set for This Screen'}</span>
              </button>
              <button type="button" className="mw-insp-btn" onClick={applyWallpaper}>
                <Monitor size={12} /> Set for All Screens
              </button>
              <button type="button" className="mw-insp-btn">
                <FolderOpen size={12} /> Show in Finder
              </button>
              <p className="mw-insp-label">Details</p>
              <dl className="mw-insp-details">
                <div><dt>Type</dt><dd>{selectedItem.type}</dd></div>
                <div><dt>Size</dt><dd>{selectedItem.size}</dd></div>
                <div><dt>Version</dt><dd>{selectedItem.version}</dd></div>
                <div><dt>Location</dt><dd>{selectedItem.location}</dd></div>
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
