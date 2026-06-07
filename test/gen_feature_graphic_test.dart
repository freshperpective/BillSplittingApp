// ignore_for_file: avoid_print
//
// Run with:  flutter test test/gen_feature_graphic_test.dart
//
// Writes a 1024 × 500 PNG to assets/store/feature_graphic.png.
// Upload this file as the "Feature graphic" in Google Play Console.
//
// Design: teal field, white wordmark + tagline, amber accent strip at bottom.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generate Play Store feature graphic → assets/store/feature_graphic.png',
      () async {
    const w = 1024.0;
    const h = 500.0;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, const ui.Rect.fromLTWH(0, 0, w, h));

    _drawFeatureGraphic(canvas, w, h);

    final picture = recorder.endRecording();
    final image = await picture.toImage(w.toInt(), h.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    final dir = Directory('assets/store');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('assets/store/feature_graphic.png');
    file.writeAsBytesSync(bytes);

    print('Feature graphic written to ${file.path} (${bytes.length} bytes)');
    expect(bytes.length, greaterThan(1000));
  });
}

void _drawFeatureGraphic(ui.Canvas canvas, double w, double h) {
  const teal = ui.Color(0xFF0E7C66);
  const amber = ui.Color(0xFFF4A259);
  const white = ui.Color(0xFFFFFFFF);
  const whiteDim = ui.Color(0xBBFFFFFF);

  // ── 1. Background ───────────────────────────────────────────────────────────
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w, h),
    ui.Paint()..color = teal,
  );

  // ── 2. Subtle darker-teal radial vignette (depth without texture) ───────────
  final vignette = ui.Paint()
    ..shader = ui.Gradient.radial(
      ui.Offset(w / 2, h / 2),
      w * 0.75,
      [const ui.Color(0x00000000), const ui.Color(0x33000000)],
    );
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, w, h), vignette);

  // ── 3. Wordmark — "Sorted" ───────────────────────────────────────────────────
  final titleStyle = ui.TextStyle(
    color: white,
    fontSize: 112,
    fontWeight: ui.FontWeight.w700,
    letterSpacing: -2,
  );
  final titleBuilder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textAlign: ui.TextAlign.center,
      fontSize: 112,
      fontWeight: ui.FontWeight.w700,
    ),
  )
    ..pushStyle(titleStyle)
    ..addText('Sorted');
  final titlePara = titleBuilder.build()
    ..layout(ui.ParagraphConstraints(width: w));
  // Vertically centre slightly above midpoint
  final titleY = h / 2 - titlePara.height - 12;
  canvas.drawParagraph(titlePara, ui.Offset(0, titleY));

  // ── 4. Tagline ───────────────────────────────────────────────────────────────
  final tagStyle = ui.TextStyle(
    color: whiteDim,
    fontSize: 28,
    fontWeight: ui.FontWeight.w400,
    letterSpacing: 0.5,
  );
  final tagBuilder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textAlign: ui.TextAlign.center,
      fontSize: 28,
    ),
  )
    ..pushStyle(tagStyle)
    ..addText('Split bills. Stay friends.');
  final tagPara = tagBuilder.build()
    ..layout(ui.ParagraphConstraints(width: w));
  final tagY = h / 2 + 8;
  canvas.drawParagraph(tagPara, ui.Offset(0, tagY));

  // ── 5. Amber accent strip at bottom ─────────────────────────────────────────
  const stripH = 6.0;
  canvas.drawRect(
    ui.Rect.fromLTWH(0, h - stripH, w, stripH),
    ui.Paint()..color = amber,
  );

  // ── 6. Small amber dot accent (echoes icon nose / brand punctuation) ─────────
  canvas.drawCircle(
    ui.Offset(w / 2, h - stripH - 22),
    5,
    ui.Paint()..color = amber.withValues(alpha: 0.5),
  );
}
