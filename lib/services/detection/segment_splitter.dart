// lib/services/detection/segment_splitter.dart
// -------------------------------------------------------------
// تقسيم النص إلى رسائل (مقاطع) — مشترك بين شاشة الفقاعات وشاشة التسليم:
// 1) هيدر واتساب المنسوخ:  [24/09, 10:30] الاسم: ...
// 2) صيغ مخصّصة يكتبها المستخدم في الإعدادات (قسم «صيغ الرسائل») بنفس
//    القوالب، مثل:  ‏[{day}/{month}، {hour}:{minute}] {name}:‏
// 3) فاصل صفوف الملفات المستوردة:  —— صف 5 ——
//    (يضيفه محوّل الملفات حتى يصبح كل صف في Excel/CSV رسالة مستقلة)
// النص بدون أي هيدر أو فاصل = رسالة واحدة (نفس السلوك القديم تمامًا).
// (ملف Dart نقي بدون Flutter)
// -------------------------------------------------------------

import 'header_format.dart';
import 'text_tokens.dart' show digitsOnly;

export 'header_format.dart'
    show HeaderFormat, HeaderFormatException, HeaderFormatSuggestion, HeaderFormats;

/// مقطع خام قبل تحويله إلى نوع المقطع الخاص بكل شاشة
class RawSegment {
  final String header;
  final String senderName;
  final DateTime? timestamp;
  final List<String> lines;

  /// true إذا جاء المقطع من صف ملف مستورد (فاصل «—— صف N ——»)
  final bool fromImportRow;

  const RawSegment({
    required this.header,
    required this.senderName,
    required this.timestamp,
    required this.lines,
    this.fromImportRow = false,
  });
}

class SegmentSplitter {
  SegmentSplitter._();

  /// هيدر واتساب عند نسخ الرسائل: [24/09, 10:30] الاسم:
  /// (نفس الصيغة المضمّنة في HeaderFormats — يتعرف أيضًا على الصيغ التي
  /// يكتبها المستخدم في الإعدادات)
  static final RegExp whatsappHeader = HeaderFormats.builtIn().pattern;

  static const String rowMarkerEdge = '——';

  /// سطر فاصل كامل: «—— صف 5 ——» أو «—— سطر 3 • ملف.xlsx ——»
  static final RegExp rowMarker = RegExp(
    r'^[ \t\u200E\u200F]*——[ \t]*((?:صف|سطر|رسالة)[ \t]*[0-9\u0660-\u0669]+[^\n]*?)[ \t]*——[ \t\u200E\u200F]*$',
    multiLine: true,
  );

  /// يبني سطر الفاصل لعنوان معيّن (مثال: «صف 5»)
  static String rowMarkerLine(String label) =>
      '$rowMarkerEdge ${label.trim()} $rowMarkerEdge';

  static bool hasRowMarkers(String text) => rowMarker.hasMatch(text);

  /// عدد رسائل واتساب (الهيدرات) في النص
  static int countWhatsappHeaders(String text, {List<String>? customFormats}) =>
      _findHeaders(text.replaceAll('\r', ''), customFormats).length;

  /// كل تطابقات الهيدر (المضمّن + المخصّص) بدون تداخل، مرتبة بالظهور.
  /// عند تطابق أكثر من صيغة على نفس الموضع تُفضّل المضمّنة، ثم الأطول.
  static List<_HeaderHit> _findHeaders(String text, List<String>? custom) {
    final formats = HeaderFormats.all(custom ?? const []);
    final hits = <_HeaderHit>[];
    for (var i = 0; i < formats.length; i++) {
      for (final m in formats[i].pattern.allMatches(text)) {
        hits.add(_HeaderHit(m, formats[i], i));
      }
    }
    hits.sort((a, b) {
      var c = a.match.start.compareTo(b.match.start);
      if (c != 0) return c;
      c = b.match.end.compareTo(a.match.end);
      if (c != 0) return c;
      return a.formatIndex.compareTo(b.formatIndex);
    });
    final out = <_HeaderHit>[];
    var lastEnd = -1;
    for (final h in hits) {
      if (h.match.start < lastEnd) continue;
      out.add(h);
      lastEnd = h.match.end;
    }
    return out;
  }

  /// يقسم النص إلى مقاطع.
  /// [headerlessLabel]: عنوان المقطع عندما لا يوجد أي هيدر (يختلف بين الشاشات).
  /// [customFormats]: قوالب الهيدر المخصّصة من الإعدادات (إن وجدت).
  static List<RawSegment> split(
    String input, {
    String headerlessLabel = '',
    DateTime? now,
    List<String>? customFormats,
  }) {
    final text = input.replaceAll('\r', '');
    final clock = now ?? DateTime.now();
    final markers = rowMarker.allMatches(text).toList();
    final headers = _findHeaders(text, customFormats);

    if (markers.isEmpty) {
      if (headers.isEmpty) {
        return [
          RawSegment(
            header: headerlessLabel,
            senderName: '',
            timestamp: null,
            lines: _lines(text),
          ),
        ];
      }
      // السلوك القديم: كل هيدر يبدأ رسالة، وما قبل أول هيدر يُتجاهل
      final out = <RawSegment>[];
      for (var i = 0; i < headers.length; i++) {
        final m = headers[i];
        final end = (i + 1 < headers.length)
            ? headers[i + 1].match.start
            : text.length;
        out.add(_fromHeader(m, text.substring(m.match.end, end), clock));
      }
      return out;
    }

    // نص فيه فواصل صفوف (وقد يحتوي أيضًا رسائل واتساب قبلها أو بعدها)
    final bounds = <_Bound>[
      for (final m in markers) _Bound(m, true, null),
      for (final h in headers)
        if (!markers.any((k) => h.match.start < k.end && h.match.end > k.start))
          _Bound(h.match, false, h.format),
    ]..sort((a, b) => a.match.start.compareTo(b.match.start));

    final out = <RawSegment>[];
    final preamble = text.substring(0, bounds.first.match.start);
    if (preamble.trim().isNotEmpty) {
      out.add(
        RawSegment(
          header: headerlessLabel,
          senderName: '',
          timestamp: null,
          lines: _trimBlankEdges(_lines(preamble)),
        ),
      );
    }
    for (var i = 0; i < bounds.length; i++) {
      final b = bounds[i];
      final end = (i + 1 < bounds.length)
          ? bounds[i + 1].match.start
          : text.length;
      final body = text.substring(b.match.end, end);
      if (b.isMarker) {
        out.add(
          RawSegment(
            header: (b.match.group(1) ?? '').trim(),
            senderName: '',
            timestamp: null,
            lines: _trimBlankEdges(_lines(body)),
            fromImportRow: true,
          ),
        );
      } else {
        out.add(
          _fromHeader(
            _HeaderHit(b.match, b.format!, 0),
            body,
            clock,
          ),
        );
      }
    }
    return out;
  }

  static List<String> _lines(String body) =>
      body.split('\n').map((e) => e.trimRight()).toList();

  static List<String> _trimBlankEdges(List<String> lines) {
    var start = 0;
    var end = lines.length;
    while (start < end && lines[start].trim().isEmpty) {
      start++;
    }
    while (end > start && lines[end - 1].trim().isEmpty) {
      end--;
    }
    return lines.sublist(start, end);
  }

  static int _toInt(String s) => int.tryParse(digitsOnly(s)) ?? 0;

  static RawSegment _fromHeader(_HeaderHit hit, String body, DateTime now) {
    final m = hit.match;
    final f = hit.format;

    String? tok(String name) => f.valueOf(m, name);

    DateTime? ts;
    final hourTok = tok('hour');
    final minuteTok = tok('minute');
    if (hourTok != null || minuteTok != null) {
      final dd = _toInt(tok('day') ?? '1');
      final mo = _toInt(tok('month') ?? '1');
      final yyTok = tok('year');
      final hh = _toInt(hourTok ?? '0');
      final mi = _toInt(minuteTok ?? '0');

      try {
        var year = now.year;
        if (yyTok != null && yyTok.trim().isNotEmpty) {
          var y = _toInt(yyTok);
          // سنة بمنزلتين: 00-68 ← 2000-2068 ، 69-99 ← 1969-1999
          if (y < 100) y += (y <= 68 ? 2000 : 1900);
          year = y;
        }
        ts = DateTime(year, mo, dd, hh, mi);
        // الهيدر لا يحتوي السنة: تاريخ بعد اليوم بأكثر من يومين يعني
        // أن الرسالة من السنة الماضية (مثلًا رسائل كانون الأول تُحلَّل في كانون الثاني)
        if (yyTok == null &&
            ts.isAfter(now.add(const Duration(days: 2)))) {
          ts = DateTime(now.year - 1, mo, dd, hh, mi);
        }
      } catch (_) {}
    }

    return RawSegment(
      header: m.group(0)!.trim(),
      senderName: (tok('name') ?? '').trim(),
      timestamp: ts,
      lines: _lines(body),
    );
  }
}

/// تطابق هيدر مع صيغته (المضمّنة أو مخصّصة)
class _HeaderHit {
  final RegExpMatch match;
  final HeaderFormat format;

  /// ترتيب الصيغة في القائمة (المضمّنة = 0) — لفك التعادل
  final int formatIndex;

  const _HeaderHit(this.match, this.format, this.formatIndex);
}

class _Bound {
  final RegExpMatch match;
  final bool isMarker;
  final HeaderFormat? format;
  const _Bound(this.match, this.isMarker, this.format);
}
