/// A company's printing preferences, as stored against that company.
///
/// Every field is business configuration that belongs to one company and must
/// never bleed into another. Defaults exist so a brand new company prints
/// sensibly on its very first document without anybody having to visit
/// settings first, but every value is overridable.
class CompanyPrintProfile {
  const CompanyPrintProfile({
    this.receiptPaper = PaperSize.thermal80,
    this.reportPaper = PaperSize.a4,
    this.statementPaper = PaperSize.a4,
    this.showPreview = true,
  });

  /// Paper for receiving receipts.
  final PaperSize receiptPaper;

  /// Paper for reports and analytics.
  final PaperSize reportPaper;

  /// Paper for supplier statements and histories.
  final PaperSize statementPaper;

  /// Whether opening a print action shows the preview first.
  ///
  /// Preview is on by default because printing is hard to undo, but an
  /// established user who has a fast, trusted printer setup can turn it off
  /// rather than being forced through a dialog on every receipt.
  final bool showPreview;

  /// Reads a company row, tolerating absent or unrecognised values.
  ///
  /// Reading never throws: a row saved by an older build, or one written by
  /// hand, still yields a usable profile.
  factory CompanyPrintProfile.fromCompanyRow(Map<String, dynamic> row) {
    return CompanyPrintProfile(
      receiptPaper: PaperSize.fromId(
        row['receipt_paper_size'] as String?,
        fallback: PaperSize.thermal80,
      ),
      reportPaper: PaperSize.fromId(
        row['report_paper_size'] as String?,
        fallback: PaperSize.a4,
      ),
      statementPaper: PaperSize.fromId(
        row['statement_paper_size'] as String?,
        fallback: PaperSize.a4,
      ),
      showPreview: (row['print_show_preview'] as bool?) ?? true,
    );
  }

  /// The columns to write back, named exactly as the database names them.
  Map<String, dynamic> toCompanyColumns() => {
    'receipt_paper_size': receiptPaper.id,
    'report_paper_size': reportPaper.id,
    'statement_paper_size': statementPaper.id,
    'print_show_preview': showPreview,
  };

  CompanyPrintProfile copyWith({
    PaperSize? receiptPaper,
    PaperSize? reportPaper,
    PaperSize? statementPaper,
    bool? showPreview,
  }) => CompanyPrintProfile(
    receiptPaper: receiptPaper ?? this.receiptPaper,
    reportPaper: reportPaper ?? this.reportPaper,
    statementPaper: statementPaper ?? this.statementPaper,
    showPreview: showPreview ?? this.showPreview,
  );

  @override
  bool operator ==(Object other) =>
      other is CompanyPrintProfile &&
      other.receiptPaper == receiptPaper &&
      other.reportPaper == reportPaper &&
      other.statementPaper == statementPaper &&
      other.showPreview == showPreview;

  @override
  int get hashCode =>
      Object.hash(receiptPaper, reportPaper, statementPaper, showPreview);
}

///
/// Deliberately kept out of the company profile and out of the database. A
/// printer belongs to the device it is plugged into, not to a business, so
/// storing it centrally would be wrong twice over: the company would inherit a
/// printer name that does not exist on the machine printing it, and two
/// companies sharing one machine could never each keep their own printer.
///
/// The printer is therefore remembered per company, but only on the device that
/// was used, so switching between two companies on one PC still gives each its
/// own printer while neither is forced onto another PC.
class DevicePrinterPreference {
  const DevicePrinterPreference({this.receiptPrinter, this.reportPrinter});

  /// Windows/printer-system name for receipts. Null means "let the operating
  /// system's own default printer handle it", which is the correct answer on a
  /// machine with one printer and the only sensible answer on Android, where
  /// there is no equivalent picker at all.
  final String? receiptPrinter;

  /// Windows/printer-system name for reports and statements.
  final String? reportPrinter;

  DevicePrinterPreference copyWith({
    String? receiptPrinter,
    String? reportPrinter,
    bool clearReceiptPrinter = false,
    bool clearReportPrinter = false,
  }) => DevicePrinterPreference(
    receiptPrinter: clearReceiptPrinter
        ? null
        : (receiptPrinter ?? this.receiptPrinter),
    reportPrinter: clearReportPrinter
        ? null
        : (reportPrinter ?? this.reportPrinter),
  );

  Map<String, dynamic> toJson() => {
    'receiptPrinter': receiptPrinter,
    'reportPrinter': reportPrinter,
  };

  factory DevicePrinterPreference.fromJson(Map<String, dynamic> json) =>
      DevicePrinterPreference(
        receiptPrinter: json['receiptPrinter'] as String?,
        reportPrinter: json['reportPrinter'] as String?,
      );
}

/// Paper sizes a company can print on.
///
/// Platform independent on purpose: this is business configuration, not a
/// Windows or Android concept, so the same setting travels with the company
/// whichever machine opens it. Nothing here names a particular printer, vendor
/// or business.
///
/// The millimetre figures are the physical media, converted to PostScript
/// points for the PDF engine. A thermal roll has no fixed height, so its height
/// is derived from the content at build time rather than fixed here.
enum PaperSize {
  thermal58('thermal58', '58 mm (thermal receipt)', 58.0),
  thermal80('thermal80', '80 mm (thermal receipt)', 80.0),
  a5('a5', 'A5', 148.0),
  a4('a4', 'A4', 210.0),
  letter('letter', 'Letter', 215.9),
  legal('legal', 'Legal', 215.9);

  const PaperSize(this.id, this.label, this.widthMm);

  /// Stable identifier written to the database. Never derive the stored value
  /// from [label]; changing a label must not orphan a company's setting.
  final String id;

  final String label;

  /// Media width in millimetres.
  final double widthMm;

  /// Media height in millimetres. Thermal rolls are continuous, so they report
  /// zero height and are sized from their content instead.
  double get heightMm => switch (this) {
    PaperSize.thermal58 || PaperSize.thermal80 => 0,
    PaperSize.a5 => 210.0,
    PaperSize.a4 => 297.0,
    PaperSize.letter => 279.4,
    PaperSize.legal => 355.6,
  };

  /// True for continuous-feed receipt printers, which get a receipt layout
  /// rather than a page layout.
  bool get isThermal =>
      this == PaperSize.thermal58 || this == PaperSize.thermal80;

  /// Width in PostScript points, the unit the PDF engine works in.
  double get widthPt => widthMm * 72.0 / 25.4;

  /// Height in points, for the fixed-height sheet sizes.
  double get heightPt => heightMm * 72.0 / 25.4;

  /// Paper sizes offered for receiving receipts.
  ///
  /// Thermal and sheet sizes are both legitimate here: a company on an 80 mm
  /// roll and a company filing A4 receipts are both real customers, so neither
  /// group is treated as the default or the special case.
  static const receiptOptions = <PaperSize>[
    PaperSize.thermal80,
    PaperSize.thermal58,
    PaperSize.a4,
    PaperSize.a5,
    PaperSize.letter,
    PaperSize.legal,
  ];

  /// Paper sizes offered for reports and supplier statements.
  ///
  /// Thermal is deliberately absent. A statement is a multi-row table that has
  /// to stay readable on paper that can be filed; there is no honest 58 mm
  /// layout for one, and offering it would only invite a broken printout.
  static const sheetOptions = <PaperSize>[
    PaperSize.a4,
    PaperSize.a5,
    PaperSize.letter,
    PaperSize.legal,
  ];

  /// Resolves a stored identifier, falling back to [fallback] for anything
  /// unrecognised.
  ///
  /// A company's stored value must never be able to crash printing, so an
  /// unknown or corrupt entry degrades to a sensible default instead.
  static PaperSize fromId(String? id, {required PaperSize fallback}) {
    if (id == null) return fallback;
    for (final size in PaperSize.values) {
      if (size.id == id) return size;
    }
    return fallback;
  }

  /// True when [id] names a paper size this build understands.
  static bool isKnownId(String? id) {
    if (id == null) return false;
    for (final size in PaperSize.values) {
      if (size.id == id) return true;
    }
    return false;
  }
}
