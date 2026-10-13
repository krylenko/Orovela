from reportlab.lib.pagesizes import letter, landscape
from reportlab.lib.units import inch
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib import colors
from reportlab.platypus import (BaseDocTemplate, Frame, PageTemplate, Paragraph,
                                KeepTogether, FrameBreak)
from reportlab.pdfbase.pdfmetrics import stringWidth
from pypdf import PdfReader

PAGE = landscape(letter); W,H = PAGE; M = 0.40*inch; NCOL=4; GUT=0.16*inch
colw = (W - 2*M - (NCOL-1)*GUT)/NCOL
ACC = colors.HexColor('#1b5e20'); GRP = colors.HexColor('#e8f5e9')

SAMPLING = ('SAMPLING', [
  ('1','Sample rate','1-4','3',['4 = ~15.5 kHz, ~2.1 s','3 = ~10.3 kHz, ~3.2 s','2 = ~6.3 kHz, ~5.2 s','1 = ~3.4 kHz, ~9.6 s']),
  ('2','Input source','0-1','1',['0 = mic, 1 = line']),
  ('3','Input filter freq','0-99','99',['0 = closed ... 99 = calibrated max']),
  ('4','Trigger mode','0-1','0',['0 = manual, 1 = auto (threshold)']),
  ('5','Auto-trigger threshold','0-99','20',['Trigger level for mode 1']),
])
TUNING = ('TUNING', [
  ('6','Sample tune','0-99','50',['Global fine tune; 50 = center']),
  ('7','Base note','0-99','60',['Recorded pitch; 60 = middle C']),
  ('8','Coarse tune','0-48','24',['Semitones; 24 = zero (±24)']),
  ('9','Fine tune','0-98','49',['~19 cents/step; 49 = zero']),
  ('10','Detune mix','0-99','0',['Detune blend; 0 = dry']),
  ('11','Detune amount','0-20','11',['10 = unison; curved to ±1 octave']),
  ('12','Detune drift depth','0-4','0',['Slow random wander; 0 = off']),
])
PLAYBACK = ('PLAYBACK + LOOPING', [
  ('13','Loop mode','0-1','1',['0 = one-shot, 1 = loop']),
  ('14','Playback direction','0-1','0',['0 = forward, 1 = reverse']),
  ('15','Sample start','0-99','0',[]),
  ('16','Sample end','0-99','99',[]),
  ('17','Loop start','0-99','0',['Plays within 15-16']),
  ('18','Loop end','0-99','99',['Plays within 17-16']),
])
FILTER = ('FILTER', [
  ('21','Cutoff','0-99','99',[]),
  ('22','Resonance','0-99','20',[]),
  ('23','Keyboard tracking','0-98','49',['Bipolar; 49 = off']),
  ('24','Velocity -> filter','0-99','0',[]),
  ('25','Velocity -> resonance','0-99','0',[]),
])
AMPENV = ('AMP ENVELOPE', [
  ('31','Amp attack','0-99','0',[]),
  ('32','Amp decay','0-99','40',[]),
  ('33','Amp sustain','0-99','50',[]),
  ('34','Amp release','0-99','30',[]),
  ('35','Velocity -> amp','0-99','99',['0 = constant; 99 = full velocity']),
])
FILTENV = ('FILTER ENVELOPE', [
  ('41','Filter attack','0-99','0',[]),
  ('42','Filter decay','0-99','40',[]),
  ('43','Filter sustain','0-99','50',[]),
  ('44','Filter release','0-99','20',[]),
  ('45','Filter env -> cutoff','0-98','49',['Bipolar: 49 = zero']),
  ('46','Filter env -> res','0-98','49',['Bipolar: 49 = zero']),
])
PITCHENV = ('PITCH ENVELOPE', [
  ('51','Pitch env attack','0-99','0',[]),
  ('52','Pitch env decay','0-99','20',[]),
  ('53','Pitch env sustain','0-99','0',[]),
  ('54','Pitch env release','0-99','10',[]),
  ('55','Pitch env depth','0-99','0',[]),
  ('56','Pitch env direction','0-1','1',['0 = down, 1 = up']),
])
LFO = ('LFO', [
  ('61','LFO waveform','0-4','0',['0 tri · 1 saw up · 2 saw down · 3 square · 4 random S&amp;H']),
  ('62','LFO speed','0-99','4',['Curved; span set by param 76']),
  ('63','LFO trigger','0-1','0',['0 = retrigger; 1 = free-run']),
  ('64','LFO -> amp','0-99','0',[]),
  ('65','LFO -> cutoff','0-99','0',[]),
  ('66','LFO -> pitch','0-99','0',[]),
  ('67','LFO -> res','0-99','0',[]),
  ('76','LFO range','0-1','0',['0 = low, 1 = high']),
])
CONTROL = ('CONTROL / MIDI', [
  ('71','MIDI channel','1-16','1',['Transmit and receive']),
  ('72','Mod wheel function','0-4','0',['0 = edit param','1 = LFO speed','2 = LFO pitch','3 = LFO filter','4 = LFO amp']),
  ('73','Mod wheel damping','0-3','1',['Pot smoothing; higher = smoother']),
  ('74','Pitch bend range','1-12','2',['Semitones +/-']),
  ('75','Pitch wheel disable','0-1','0',['0 = enabled, 1 = disabled','(MIDI bend still received)']),
  ('77','MIDI mod wheel receive','0-1','0',['0 = on, 1 = off','(local wheel only; notes/bend still received)']),
])
# Utility: list of groups; extra space between groups
UTIL_GROUPS = [
 ['<b>Save Program</b>: Seq Save -> slot 0-9 -> Enter (Cancel aborts)',
  '<b>Load Program</b>: Seq Load -> slot 0-9 -> Enter; empty slot restores the default saw'],
 ['<b>Reset Params</b>: Load Upper + Lower together; resets all except 71-75 and 77'],
 ['<b>Octave Up</b>: Sample Upper',
  '<b>Octave Down</b>: Sample Lower',
  '<b>Octave Reset</b>: Sample Upper + Sample Lower simultaneously'],
 ['<b>Panic</b>: Press Play Seq twice; cuts off all sounding notes'],
]

COLS = [
 [SAMPLING, TUNING],
 [PLAYBACK, FILTER, AMPENV],
 [FILTENV, PITCHENV, LFO],
 [CONTROL, 'UTILITY'],
]

class CheckedDoc(BaseDocTemplate):
    def afterFlowable(self, fl):
        if hasattr(fl, '_expect_col'):
            self.colcheck.append((fl._expect_col, int(self.frame.id[1:])))

def build(scale, out):
    nm = 8.0*scale; det = 6.1*scale; grp = 8.2*scale
    s_group = ParagraphStyle('g', fontName='Helvetica-Bold', fontSize=grp, leading=grp*1.25,
                             textColor=ACC, backColor=GRP, borderPadding=(2,3,1,3),
                             spaceBefore=grp*0.55, spaceAfter=grp*0.3)
    s_name = ParagraphStyle('nm', fontName='Helvetica-Bold', fontSize=nm, leading=nm*1.18, spaceAfter=0.5,
                            leftIndent=nm*1.1, firstLineIndent=-nm*1.1)
    s_det  = ParagraphStyle('dt', fontName='Helvetica', fontSize=det, leading=det*1.2,
                            leftIndent=nm*1.1, spaceAfter=0.5)
    s_util = ParagraphStyle('u', parent=s_det, leftIndent=0)
    s_util_gap = ParagraphStyle('ug', parent=s_util, spaceBefore=det*1.1)
    story=[]
    for ci, sections in enumerate(COLS):
        if ci: story.append(FrameBreak())
        for sec in sections:
            if sec == 'UTILITY':
                p = Paragraph('UTILITY', s_group); p._expect_col = ci
                story.append(p)
                for gi, group in enumerate(UTIL_GROUPS):
                    for li, u in enumerate(group):
                        story.append(Paragraph(u, s_util_gap if (gi and not li) else s_util))
                continue
            gname, entries = sec
            p = Paragraph(gname, s_group); p._expect_col = ci
            story.append(p)
            for num,name,rng,d,lines in entries:
                # indent detail (and wrapped name lines) to where THIS entry's name starts
                w = stringWidth(num+'  ', 'Helvetica-Bold', nm)
                s_name_e = ParagraphStyle('nm'+num, parent=s_name, leftIndent=w, firstLineIndent=-w)
                s_det_e  = ParagraphStyle('dt'+num, parent=s_det, leftIndent=w)
                parts=[Paragraph('<font color="#1b5e20">%s</font>&nbsp;&nbsp;%s <font face="Helvetica" size="%.1f" color="#5e7d62">(%s,&nbsp;def&nbsp;%s)</font>'
                                 % (num,name,det,rng,d), s_name_e)]
                parts += [Paragraph(l, s_det_e) for l in lines]
                story.append(KeepTogether(parts))
    def header(canv, doc):
        canv.saveState()
        canv.setFillColor(ACC); canv.rect(0, H-0.5*inch, W, 0.5*inch, stroke=0, fill=1)
        canv.setFillColor(colors.white); canv.setFont('Helvetica-Bold', 15)
        canv.drawString(M, H-0.35*inch, 'OROVELA')
        canv.setFont('Helvetica', 9.5)
        canv.drawString(M+1.16*inch, H-0.345*inch, 'Ensoniq Mirage DSK-8 replacement OS — Parameter Reference')
        canv.setFont('Helvetica', 8)
        canv.drawRightString(W-M, H-0.345*inch, 'Orovela 1.5 · 2026-10-12')
        canv.restoreState()
    frames=[Frame(M+i*(colw+GUT), 0.28*inch, colw, H-0.5*inch-0.42*inch, id='c%d'%i,
                  leftPadding=0,rightPadding=0,topPadding=0,bottomPadding=0) for i in range(NCOL)]
    doc=CheckedDoc(out, pagesize=PAGE, pageTemplates=[PageTemplate(id='c',frames=frames,onPage=header)],
                        title='OROVELA Parameter Reference (Orovela 1.5)')
    doc.colcheck=[]
    doc.build(story)
    spills = sum(1 for want,got in doc.colcheck if want!=got)
    return len(PdfReader(out).pages), spills

best=None
for scale in [1.75,1.68,1.62,1.58,1.55,1.52,1.48,1.45,1.42,1.38,1.34,1.3,1.22,1.15,1.08,1.0]:
    n, spills = build(scale,'OROVELA_param_reference.pdf')
    print('scale %.2f -> %d page(s), %d header spill(s)'%(scale,n,spills))
    if n==1 and spills==0:
        best=scale; break
print('chosen scale:', best, '-> name font %.1fpt, detail %.1fpt'%(8.0*best,6.1*best))
