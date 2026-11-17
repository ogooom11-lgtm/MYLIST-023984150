// lib/services/detection/header_format.dart
// -------------------------------------------------------------
// صيغ الهيدر المخصّصة: علامات تفصل الرسائل داخل النص المنسوخ،
// مثل هيدر واتساب «[24/09, 10:30] الاسم:».
//
// المستخدم يكتب «قالب» في الإعدادات والبرنامج يحوّله لمطابقة، مثل:
//   [{day}/{month}, {hour}:{minute}] {name}:
//
// الرموز المسموحة (داخل {}):
//   {day} {month} {year}   — أرقام اليوم/الشهر/السنة (تقبل الأرقام
//                             العربية ٠-٩ واللاتينية)
//   {hour} {minute}        — الساعة والدقيقة
//   {name}                 — اسم المرسل (يمتد حتى أول «:» في السطر)
//
// كل حرف غير رمز يُعتبر حرفيًا كما هو، مع مرونة في:
//   • المسافات وعلامات الاتجاه (RLM/LRM...) في أي مكان،
//   • الفاصلة اللاتينية والعربية (, ،) متكافئتان.
//
// (ملف Dart نقي بدون Flutter — يمكن اختباره مباشرة)
// -------------------------------------------------------------

library;

/// خطأ في قالب صيغة (رسالة عربية مفهومة للمستخدم)
class HeaderFormatException implements Exception {
  final String message;
  const HeaderFormatException(this.message);

  @override
  String toString() => message;
}

/// صيغة واحدة مترجمة: القالب نصي + التعويض الجزائي (RegExp) + ترتيب الرموز.
class HeaderFormat {
  /// القالب كما كتبه المستخدم (بعد التشذيب)، مثال: «[{day}/{month}] {name}:»
  final String template;

  /// التعويض الجزائي النهائي (multiLine) — لا يحتوي `^` حتى يعمل داخل السطر
  final RegExp pattern;

  /// نوع كل مجموعة (group) بالترتيب: groupTokens[i] هو رمز group(i + 1).
  /// مثال: «[{day}/{month}, {hour}:{minute}] {name}:» →
  /// [day, month, hour, minute, name]
  final List<String> groupTokens;

  HeaderFormat._(this.template, this.pattern, this.groupTokens);

  static const String _digit = r'[0-9\u0660-\u0669]';

  /// فاصل مرن: مسافات وعلامات اتجاه ثنائية في أي مكان
  static const String _sep = r'[\s\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]*';

  static bool _isSpace(String ch) =>
      ch == ' ' || ch == '\t' || ch == ' ' || ch == '\n';

  /// يترجم قالبًا نصيًا إلى صيغة قابلة للتطبيق. يرمي [HeaderFormatException]
  /// برسالة عربية إذا كان القالب غير صالح.
  static HeaderFormat compile(String template) {
    final t = template.trim();
    if (t.isEmpty) {
      throw const HeaderFormatException('الصيغة فاضية');
    }
    if (t.length > 150) {
      throw const HeaderFormatException('الصيغة أطول من اللازم (الحد 150 حرف)');
    }

    final atoms = <String>[];
    final groupTokens = <String>[];
    var hasDateOrTime = false;
    var hasName = false;

    var i = 0;
    while (i < t.length) {
      final ch = t[i];
      if (ch == '{') {
        final end = t.indexOf('}', i + 1);
        if (end < 0) {
          throw const HeaderFormatException('قوس «{» بدون إغلاق «}»');
        }
        final token = t.substring(i + 1, end).trim().toLowerCase();
        switch (token) {
          case 'day':
          case 'month':
          case 'hour':
          case 'minute':
            atoms.add('$_digit{1,2}');
            groupTokens.add(token);
            hasDateOrTime = true;
            break;
          case 'year':
            atoms.add('$_digit{2,4}');
            groupTokens.add(token);
            hasDateOrTime = true;
            break;
          case 'name':
            atoms.add(r'[^:\n]+?');
            groupTokens.add(token);
            hasName = true;
            break;
          default:
            throw HeaderFormatException(
              'رمز غير معروف «{$token}» — المسموح: '
              '{day} {month} {year} {hour} {minute} {name}',
            );
        }
        i = end + 1;
        continue;
      }
      if (ch == '}') {
        throw const HeaderFormatException('قوس «}» بدون فتح «{»');
      }
      if (_isSpace(ch)) {
        // المسافات لا تُعتبر رموزًا: الفاصل المرن يتكفل بها
        i++;
        continue;
      }
      if (ch == ',' || ch == '،' || ch == '،') {
        // الفاصلة اللاتينية والعربية متكافئتان
        atoms.add('[,،]');
        i++;
        continue;
      }
      atoms.add(RegExp.escape(ch));
      i++;
    }

    if (!hasDateOrTime && !hasName) {
      throw const HeaderFormatException(
        'الصيغة لازم تحتوي على {day} أو {hour}... أو {name} على الأقل',
      );
    }

    final pattern = RegExp(atoms.join(_sep), multiLine: true);
    return HeaderFormat._(t, pattern, groupTokens);
  }

  /// قيمة رمز معين من نتيجة التطابق (أو null إن لم تكن الصيغة تحتويه)
  String? valueOf(RegExpMatch match, String token) {
    for (var i = 0; i < groupTokens.length; i++) {
      if (groupTokens[i] == token) return match.group(i + 1);
    }
    return null;
  }

  bool get hasDateOrTime =>
      groupTokens.any((t) => t != 'name');
}

/// اقتراح صيغة مكتشفة في النص (تُعرض على المستخدم ليضيفها إن أراد)
class HeaderFormatSuggestion {
  /// القالب المقترح (مثال: «[{day}/{month}, {hour}:{minute}] {name}:»)
  final String template;

  /// سطر حقيقي من النص يطابق القالب — للمعاينة
  final String sample;

  const HeaderFormatSuggestion(this.template, this.sample);
}

/// أدوات الجمع بين الصيغة المضمّنة (واتساب) والصيغ المخصّصة
class HeaderFormats {
  HeaderFormats._();

  /// الصيغة المضمّنة: هيدر واتساب المنسوخ
  static const String builtInTemplate = '[{day}/{month}, {hour}:{minute}] {name}:';

  static HeaderFormat? _builtIn;

  static HeaderFormat builtIn() =>
      _builtIn ??= HeaderFormat.compile(builtInTemplate);

  /// كل الصيغ الفعّالة: المضمّنة أولًا (أولوية عند التداخل) ثم المخصّصة.
  /// الصيغ المخصّصة المعطوبة تُتجاهل بصمت حتى لا تكسر التحليل.
  static List<HeaderFormat> all(Iterable<String> customTemplates) {
    final out = <HeaderFormat>[builtIn()];
    for (final raw in customTemplates) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      try {
        out.add(HeaderFormat.compile(t));
      } catch (_) {
        // صيغة معطوبة في الإعدادات: تُتجاهل (التطبيق يشتغل على الباقي)
      }
    }
    return out;
  }

  static final RegExp _looksLikeHeader = RegExp(
    r'^[\s\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]*'
    r'\[[^\]\n]{2,80}\]'
    r'[\s\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]*'
    r'[^:\n]{1,120}:',
  );

  static final RegExp _digitRe = RegExp(r'[0-9\u0660-\u0669]');

  /// أسطر تبدو كرؤوس رسائل لكن ما بتتطابق مع أي صيغة معروفة → اقتراحات.
  /// يعيد حتى 3 اقتراحات بأقصى حد، كل واحد بقالب مكوَّن تلقائيًا يمر
  /// بالتحقق (يترجم ويطابق السطر نفسه).
  static List<HeaderFormatSuggestion> suggestions(
    String text,
    Iterable<String> existingFormats,
  ) {
    final known = all(existingFormats);
    final byTemplate = <String, String>{};
    for (final raw in text.split('\n')) {
      if (byTemplate.length >= 3) break;
      final line = raw.trim();
      if (line.length < 8 || line.length > 200) continue;
      if (!_looksLikeHeader.hasMatch(line)) continue;
      if (!_digitRe.hasMatch(line)) continue;
      var recognized = false;
      for (final f in known) {
        if (f.pattern.hasMatch(line)) {
          recognized = true;
          break;
        }
      }
      if (recognized) continue;
      final guessed = guessTemplate(line);
      if (guessed == null) continue;
      try {
        final f = HeaderFormat.compile(guessed);
        if (!f.pattern.hasMatch(line)) continue;
      } catch (_) {
        continue;
      }
      byTemplate.putIfAbsent(guessed, () => line);
    }
    return [
      for (final e in byTemplate.entries)
        HeaderFormatSuggestion(e.key, e.value),
    ];
  }

  static const List<String> _bidiChars = [
    '\u061C',
    '\u200E',
    '\u200F',
    '\u202A',
    '\u202B',
    '\u202C',
    '\u202D',
    '\u202E',
    '\u2066',
    '\u2067',
    '\u2068',
    '\u2069',
  ];

  static String _stripBidi(String s) {
    final out = StringBuffer();
    for (final ch in s.split('')) {
      if (_bidiChars.contains(ch)) continue;
      out.write(ch);
    }
    return out.toString();
  }

  /// يبني قالبًا من سطر حقيقي يشبه الهيدر (يستبدل مقاطع الأرقام برموز
  /// حسب موضعها: يوم/شهر[/سنة] ثم ساعة:دقيقة). يعيد null إذا تعذر.
  static String? guessTemplate(String line) {
    final s = line.trim();
    final m = RegExp(
      r'^[\s\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]*'
      r'\[([^\]\n]{2,80})\]'
      r'[\s\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]*'
      r'[^:\n]{1,120}:',
    ).firstMatch(s);
    if (m == null) return null;

    final inside = _stripBidi(m.group(1)!);
    final numRe = RegExp(r'[0-9\u0660-\u0669]+');
    final nums = numRe.allMatches(inside).toList();
    // على الأقل يوم/شهر + ساعة:دقيقة
    if (nums.length < 4) return null;

    String roleAt(int index, int count) {
      if (count == 4) {
        return const ['day', 'month', 'hour', 'minute'][index];
      }
      if (count == 5) {
        return const ['day', 'month', 'year', 'hour', 'minute'][index];
      }
      // 6 أرقام فأكثر: الأولان يوم/شهر، الأخيران ساعة/دقيقة، والباقي سنة
      if (index == 0) return 'day';
      if (index == 1) return 'month';
      if (index >= count - 2) return index == count - 2 ? 'hour' : 'minute';
      return 'year';
    }

    String cleanLiteral(String raw) {
      var lit = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
      // وحّد الفاصلة العربية بالقالب (المُصرِّف بيطابق الاتنين)
      lit = lit.replaceAll('،', ',');
      return lit;
    }

    final buf = StringBuffer('[');
    var last = 0;
    for (var n = 0; n < nums.length; n++) {
      final hit = nums[n];
      buf.write(cleanLiteral(inside.substring(last, hit.start)));
      buf.write('{');
      buf.write(roleAt(n, nums.length));
      buf.write('}');
      last = hit.end;
    }
    buf.write(cleanLiteral(inside.substring(last)));
    buf.write('] {name}:');

    final template = buf.toString().replaceAll('  ', ' ').trim();
    // تحقق نهائي: القالب يُترجم ويطابق السطر نفسه
    try {
      final f = HeaderFormat.compile(template);
      if (!f.pattern.hasMatch(line)) return null;
    } catch (_) {
      return null;
    }
    return template;
  }

  /// قالب مقترح جاهز للاستخدام من الإعدادات (شرح للرموز)
  static const String syntaxHelp =
      'اكتب القالب مع الرموز التالية بين أقواس معقوفة:\n'
      '{day} يوم • {month} شهر • {year} سنة\n'
      '{hour} ساعة • {minute} دقيقة • {name} اسم المرسل\n'
      'باقي الحروف والرموز تُعتبر كما هي، والمسافات وعلامات الاتجاه '
      'يُتغاضى عنها، والفاصلة (, ،) متكافئتان.';
}
