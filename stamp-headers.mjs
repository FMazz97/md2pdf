// Adds the running header to a finished PDF: document title on the left, title of the current section on the right.
// Uses pdf-lib with a standard font; characters the font cannot encode (for example emoji) are left out of the header.
import { PDFDocument, StandardFonts, rgb } from 'pdf-lib';

const MM = 72 / 25.4;
const SIZE = 9;           // font size in points
const MARGIN = 16 * MM;   // same side margin as @page in the CSS
const GAP = 12;           // minimum space between the left and the right text, in points

// info.entries: first page (1-based) and title of each section, sorted or not; a section starts at the first
// page of a document or at every top-level heading after the first one in the same document.
export async function stampHeaders(pdfBytes, { title, tocTitle, entries }) {
  const doc = await PDFDocument.load(pdfBytes);
  const font = await doc.embedFont(StandardFonts.Helvetica);
  const color = rgb(0x59 / 255, 0x63 / 255, 0x6e / 255);
  const ruleColor = rgb(0xd1 / 255, 0xd9 / 255, 0xe0 / 255);

  const supported = new Set(font.getCharacterSet());
  const clean = (t) => [...(t || '')].filter((c) => supported.has(c.codePointAt(0))).join('').replace(/\s+/g, ' ').trim();
  const width = (t) => font.widthOfTextAtSize(t, SIZE);
  const fit = (t, max) => {
    if (max <= 0) return '';
    if (width(t) <= max) return t;
    let s = t;
    while (s.length > 1 && width(s + '...') > max) s = s.slice(0, -1);
    return s.trimEnd() + '...';
  };

  const left = clean(title);
  const toc = clean(tocTitle);
  const sections = entries
    .filter((e) => e.page)
    .map((e) => ({ page: e.page, text: clean(e.text) }))
    .sort((a, b) => a.page - b.page);
  const firstSectionPage = sections.length ? sections[0].page : Infinity;

  doc.getPages().forEach((pg, i) => {
    const n = i + 1;
    if (n === 1) return;   // cover page: no header

    let right = '';
    if (n < firstSectionPage) right = toc;   // pages between the cover and the first section: table of contents
    else for (const s of sections) { if (s.page <= n) right = s.text; else break; }

    const { width: w, height: h } = pg.getSize();
    const avail = w - 2 * MARGIN;
    const leftText = fit(left, right ? avail * 0.55 : avail);
    const rightText = fit(right, avail - width(leftText) - GAP);
    const y = h - 10.5 * MM;   // text baseline

    if (leftText) pg.drawText(leftText, { x: MARGIN, y, size: SIZE, font, color });
    if (rightText) pg.drawText(rightText, { x: w - MARGIN - width(rightText), y, size: SIZE, font, color });
    if (leftText || rightText) {
      pg.drawLine({ start: { x: MARGIN, y: h - 12.5 * MM }, end: { x: w - MARGIN, y: h - 12.5 * MM }, thickness: 0.5, color: ruleColor });
    }
  });

  return doc.save();
}
