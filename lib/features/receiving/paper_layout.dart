import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/models/delivery.dart';
import 'paper_size.dart';

/// Turns a [PaperSize] into the concrete geometry and type scale a document is
/// laid out with.
///
/// The point of this class is that a thermal receipt is not a small A4. Each
/// medium gets its own margins, font sizes and column widths, so an 80 mm roll
/// uses the full width a receipt printer can actually print and a 58 mm roll is
/// never asked to carry content it physically cannot fit.
class PaperLayout {
  const PaperLayout._({
    required this.paper,
    required this.pageFormat,
    required this.margin,
    required this.titleSize,
    required this.bodySize,
    required this.smallSize,
    required this.lineHeight,
  });

  final PaperSize paper;
  final PdfPageFormat pageFormat;
  final pw.EdgeInsets margin;

  final double titleSize;
  final double bodySize;
  final double smallSize;

  /// Height of one body line, used to size a continuous thermal page.
  final double lineHeight;

  /// Thermal margins are tight because every millimetre is printable area, and
  /// a thermal head cannot print reliably right into the edge of the paper.
  static const _thermal58Margin = pw.EdgeInsets.symmetric(
    horizontal: 4,
    vertical: 6,
  );
  static const _thermal80Margin = pw.EdgeInsets.symmetric(
    horizontal: 6,
    vertical: 6,
  );

  /// Builds the layout for [paper].
  ///
  /// [contentHeightPt] applies only to thermal sizes, whose height comes from
  /// their content. Sheet sizes always use their real media height.
  factory PaperLayout.forPaper(PaperSize paper, {double contentHeightPt = 0}) {
    if (paper.isThermal) {
      final isNarrow = paper == PaperSize.thermal58;
      return PaperLayout._(
        paper: paper,
        pageFormat: PdfPageFormat(
          paper.widthPt,
          contentHeightPt <= 0 ? 400 : contentHeightPt,
        ),
        margin: isNarrow ? _thermal58Margin : _thermal80Margin,
        // A thermal head has a low resolution, so type is set larger than the
        // same information on a laser page, and the narrow roll is scaled to its
        // own width rather than proportionally shrunk from the wider one.
        titleSize: isNarrow ? 9.5 : 12,
        bodySize: isNarrow ? 7.5 : 9,
        smallSize: isNarrow ? 6.5 : 7.5,
        lineHeight: isNarrow ? 9.5 : 11.5,
      );
    }
    return PaperLayout._(
      paper: paper,
      pageFormat: PdfPageFormat(paper.widthPt, paper.heightPt),
      // A4 keeps the margin it has always had, so existing A4 output is
      // unchanged. Smaller sheets are tightened, because A4's 32pt margin would
      // leave a narrow A5 page badly under-filled.
      margin: pw.EdgeInsets.all(paper == PaperSize.a4 ? 32 : 22),
      titleSize: paper == PaperSize.a5 ? 17 : 22,
      bodySize: paper == PaperSize.a5 ? 10 : 12,
      smallSize: paper == PaperSize.a5 ? 8.5 : 10,
      lineHeight: paper == PaperSize.a5 ? 12 : 14,
    );
  }

  /// Printable width in points: the real budget for any table or wrapped text.
  double get contentWidthPt => pageFormat.width - margin.horizontal;

  double get tableFontSize => bodySize;

  /// True when this layout targets a continuous roll rather than a sheet.
  bool get isThermal => paper.isThermal;

  /// The default body text style for this medium.
  pw.TextStyle get textStyle => pw.TextStyle(fontSize: bodySize);

  /// The page geometry a preview should display for this document, so the
  /// preview shows the real page rather than a stand-in that might differ from
  /// what prints.
  PdfPageFormat get previewFormat => pageFormat;
}

/// A single label/value row before it is laid out.
class PrintRow {
  const PrintRow(this.label, this.value, {this.emphasise = false});

  final String label;
  final String value;

  /// True for totals, which print larger and bolder.
  final bool emphasise;
}

/// Lays out a two-column label/value block, wrapping long values.
pw.Widget buildLabelValueBlock(List<PrintRow> rows, PaperLayout layout) {
  final style = pw.TextStyle(fontSize: layout.bodySize);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (final row in rows)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                // A fixed label column keeps values aligned down the page. On
                // 58 mm the label takes a smaller share, because the value is
                // what a reader is actually looking up.
                width: layout.paper == PaperSize.thermal58
                    ? layout.contentWidthPt * 0.38
                    : layout.contentWidthPt * 0.42,
                child: pw.Text(
                  row.label,
                  style: style.copyWith(fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  row.value,
                  // Values wrap rather than being truncated: clipping a supplier
                  // name or phone number is worse than a second line.
                  style: row.emphasise
                      ? style.copyWith(fontWeight: pw.FontWeight.bold)
                      : style,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Estimates the height a continuous thermal receipt needs.
///
/// Thermal media declares no height, so it must be derived or the printer
/// either cuts the receipt short or feeds a long blank tail. This counts the
/// lines the layout will actually emit rather than guessing a fixed length.
double estimateThermalHeightPt({
  required PaperLayout layout,
  required int infoRows,
  required int tableRows,
  required int headingLines,
  bool hasDivider = true,
}) {
  final margin = layout.margin.vertical;
  final total =
      margin +
      (layout.titleSize * 1.5) +
      // Label rows, table rows and totals all sit a little taller than a bare
      // line: a 9pt thermal glyph needs leading around it, and each table cell
      // adds cell padding. Underestimating here would silently cut the totals
      // off the end of the roll, so the estimate is deliberately generous. A
      // slightly long receipt is harmless; a clipped one is not recoverable.
      (layout.lineHeight * infoRows * 1.35) +
      layout.lineHeight +
      (layout.lineHeight * (tableRows + 1) * 1.6) +
      (layout.lineHeight * 3 * 1.35) +
      (hasDivider ? layout.lineHeight : 0) +
      (layout.lineHeight * headingLines * 1.35) +
      margin;
  // A floor stops a nearly empty receipt becoming a sliver of paper, and the
  // headroom keeps the last line off the cut.
  return total < 200 ? 200 : total + 72;
}

/// Builds a printable table sized to the available width.
pw.Widget buildSizedTable({
  required PaperLayout layout,
  required List<String> headers,
  required List<List<String>> data,
}) {
  if (data.isEmpty) return pw.SizedBox();
  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: data,
    headerStyle: pw.TextStyle(
      fontSize: layout.tableFontSize,
      fontWeight: pw.FontWeight.bold,
    ),
    cellStyle: pw.TextStyle(fontSize: layout.tableFontSize),
    headerDecoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
    ),
    oddRowDecoration: const pw.BoxDecoration(),
    // Long values on a narrow roll must wrap rather than run off the page.
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
  );
}

/// The standard receiving weights table, sized to the available width.
pw.Widget buildBagWeightTable(Delivery delivery, PaperLayout layout) {
  if (delivery.isBulk || delivery.bagWeights.isEmpty) {
    return buildSizedTable(
      layout: layout,
      headers: const ['Measure', 'Value'],
      data: [
        ['Number of bags', '${delivery.numberOfBags}'],
        ['Total weight', '${delivery.totalWeight.toStringAsFixed(1)} kg'],
      ],
    );
  }
  return buildSizedTable(
    layout: layout,
    headers: const ['Bag', 'Weight'],
    data: [
      for (var i = 0; i < delivery.bagWeights.length; i++)
        ['${i + 1}', '${delivery.bagWeights[i].toStringAsFixed(1)} kg'],
    ],
  );
}
