#!/usr/bin/env python3
"""Generate the README illustration from original sample content and real controls."""
import base64
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
controls = base64.b64encode((ROOT / "docs/assets/controls-en.png").read_bytes()).decode()
svg = '''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1280" height="700" viewBox="0 0 1280 700" role="img" aria-labelledby="title desc">
<title id="title">Keep your reference. Keep your flow.</title>
<desc id="desc">An illustrated desktop with a release checklist floating over a draft. OnTop's real hover controls sit above the checklist. Sample content, not a screen capture.</desc>
<defs>
  <linearGradient id="bg" x2="1" y2="1"><stop stop-color="#eef1ff"/><stop offset="1" stop-color="#e8eff4"/></linearGradient>
  <linearGradient id="card" x2="0" y2="1"><stop stop-color="#fff"/><stop offset="1" stop-color="#fafbff"/></linearGradient>
  <filter id="shadow" x="-30%" y="-30%" width="160%" height="180%"><feDropShadow dx="0" dy="16" stdDeviation="24" flood-color="#263251" flood-opacity=".14"/></filter>
  <filter id="smallShadow" x="-20%" y="-50%" width="140%" height="220%"><feDropShadow dx="0" dy="5" stdDeviation="9" flood-color="#263251" flood-opacity=".14"/></filter>
  <pattern id="grid" width="32" height="32" patternUnits="userSpaceOnUse"><circle cx="1" cy="1" r="1" fill="#7987ba" opacity=".15"/></pattern>
</defs>
<rect width="1280" height="700" rx="24" fill="url(#bg)"/>
<rect width="1280" height="700" rx="24" fill="url(#grid)"/>
<g font-family="-apple-system, BlinkMacSystemFont, Helvetica Neue, Helvetica, Arial, sans-serif">
  <text x="76" y="75" font-size="13" letter-spacing="3" font-weight="700" fill="#6269a0">ONTOP FOR MACOS</text>
  <text x="76" y="128" font-size="40" letter-spacing="-1.3" font-weight="700" fill="#202943">Keep your reference.</text>
  <text x="76" y="175" font-size="40" letter-spacing="-1.3" font-weight="700" fill="#6267d9">Keep your flow.</text>

  <g filter="url(#shadow)">
    <rect x="76" y="230" width="970" height="378" rx="14" fill="#fff"/>
    <path d="M90 230H1032Q1046 230 1046 244V277H76V244Q76 230 90 230Z" fill="#f8f9fc"/>
    <path d="M76 277H1046" stroke="#e9ebf2"/>
    <circle cx="99" cy="254" r="5" fill="#ff817a"/><circle cx="117" cy="254" r="5" fill="#f7ce6f"/><circle cx="135" cy="254" r="5" fill="#80c99b"/>
    <text x="182" y="259" font-size="13" fill="#7c8498">Draft — Launch announcement</text>
    <rect x="76" y="278" width="178" height="316" fill="#fbfcff"/>
    <text x="99" y="315" font-size="10" letter-spacing="1.5" font-weight="700" fill="#98a0b3">WORKSPACE</text>
    <rect x="89" y="332" width="150" height="32" rx="6" fill="#edf0fc"/>
    <text x="101" y="353" font-size="12" font-weight="600" fill="#6267b5">Launch announcement</text>
    <text x="101" y="389" font-size="12" fill="#8e96a9">Product notes</text>
    <text x="101" y="425" font-size="12" fill="#8e96a9">Ideas for next week</text>
    <path d="M254 278V608" stroke="#edf0f6"/>

    <text x="296" y="330" font-size="11" letter-spacing="1.6" font-weight="600" fill="#949bb1">IN PROGRESS</text>
    <text x="295" y="372" font-size="27" font-weight="700" letter-spacing="-.6" fill="#2f3850">A little less window juggling.</text>
    <text x="297" y="414" font-size="16" fill="#647089">Docs open. Notes ready. One thing at a time.</text>
    <text x="297" y="444" font-size="16" fill="#647089">A small tool that makes room for your work.</text>
    <text x="297" y="489" font-size="16" fill="#49556f">Today, we’re shipping OnTop.</text>
    <path d="M505 473V494" stroke="#6267d9" stroke-width="2"/>
    <path d="M297 523H667M297 544H608M297 565H644" stroke="#eef0f6" stroke-width="7" stroke-linecap="round"/>
  </g>

  <g filter="url(#shadow)">
    <rect x="772" y="203" width="432" height="314" rx="12" fill="url(#card)" stroke="#dce1f1"/>
    <rect x="797" y="228" width="91" height="24" rx="12" fill="#eeedfd"/>
    <text x="842" y="244" text-anchor="middle" font-size="10" font-weight="700" letter-spacing="1" fill="#7270b7">REFERENCE</text>
    <text x="797" y="289" font-size="26" font-weight="700" letter-spacing="-.6" fill="#30384f">Release checklist</text>
    <text x="797" y="316" font-size="13" fill="#8a93a7">The details stay in view. You stay in the flow.</text>
    <path d="M797 334H1179" stroke="#e8ebf4"/>
    <g fill="#edf6f1" stroke="#b7d8c7"><rect x="798" y="355" width="18" height="18" rx="5"/><rect x="798" y="397" width="18" height="18" rx="5"/></g>
    <g fill="none" stroke="#5d9d7d" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M803 364L806 367L811 361"/><path d="M803 406L806 409L811 403"/></g>
    <text x="832" y="369" font-size="15" fill="#64758a">Build for Apple Silicon + Intel</text>
    <text x="832" y="411" font-size="15" fill="#64758a">Run the tests</text>
    <rect x="798" y="439" width="18" height="18" rx="5" fill="#fff" stroke="#cad1e4"/>
    <text x="832" y="453" font-size="15" font-weight="600" fill="#495571">Write the announcement</text>
    <text x="797" y="491" font-size="11" fill="#a0a8bb">A live preview of the window you choose</text>
  </g>
  <g filter="url(#smallShadow)"><image x="788" y="151" width="400" height="44" xlink:href="data:image/png;base64,CONTROLS"/></g>
  <path d="M961 124V141" stroke="#858bc3" stroke-width="1.5" stroke-linecap="round"/>
  <text x="961" y="112" text-anchor="middle" font-size="13" fill="#747ca3">Hover for controls</text>

  <path d="M739 484L743 508L749 501L757 501Z" fill="#6267d9" stroke="#fff" stroke-width="2" stroke-linejoin="round"/>
  <path d="M751 521Q774 573 858 570" fill="none" stroke="#8389c6" stroke-width="1.5" stroke-dasharray="4 5"/>
  <text x="874" y="575" font-size="13" font-weight="500" fill="#67729a">Clicks pass through</text>

  <text x="76" y="653" font-size="13" font-weight="500" fill="#6b7591">Native macOS app</text>
  <circle cx="224" cy="649" r="2" fill="#a3abc0"/>
  <text x="241" y="653" font-size="13" font-weight="500" fill="#6b7591">No account. No tracking.</text>
  <text x="1204" y="653" text-anchor="end" font-size="13" font-weight="600" fill="#737bae">Small by design.</text>
</g>
</svg>
'''
target = ROOT / "docs/assets/hero.svg"
target.write_text(svg.replace("CONTROLS", controls))
print(f"Wrote {target.relative_to(ROOT)}")
