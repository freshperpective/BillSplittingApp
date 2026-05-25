// ignore_for_file: avoid_print
//
// Run with:  flutter test test/gen_icon_test.dart
//
// Writes a 1024 × 1024 PNG to assets/icon/icon.png, which is the source
// image used by flutter_launcher_icons to generate all platform densities.
//
// Design: "Tabby" — a geometric cat face on a teal field.
//   • The cat = "tabby" (the breed), its three amber forehead stripes
//     double as ledger / bill lines = the "tab" meaning of the name.
//   • White circle (head) + two white triangles (ears) form a single merged
//     silhouette. A small amber nose anchors the face without adding clutter.
//   • Full-bleed — the OS applies its own rounded-corner or circular mask.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generate app icon → assets/icon/icon.png', () async {
    const size = 1024.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, size, size),
    );

    _drawTabbyIcon(canvas, size);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    final outFile =
        File('${Directory.current.path}/assets/icon/icon.png');
    await outFile.create(recursive: true);
    await outFile.writeAsBytes(bytes);

    print('✓  Icon written to ${outFile.path} (${bytes.length} bytes)');
    expect(bytes.length, greaterThan(1000));
  });
}

// ─── Drawing ───────────────────────────────────────────────────────────────

// Brand palette (duplicated here so the generator has no package deps).
const _teal = ui.Color(0xFF0E7C66);
const _tealDeep = ui.Color(0xFF0B5E4D);
const _amber = ui.Color(0xFFF4A259);
const _white = ui.Color(0xFFFFFFFF);

void _drawTabbyIcon(ui.Canvas canvas, double s) {
  final p = ui.Paint()..isAntiAlias = true;

  // ── 1. Teal background (full bleed; OS applies its own corner mask) ────
  p
    ..color = _teal
    ..style = ui.PaintingStyle.fill;
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, s, s), p);

  // ── 2. White ear triangles ─────────────────────────────────────────────
  // Both base points of each ear land exactly on the head circle
  // (verified: distance from centre ≈ headRadius) so the circle drawn
  // in step 4 merges seamlessly, leaving no gap or overlap artefact.
  p.color = _white;

  // Left ear
  _tri(canvas, p,
    ui.Offset(s * 0.275, s * 0.388), // outer base  (on circle)
    ui.Offset(s * 0.399, s * 0.301), // inner base  (on circle)
    ui.Offset(s * 0.215, s * 0.063), // tip
  );

  // Right ear (mirror)
  _tri(canvas, p,
    ui.Offset(s * 0.601, s * 0.301),
    ui.Offset(s * 0.725, s * 0.388),
    ui.Offset(s * 0.785, s * 0.063),
  );

  // ── 3. Amber inner-ear marks ───────────────────────────────────────────
  // Smaller triangles inside each ear. Drawn before the head circle so the
  // circle naturally covers their lower portions — only the upper (ear)
  // section remains visible.
  p.color = _amber.withOpacity(0.75);

  _tri(canvas, p,
    ui.Offset(s * 0.298, s * 0.376),
    ui.Offset(s * 0.390, s * 0.317),
    ui.Offset(s * 0.244, s * 0.112),
  );
  _tri(canvas, p,
    ui.Offset(s * 0.610, s * 0.317),
    ui.Offset(s * 0.702, s * 0.376),
    ui.Offset(s * 0.756, s * 0.112),
  );

  // ── 4. White head circle ───────────────────────────────────────────────
  p.color = _white;
  final hc = ui.Offset(s * 0.500, s * 0.576);
  final hr = s * 0.293;
  canvas.drawCircle(hc, hr, p);

  // ── 5. Amber tabby stripes, clipped to the head circle ────────────────
  // Three bold horizontal bands across the upper face.  At every display
  // size they read as both cat forehead markings and ledger / bill lines.
  canvas.save();
  canvas.clipPath(ui.Path()
    ..addOval(ui.Rect.fromCircle(center: hc, radius: hr)));

  p.color = _amber;
  const sRad = ui.Radius.circular(13);
  for (var i = 0; i < 3; i++) {
    final top = s * (0.346 + i * 0.090);
    canvas.drawRRect(
      ui.RRect.fromLTRBR(
        s * 0.17, top,
        s * 0.83, top + s * 0.063,
        sRad,
      ),
      p,
    );
  }
  canvas.restore();

  // ── 6. Subtle darker-teal ring around head (depth separator) ──────────
  // Keeps the white face from bleeding into the teal background at the
  // circle edge when the icon is displayed on a teal-ish wallpaper.
  p
    ..color = _tealDeep.withOpacity(0.18)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = s * 0.012;
  canvas.drawCircle(hc, hr, p);

  // ── 7. Amber nose dot ─────────────────────────────────────────────────
  p
    ..color = _amber
    ..style = ui.PaintingStyle.fill;
  canvas.drawCircle(ui.Offset(s * 0.500, s * 0.742), s * 0.021, p);
}

/// Draw a filled triangle through three vertices.
void _tri(
  ui.Canvas canvas,
  ui.Paint paint,
  ui.Offset a,
  ui.Offset b,
  ui.Offset c,
) {
  canvas.drawPath(
    ui.Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..close(),
    paint,
  );
}
