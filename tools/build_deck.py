from pathlib import Path
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'Signal-Room-DevFest-2026.pptx'
prs = Presentation()
prs.slide_width, prs.slide_height = Inches(13.333), Inches(7.5)
BG = RGBColor(11, 17, 30)
WHITE = RGBColor(242, 246, 250)
MUTED = RGBColor(153, 172, 187)
CYAN = RGBColor(74, 226, 217)
LIME = RGBColor(216, 240, 103)

def txt(slide, x, y, w, h, string, size=24, color=WHITE, bold=False, font='Aptos', align=None):
    box = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = box.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = 0
    tf.margin_top = tf.margin_bottom = 0
    for i, line in enumerate(string.split('\n')):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.text = line
        p.font.name, p.font.size, p.font.bold = font, Pt(size), bold
        p.font.color.rgb = color
        p.space_after = Pt(10)
        if align: p.alignment = align
    return box

def base(number, eyebrow, title, note=''):
    s = prs.slides.add_slide(prs.slide_layouts[6]); s.background.fill.solid(); s.background.fill.fore_color.rgb = BG
    txt(s,.65,.3,11,.35,eyebrow.upper(),14,CYAN,True)
    txt(s,.65,.82,12,1.2,title,37,WHITE,True)
    txt(s,.65,7.13,11,.22,'GOOGLE DEVFEST 2026 WROCŁAW   /   SIGNAL ROOM',10,MUTED)
    txt(s,12.2,7.10,.4,.3,str(number).zfill(2),12,LIME,True)
    if note:
        try: s.notes_slide.notes_text_frame.text = note
        except Exception: pass
    return s

s=base(1,'Live build / 40 minutes','Event-Driven AI Pipelines on GCP')
txt(s,.7,2.5,11,1.6,'From Eventarc to LLMs',52,CYAN,True)
txt(s,.7,5.25,11,.8,'A field report becomes an operator brief. Built live from a terminal.',24,MUTED)

s=base(2,'The incident','14:20 at Grunwaldzki Bridge')
txt(s,.8,2.2,11,1.7,'A tram stops. The power fails.\n45 passengers wait in the heat.',31,WHITE,True)
txt(s,.8,5,10,1,'One report arrives. What should the operator know first?',26,CYAN)

s=base(3,'System map','One upload. One traceable brief.')
txt(s,.75,2.15,11.8,1.8,'Cloud Storage    →    Eventarc    →    Cloud Run',32,CYAN,True)
txt(s,.75,4.1,11.8,.8,'Gemini on Vertex AI    →    separate result bucket',30,LIME,True)
txt(s,.75,5.55,11.6,.8,'Private service • two identities • object generation in every result',21,MUTED)

s=base(4,'Input contract','Reports are evidence, not commands')
txt(s,.8,2.1,5.5,3.5,'incident_id\nlocation\nobserved_at\nreport',28,CYAN,True,font='Aptos Mono')
txt(s,6.9,2.2,5.1,2.9,'A fictional transit disruption.\nThe model may suggest an action.\nA person makes the decision.',25,WHITE)

s=base(5,'Output contract','A brief a human can inspect')
txt(s,.8,2.1,6,3.5,'category  /  severity\nsummary  /  entities\nsuggested_action\nuncertainty',27,LIME,True,font='Aptos Mono')
txt(s,7,2.2,5.3,2.8,'source bucket + object + generation\nmodel ID\nreview_required: true',23,WHITE)

s=base(6,'Build / foundation','Give each component only what it needs')
txt(s,.8,2.15,11.3,3.8,'Input bucket: versioned reports\nOutput bucket: generated briefs\nRuntime identity: Storage + Vertex AI\nTrigger identity: receive event + invoke Run',25,WHITE)

s=base(7,'Build / worker','The request is a CloudEvent')
txt(s,.8,2.05,11.7,4,'1  Validate event type and source generation\n2  Read exact object generation\n3  Ask Gemini for structured JSON\n4  Create the result only if absent',27,CYAN,True)

s=base(8,'Build / routing','Eventarc listens for finalized objects')
txt(s,.8,2.2,11.5,2.7,'type = google.cloud.storage.object.v1.finalized\nbucket = signal-in',25,LIME,True,font='Aptos Mono')
txt(s,.8,5.35,11.5,.8,'Bucket filter is exact. Output goes to another bucket.',23,MUTED)

s=base(9,'Demo / first result','Watch the brief arrive')
txt(s,.8,2.15,11.7,2.4,'bash demo.sh --apply\nREPORT=samples/02-followup.json bash demo.sh --apply',25,CYAN,True,font='Aptos Mono')
txt(s,.8,5.4,11,.9,'Compare the evidence, the severity, and the uncertainty.',23,MUTED)

s=base(10,'Failure drill','What happens when delivery repeats?')
txt(s,.8,2.15,11.6,3.8,'Same name + generation  →  same result key\nCreate-only write  →  one stored brief\nTransient failure  →  503 and retry\nInvalid input  →  log and acknowledge',25,WHITE)

s=base(11,'Production questions','The demo exposes the next decisions')
txt(s,.8,2.15,11.6,3.8,'Where do invalid reports go?\nHow long should retries continue?\nHow do we audit model quality and cost?\nWho reviews a high-severity recommendation?',26,WHITE)

s=base(12,'Takeaway','The input generation is the anchor')
txt(s,.8,2.3,11.8,2.2,'Trace the brief to a specific object.\nMake repeated delivery safe for the result.',31,CYAN,True)
txt(s,.8,5.7,10,.6,'20-minute Terraform variant included in the project kit.',22,LIME)

prs.save(OUT)
print(OUT)
