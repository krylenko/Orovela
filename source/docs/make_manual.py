"""Orovela user manual generator — companion to make_card.py (same palette/type).

ALL TEXT lives in OROVELA_user_manual.md (format rules at the top of that file).
Edit the markdown, then:   python3 make_manual.py [source.md] [output.pdf]
pip install reportlab pypdf --break-system-packages

Landscape letter, 4 columns, panel close-ups (vertical button strips) across the top of
page 1. Auto scale-search: the largest type that fits on ONE page with no column spill;
if nothing fits it says so (shorten the text)."""
import re, sys
from xml.sax.saxutils import escape
from reportlab.lib.pagesizes import letter, landscape
from reportlab.lib.units import inch
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib import colors
from reportlab.platypus import (BaseDocTemplate, Frame, PageTemplate, Paragraph, KeepTogether,
                                FrameBreak, Flowable)
from pypdf import PdfReader

SRC = sys.argv[1] if len(sys.argv) > 1 else 'OROVELA_user_manual.md'
OUT = sys.argv[2] if len(sys.argv) > 2 else re.sub(r'\.md$', '', SRC) + '.pdf'

PAGE = landscape(letter); W, H = PAGE; M = 0.40*inch; NCOL = 4; GUT = 0.20*inch
colw = (W - 2*M - (NCOL-1)*GUT)/NCOL
THEMES = {   # accent, section band, muted text, tag sub-label, tip bg, tip border, dark text
  'green':    ('#1b5e20', '#e8f5e9', '#5e7d62', '#b9d8bb', '#f4f7f4', '#a5c9a8', '#2f3b30'),
  'lavender': ('#5b4a8b', '#eeeaf6', '#7c7299', '#d3cbe8', '#f6f4fa', '#bfb3dc', '#36304a'),
}
ACC = GRP = MID = SUBC = TIPBG = TIPBD = DARK = None
def set_theme(name):
    global ACC, GRP, MID, SUBC, TIPBG, TIPBD, DARK
    if name not in THEMES: raise SystemExit('unknown theme %r (have: %s)' % (name, ', '.join(THEMES)))
    ACC, GRP, MID, SUBC, TIPBG, TIPBD, DARK = [colors.HexColor(h) for h in THEMES[name]]
PANEL = colors.HexColor('#2a2b2d'); WELL = colors.HexColor('#1c1d1f')
CAP = colors.HexColor('#d8d6d0'); CAPSH = colors.HexColor('#0e0f10')
LEG = colors.HexColor('#e9e9e4')
TOPH = 0.5*inch           # header bar
ROW = 0.36*inch           # button pitch in a vertical strip

# ================================================================ markdown source
def inline(t):
    t = escape(t.strip()).replace(' -- ', ' – ').replace('--', '–')
    return re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', t)

def parse(path):
    txt = re.sub(r'<!--.*?-->', '', open(path, encoding='utf-8').read(), flags=re.S)
    meta = {'version': '', 'footer': '', 'title': 'streamlined Ensoniq Mirage OS — User Manual', 'theme': 'green'}
    panels, cols = [], []
    cur = None          # current panel dict, or None when in a column
    para = []
    def flush():
        if para and cols:
            cols[-1].append(('P', inline(' '.join(para))))
        para.clear()
    for raw in txt.splitlines():
        line = raw.rstrip()
        s = line.strip()
        m = re.match(r'^(version|footer|title|theme):\s*(.*)$', s)
        if m and not cols and cur is None:
            meta[m.group(1)] = m.group(2); continue
        if s.startswith('# '):
            flush()
            head = s[2:].strip()
            kind, _, title = head.partition(' ')
            kind = kind.upper()
            if kind == 'PANEL':
                cur = {'kind': 'panel', 'title': title.strip(), 'buttons': [], 'both': None}
                panels.append(cur)
            elif kind == 'WINDOW':
                cur = {'kind': 'window', 'title': title.strip(), 'span': 3, 'rows': [], 'top': [],
                       'bottom': [], 'columns': [], 'status': '', 'toplabel': '', 'bottomlabel': '',
                       'select': -1}
                panels.append(cur)
            elif kind == 'NOTE':
                cur = {'kind': 'note', 'title': title.strip(), 'lines': []}
                panels.append(cur)
            elif kind == 'COLUMN':
                cur = None; cols.append([])
            else:
                raise SystemExit('unknown top-level heading: %r' % s)
            continue
        if cur is not None:                       # inside a panel / note
            if not s: continue
            if cur['kind'] == 'window':
                key, _, val = s.partition(':')
                key = key.strip().lower(); cells = [v.strip() for v in val.split('|')]
                if key in ('top', 'bottom', 'columns'): cur[key] = cells
                elif key == 'row': cur['rows'].append(cells)
                elif key == 'selected': cur['select'] = int(val)
                elif key == 'span': cur['span'] = int(val)
                elif key in ('status', 'toplabel', 'bottomlabel'): cur[key] = val.strip()
                else: raise SystemExit('bad window line: %r' % s)
            elif cur['kind'] == 'panel':
                if s.startswith('- '):
                    parts = [p.strip() for p in s[2:].split('|')] + ['', '']
                    cur['buttons'].append(tuple(parts[:3]))
                elif s.lower().startswith('both:'):
                    parts = [p.strip() for p in s[5:].split('|')] + ['']
                    cur['both'] = tuple(parts[:2])
                else:
                    raise SystemExit('bad panel line: %r' % s)
            else:
                cur['lines'].append(inline(s))
            continue
        if not cols:
            if s: raise SystemExit('text before the first "# COLUMN": %r' % s)
            continue
        if not s:
            flush(); continue
        col = cols[-1]
        if s.startswith('### '):
            flush(); col.append(('S', inline(s[4:])))
        elif s.startswith('## '):
            flush(); col.append(('H', inline(s[3:])))
        elif re.match(r'^\d+[.)]\s', s):
            flush(); txtp = re.sub(r'^\d+[.)]\s+', '', s)
            if col and col[-1][0] == 'N': col[-1][1].append(inline(txtp))
            else: col.append(('N', [inline(txtp)]))
        elif s.startswith('- ') or s.startswith('* '):
            flush()
            lvl = 1 if line[:1] in (' ', '\t') else 0      # indented = sub-bullet
            if col and col[-1][0] == 'B': col[-1][1].append((lvl, inline(s[2:])))
            else: col.append(('B', [(lvl, inline(s[2:]))]))
        elif s.startswith('>'):
            flush()
            if col and col[-1][0] == 'T': col[-1] = ('T', col[-1][1] + ' ' + inline(s[1:]))
            else: col.append(('T', inline(s[1:])))
        else:
            para.append(s)
    flush()
    if sum(p.get('span', 1) for p in panels) > NCOL: raise SystemExit('panels/notes/window exceed %d slots' % NCOL)
    if len(cols) > NCOL: raise SystemExit('at most %d columns' % NCOL)
    return meta, panels, cols

META, PANELS, COLS = parse(SRC)
set_theme(META['theme'])

def strip_height():
    rows = 0
    for p in PANELS:
        if p['kind'] == 'panel':
            rows = max(rows, len(p['buttons']) + (0.9 if p['both'] else 0))
    hgt = 0.36*inch + rows*ROW + 0.12*inch if rows else 0
    for p in PANELS:
        if p['kind'] == 'window':
            hgt = max(hgt, (1.27 + 0.135*(len(p['rows'])+1))*inch)
    return hgt or 1.6*inch
STRIP = strip_height()

# ================================================================ panel close-ups
class PanelStrip(Flowable):
    """Close-ups of Mirage button sets drawn as VERTICAL strips, relabelled for Orovela.
    One slot per grid column; a NOTE renders as a pale text box instead."""
    def __init__(self, width, height):
        super().__init__(); self.width = width; self.height = height
    def wrap(self, aw, ah): return self.width, self.height
    def draw(self):
        c = self.canv
        y0, ph = 0.05*inch, self.height - 0.05*inch
        slot = 0
        for p in PANELS:
            x = slot*(colw + GUT); span = p.get('span', 1)
            w = span*colw + (span-1)*GUT; slot += span
            if p['kind'] == 'note': self.note(c, p, x, y0, w, ph)
            elif p['kind'] == 'window': self.window(c, p, x, y0, w, ph)
            else: self.panel(c, p, x, y0, w, ph)

    def button(self, c, text, x, y, h=0.20*inch, fs=6.8):
        w = c.stringWidth(text, 'Helvetica', fs) + 0.18*inch
        c.setFillColor(colors.HexColor('#e3e3e3')); c.setStrokeColor(colors.HexColor('#a9a9a9'))
        c.setLineWidth(0.6); c.roundRect(x, y, w, h, 2, stroke=1, fill=1)
        c.setFillColor(colors.HexColor('#1e1e1e')); c.setFont('Helvetica', fs)
        c.drawCentredString(x+w/2, y+h/2-fs*0.35, text)
        return w

    def window(self, c, p, x, y0, w, ph):
        """A schematic of the Sample Manager window, drawn from the WINDOW block."""
        tb = 0.22*inch
        c.setFillColor(colors.HexColor('#f4f4f4')); c.setStrokeColor(colors.HexColor('#8e8e8e'))
        c.setLineWidth(0.8); c.roundRect(x, y0, w, ph, 5, stroke=1, fill=1)
        # title bar
        c.setFillColor(colors.HexColor('#3b3946')); c.roundRect(x, y0+ph-tb, w, tb, 5, stroke=0, fill=1)
        c.rect(x, y0+ph-tb, w, tb/2, stroke=0, fill=1)
        c.setFillColor(colors.white); c.setFont('Helvetica-Bold', 7.6)
        c.drawString(x+0.12*inch, y0+ph-tb+0.07*inch, p['title'])
        cy = y0+ph-tb/2; c.setStrokeColor(colors.white); c.setLineWidth(0.8); g = 0.035*inch
        cx0 = x+w-0.16*inch                                    # close, maximize, minimize
        c.line(cx0-g, cy-g, cx0+g, cy+g); c.line(cx0-g, cy+g, cx0+g, cy-g)
        c.rect(cx0-0.22*inch-g, cy-g, 2*g, 2*g, stroke=1, fill=0)
        c.line(cx0-0.44*inch-g, cy, cx0-0.44*inch+g, cy)
        pad = 0.14*inch
        def label(text, lx, ly):
            if not text: return
            tw = c.stringWidth(text, 'Helvetica-Bold', 7.0) + 12
            c.setFillColor(ACC); c.roundRect(lx, ly, tw, 0.165*inch, 2.5, stroke=0, fill=1)
            c.setFillColor(colors.white); c.setFont('Helvetica-Bold', 7.0)
            c.drawCentredString(lx+tw/2, ly+0.047*inch, text)
        # top buttons
        yb = y0 + ph - tb - 0.30*inch; bx = x + pad
        for t in p['top']: bx += self.button(c, t, bx, yb) + 0.07*inch
        if p['toplabel']:
            c.setStrokeColor(ACC); c.setLineWidth(0.7)
            c.line(bx+0.02*inch, yb+0.10*inch, bx+0.16*inch, yb+0.10*inch)
            label(p['toplabel'], bx+0.16*inch, yb+0.018*inch)
        # slot list
        cols = p['columns'] or ['']; nrow = len(p['rows'])
        rh = 0.135*inch; lt = yb - 0.08*inch; lh = rh*(nrow+1) + 0.02*inch
        lw = w - 2*pad
        c.setFillColor(colors.white); c.setStrokeColor(colors.HexColor('#a9a9a9')); c.setLineWidth(0.6)
        c.rect(x+pad, lt-lh, lw, lh, stroke=1, fill=1)
        weights = [0.08, 0.36, 0.24, 0.14, 0.18][:len(cols)]
        if len(weights) < len(cols): weights = [1.0/len(cols)]*len(cols)
        tot = sum(weights); cx = [x+pad]
        for wt in weights: cx.append(cx[-1] + lw*wt/tot)
        c.setFillColor(colors.HexColor('#ececec')); c.rect(x+pad, lt-rh, lw, rh, stroke=0, fill=1)
        c.setFont('Helvetica-Bold', 6.4); c.setFillColor(colors.HexColor('#333333'))
        for j, h in enumerate(cols): c.drawString(cx[j]+4, lt-rh+0.04*inch, h)
        c.setStrokeColor(colors.HexColor('#d0d0d0'))
        for j in range(1, len(cols)): c.line(cx[j], lt, cx[j], lt-lh)
        for r, cells in enumerate(p['rows']):
            ry = lt - rh*(r+2)
            if r == p['select']:
                c.setFillColor(GRP); c.rect(x+pad+0.5, ry, lw-1, rh, stroke=0, fill=1)
                c.setStrokeColor(ACC); c.setLineWidth(0.6); c.rect(x+pad+0.5, ry, lw-1, rh, stroke=1, fill=0)
            c.setFont('Helvetica', 6.4); c.setFillColor(colors.HexColor('#222222'))
            for j, cell in enumerate(cells[:len(cols)]): c.drawString(cx[j]+4, ry+0.04*inch, cell)
        # bottom buttons
        yb2 = lt - lh - 0.28*inch; bx = x + pad
        for t in p['bottom']: bx += self.button(c, t, bx, yb2) + 0.07*inch
        if p['bottomlabel']:
            c.setStrokeColor(ACC); c.setLineWidth(0.7)
            c.line(bx+0.02*inch, yb2+0.10*inch, bx+0.16*inch, yb2+0.10*inch)
            label(p['bottomlabel'], bx+0.16*inch, yb2+0.018*inch)
        # status line
        c.setStrokeColor(colors.HexColor('#c8c8c8')); c.line(x+pad, yb2-0.08*inch, x+w-pad, yb2-0.08*inch)
        c.setFont('Helvetica', 6.4); c.setFillColor(colors.HexColor('#444444'))
        c.drawString(x+pad, yb2-0.20*inch, p['status'])

    def title(self, c, text, x, ytop, w, col, line=True):
        c.setFillColor(col); c.setFont('Helvetica-Bold', 9)
        c.drawString(x, ytop-0.22*inch, text)
        if line:
            tw = c.stringWidth(text, 'Helvetica-Bold', 9)
            c.setStrokeColor(col); c.setLineWidth(0.6)
            c.line(x+tw+5, ytop-0.19*inch, x+w, ytop-0.19*inch)

    def tag(self, c, text, cx, y, w=None, left=None):
        fs = 7.2
        tw = (w if w else c.stringWidth(text, 'Helvetica-Bold', fs) + 12)
        lx = left if left is not None else cx - tw/2
        c.setFillColor(ACC); c.roundRect(lx, y, tw, 0.165*inch, 2.5, stroke=0, fill=1)
        c.setFillColor(colors.white); c.setFont('Helvetica-Bold', fs)
        c.drawCentredString(lx+tw/2, y+0.047*inch, text)
        return lx, tw

    def panel(self, c, p, x, y0, w, ph):
        pad = 0.16*inch
        c.setFillColor(PANEL); c.roundRect(x, y0, w, ph, 6, stroke=0, fill=1)
        self.title(c, p['title'], x+pad, y0+ph, w-2*pad, LEG)
        legw, bw, bh, gap, tagw = 0.48*inch, 0.52*inch, 0.22*inch, 0.12*inch, 0.86*inch
        hastags = any(b[1] for b in p['buttons'])
        # block = legend | cap | (tag)   centred in the panel
        block = legw + 0.06*inch + bw + gap + tagw
        bx0 = x + (w - block)/2
        capx = bx0 + legw + 0.06*inch
        top = y0 + ph - 0.36*inch            # top of the first row
        n = len(p['buttons'])
        # the vertical strip the caps sit in
        c.setFillColor(WELL)
        c.roundRect(capx-0.05*inch, top-n*ROW+0.02*inch, bw+0.10*inch, n*ROW+0.03*inch, 4, stroke=0, fill=1)
        centres = []
        for r, (leg, oro, sub) in enumerate(p['buttons']):
            cy = top - r*ROW - ROW/2 + 0.02*inch      # cap centre
            centres.append(cy)
            by = cy - bh/2
            c.setFillColor(LEG); c.setFont('Helvetica', 7)
            c.drawRightString(capx-0.17*inch, cy-0.035*inch, leg)
            c.setFillColor(CAPSH); c.roundRect(capx+1.2, by-1.6, bw, bh, 3, stroke=0, fill=1)
            c.setFillColor(CAP); c.roundRect(capx, by, bw, bh, 3, stroke=0, fill=1)
            c.setStrokeColor(colors.white); c.setLineWidth(0.5)
            c.line(capx+3, by+bh-1.2, capx+bw-3, by+bh-1.2)
            if oro:
                tx = capx + bw + gap
                c.setStrokeColor(colors.HexColor('#7fb883')); c.setLineWidth(0.6)
                c.line(capx+bw+2, cy, tx, cy)
                self.tag(c, oro, None, cy-0.0825*inch, w=tagw, left=tx)
                if sub:
                    c.setFillColor(SUBC); c.setFont('Helvetica', 6.4)
                    c.drawCentredString(tx+tagw/2, cy-0.19*inch, sub)
        if p['both']:
            text, sub = p['both']
            if False:   # (old side-bracket layout, kept for reference)
                # bracket to the right of both caps, combo tag beside it
                bxr = capx + bw + 0.06*inch
                ya, yb = centres[0], centres[-1]
                c.setStrokeColor(colors.HexColor('#7fb883')); c.setLineWidth(0.8)
                c.line(bxr, ya, bxr+0.06*inch, ya); c.line(bxr, yb, bxr+0.06*inch, yb)
                c.line(bxr+0.06*inch, ya, bxr+0.06*inch, yb)
                ym = (ya+yb)/2
                c.line(bxr+0.06*inch, ym, bxr+0.12*inch, ym)
                lx, tw = self.tag(c, text, None, ym-0.0825*inch, left=bxr+0.12*inch)
                if sub:
                    c.setFillColor(SUBC); c.setFont('Helvetica', 6.4)
                    words, lines, cur = sub.split(), [], ''
                    for wd in words:                       # wrap into the space under the tag
                        t = (cur + ' ' + wd).strip()
                        if c.stringWidth(t, 'Helvetica', 6.4) > max(tw, x+w-pad-lx): lines.append(cur); cur = wd
                        else: cur = t
                    lines.append(cur)
                    for k, ln in enumerate(lines):
                        c.drawCentredString(lx+tw/2, ym-0.19*inch-k*0.10*inch, ln)
            else:
                # bracket down the left of the caps, combo tag under the strip
                bxl = capx - 0.11*inch
                ya, yb = centres[0], centres[-1]
                ybot = top - len(p['buttons'])*ROW - 0.16*inch
                c.setStrokeColor(colors.HexColor('#7fb883')); c.setLineWidth(0.8)
                c.line(capx-0.05*inch, ya, bxl-0.0*inch, ya)
                ytag = ybot - 0.10*inch
                c.line(bxl, ya, bxl, ytag+0.0825*inch)
                c.line(capx-0.05*inch, yb, bxl, yb)
                c.line(bxl, ytag+0.0825*inch, capx, ytag+0.0825*inch)
                lx, tw = self.tag(c, text, None, ytag, left=capx)
                if sub:
                    c.setFillColor(SUBC); c.setFont('Helvetica', 6.4)
                    c.drawString(lx, ytag-0.13*inch, sub)

    def note(self, c, p, x, y0, w, ph):
        pad = 0.14*inch
        c.setFillColor(GRP); c.roundRect(x, y0, w, ph, 6, stroke=0, fill=1)
        self.title(c, p['title'], x+pad, y0+ph, w-2*pad, ACC)
        st = ParagraphStyle('nt', fontName='Helvetica', fontSize=7.6, leading=9.8, spaceAfter=4,
                            textColor=DARK)
        y = y0 + ph - 0.34*inch
        for ln in p['lines']:
            para = Paragraph(ln, st)
            _, hgt = para.wrap(w-2*pad, ph)
            y -= hgt
            para.drawOn(c, x+pad, y)
            y -= st.spaceAfter

# ================================================================ build
class CheckedDoc(BaseDocTemplate):
    def afterFlowable(self, fl):
        if hasattr(fl, '_expect'):
            self.colcheck.append((fl._expect, (self.page, self.frame.id)))

def build(scale, out):
    body = 7.3*scale; grp = 8.2*scale; sub = 7.9*scale
    s_group = ParagraphStyle('g', fontName='Helvetica-Bold', fontSize=grp, leading=grp*1.25,
                             textColor=ACC, backColor=GRP, borderPadding=(2, 3, 1, 3),
                             spaceBefore=grp*0.55, spaceAfter=grp*0.45)
    s_sub = ParagraphStyle('s', fontName='Helvetica-Bold', fontSize=sub, leading=sub*1.2,
                           textColor=ACC, spaceBefore=sub*0.6, spaceAfter=sub*0.2)
    s_p = ParagraphStyle('p', fontName='Helvetica', fontSize=body, leading=body*1.28,
                         spaceAfter=body*0.45)
    s_li = ParagraphStyle('li', parent=s_p, leftIndent=body*1.3, bulletIndent=0, spaceAfter=body*0.3)
    s_sub2 = ParagraphStyle('li2', parent=s_li, leftIndent=body*2.6, bulletIndent=body*1.3, spaceAfter=body*0.15)
    s_num = ParagraphStyle('num', parent=s_li, bulletFontName='Helvetica-Bold', bulletColor=ACC)
    s_tip = ParagraphStyle('t', parent=s_p, fontSize=body*0.95, leading=body*0.95*1.28,
                           backColor=TIPBG, borderColor=TIPBD,
                           borderWidth=0.6, borderPadding=(3, 4, 3, 4), spaceBefore=body*0.5,
                           spaceAfter=body*0.7, textColor=DARK)
    story = [PanelStrip(W-2*M, STRIP), FrameBreak()]
    for ci, col in enumerate(COLS):
        if ci: story.append(FrameBreak())
        for kind, val in col:
            if kind == 'H': p = Paragraph(val, s_group)
            elif kind == 'S': p = Paragraph(val, s_sub)
            elif kind == 'P': p = Paragraph(val, s_p)
            elif kind == 'T': p = Paragraph(val, s_tip)
            elif kind == 'B': p = KeepTogether([Paragraph(t, s_sub2 if lv else s_li,
                                                          bulletText='–' if lv else '•') for lv, t in val])
            elif kind == 'N': p = KeepTogether([Paragraph(t, s_num, bulletText='%d' % (i+1))
                                                for i, t in enumerate(val)])
            p._expect = ci
            story.append(p)
    def header(canv, doc):
        canv.saveState()
        canv.setFillColor(ACC); canv.rect(0, H-TOPH, W, TOPH, stroke=0, fill=1)
        canv.setFillColor(colors.white); canv.setFont('Helvetica-Bold', 15)
        canv.drawString(M, H-0.35*inch, 'OROVELA')
        canv.setFont('Helvetica', 9.5)
        canv.drawString(M+1.16*inch, H-0.345*inch, META['title'])
        canv.setFont('Helvetica', 8)
        canv.drawRightString(W-M, H-0.345*inch, META['version'])
        canv.setFillColor(MID); canv.setFont('Helvetica', 6.5)
        canv.drawRightString(W-M, 0.16*inch, META['footer'])
        canv.restoreState()
    top = H - TOPH - 0.14*inch
    frames = [Frame(M, top-STRIP, W-2*M, STRIP, id='strip', leftPadding=0, rightPadding=0,
                    topPadding=0, bottomPadding=0)]
    ch = top - STRIP - 0.06*inch - 0.30*inch
    frames += [Frame(M+i*(colw+GUT), 0.30*inch, colw, ch, id='c%d' % i, leftPadding=0,
                     rightPadding=0, topPadding=0, bottomPadding=0) for i in range(NCOL)]
    doc = CheckedDoc(out, pagesize=PAGE,
                     pageTemplates=[PageTemplate(id='p', frames=frames, onPage=header)],
                     title='OROVELA ' + META['title'], author='Orovela')
    doc.colcheck = []
    doc.build(story)
    spills = sum(1 for want, (pg, fid) in doc.colcheck if pg != 1)
    return len(PdfReader(out).pages), spills

if __name__ == '__main__':
    best = None
    for scale in [1.40, 1.35, 1.30, 1.26, 1.22, 1.18, 1.14, 1.10, 1.06, 1.02, 0.98, 0.94, 0.90, 0.86]:
        n, spills = build(scale, OUT)
        print('scale %.2f -> %d page(s), %d spill(s)' % (scale, n, spills))
        if n == 1 and spills == 0:
            best = scale; break
    if best is None:
        print('DOES NOT FIT on one page even at the smallest size - shorten the text.')
    else:
        print('chosen scale: %.2f -> body %.1fpt' % (best, 7.3*best))
