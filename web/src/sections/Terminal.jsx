import { useState } from 'react'
import { Copy, Check } from 'lucide-react'
import { SectionHead, Reveal } from '../components/Shared.jsx'

const LINES = [
  { p: '# three commands and a Mac', c: 'comment' },
  { p: '$ git clone https://github.com/anuragdevcode/Tangent.git', c: 'cmd' },
  { p: '$ cd Tangent && brew install mpv        # build-time headers', c: 'cmd' },
  { p: '$ ./build.sh --universal                 # arm64 (+ x86_64)', c: 'cmd' },
  { p: '$ open build/Tangent.app                 # menu bar appears', c: 'cmd' },
]

const COMMANDS_RAW = `git clone https://github.com/anuragdevcode/Tangent.git
cd Tangent && brew install mpv
./build.sh --universal
open build/Tangent.app`

const FLAGS = [
  ['--set ~/Wallpapers/aurora --display 2 --ephemeral', 'apply to one display, don\'t touch the layout'],
  ['--library', 'open the library window at launch'],
  ['--probe-mpv loop.webm', 'decode a codec stack and print frames'],
  ['--snapshot-library /tmp/lib.png', 'render the UI to PNG, no screen-recording perms'],
  ['--test', 'the 301-check compatibility suite'],
]

export default function Terminal() {
  const [copied, setCopied] = useState(false)
  const [copiedFlag, setCopiedFlag] = useState(null)

  const copyCommands = () => {
    if (navigator?.clipboard) {
      navigator.clipboard.writeText(COMMANDS_RAW).then(() => {
        setCopied(true)
        setTimeout(() => setCopied(false), 2200)
      })
    }
  }

  const copyFlag = (flag) => {
    if (navigator?.clipboard) {
      navigator.clipboard.writeText(flag).then(() => {
        setCopiedFlag(flag)
        setTimeout(() => setCopiedFlag(null), 2000)
      })
    }
  }

  return (
    <section id="terminal" className="section term-sec">
      <div className="kwrap">
        <SectionHead
          align="left"
          eyebrow="Build from source"
          title={<>For people who read the makefile.</>}
          lede="No Xcode required — Command Line Tools and swiftc are enough. Homebrew mpv is a build-time dependency; the app bundles libmpv and its dependency closure so VP9, AV1 and Matroska play without Homebrew at runtime."
        />
      </div>

      <div className="kwrap">
        <Reveal>
          <div className="terminal mac-window" data-native-scroll>
            <div className="mw-bar">
              <span className="mw-dots" aria-hidden="true"><i /><i /><i /></span>
              <span className="mw-title">Terminal — Tangent</span>
              <button
                type="button"
                className={`term-copy-btn ${copied ? 'is-copied' : ''}`}
                onClick={copyCommands}
                aria-label="Copy build commands"
                title="Copy clean commands without prompts"
              >
                {copied ? <Check size={12} strokeWidth={2.4} /> : <Copy size={12} />}
                <span>{copied ? 'Copied' : 'Copy commands'}</span>
              </button>
            </div>
            <pre className="term-body" tabIndex={0} role="region" aria-label="Build commands">
              {LINES.map((l, i) => (
                <code key={i} className={`term-${l.c}`}>
                  {l.p}
                </code>
              ))}
              <code className="term-cursor" aria-hidden="true">▮</code>
            </pre>
          </div>
        </Reveal>

        <Reveal delay={0.1}>
          <div className="flag-grid">
            <p className="flag-title">And if your wallpaper pipeline is scripted, it&rsquo;s a first-class citizen:</p>
            {FLAGS.map(([flag, desc]) => (
              <div
                key={flag}
                className="flag-row flag-row--interactive"
                onClick={() => copyFlag(flag)}
                role="button"
                tabIndex={0}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault()
                    copyFlag(flag)
                  }
                }}
                aria-label={`Copy CLI flag ${flag}`}
                title="Click to copy flag"
              >
                <code className="flag-cmd">{flag}</code>
                <span>{desc}</span>
                <span className="flag-copy-pill" aria-hidden="true">
                  {copiedFlag === flag ? <Check size={11} strokeWidth={2.4} /> : <Copy size={11} />}
                  <span>{copiedFlag === flag ? 'Copied' : 'Copy'}</span>
                </span>
              </div>
            ))}
          </div>
        </Reveal>
      </div>
    </section>
  )
}
