// packages/share_intake/lib/share_intake.dart
// -------------------------------------------------------------
// «استقبال المشاركة»: يستلم ملفات ونصوص المحادثات يشاركها المستخدم من
// تطبيقات ثانية (أكسل/CSV/نص عادي/تصدير محادثات واتساب) — ينسخها النشاط
// الشفاف إلى مجلد الكاش، ثم يعلم Dart عبر EventChannel «my_list/share_intake/events»،
// وDart يأخذها عبر MethodChannel «my_list/share_intake» (takePending).
// أندرويد فقط.
// -------------------------------------------------------------

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ملف مشارك (نُسخ إلى مجلد الكاش عند المشاركة)
class SharedIntakeFile {
  /// مسار الملف على الجهاز (في مجلد الكاش)
  final String path;

  /// اسم الملف كما كان في التطبيق المصدر
  final String name;
  final String? mimeType;

  /// الحجم بالبايت (0 إن لم يعرف)
  final int size;

  const SharedIntakeFile({
    required this.path,
    required this.name,
    this.mimeType,
    this.size = 0,
  });

  factory SharedIntakeFile.fromMap(Map<dynamic, dynamic> m) {
    final size = m['size'];
    return SharedIntakeFile(
      path: m['path']?.toString() ?? '',
      name: m['name']?.toString() ?? '',
      mimeType: m['mimeType']?.toString(),
      size: size is num ? size.toInt() : int.tryParse('$size') ?? 0,
    );
  }
}

/// مشاركة كاملة (قد تحتوي ملفات، أو نصًا، أو الاثنين، أو أخطاء فقط)
class SharedIntake {
  /// ملفات مشاركة (قد تكون فاضية عند مشاركة النص فقط)
  final List<SharedIntakeFile> files;

  /// النص المشارك — عند مشاركة نص من تطبيق آخر
  final String? text;

  /// موضوع الرسالة/البريد إن وجد
  final String? subject;

  /// أخطاء القراءة (مثل: too_large / cannot open / blocked)
  final List<String> errors;

  /// وقت المشاركة (milliseconds since epoch)
  final int time;

  const SharedIntake({
    this.files = const [],
    this.text,
    this.subject,
    this.errors = const [],
    this.time = 0,
  });

  bool get hasText => (text?.trim().isNotEmpty) ?? false;

  /// فاضية بالكامل (لا ملفات ولا نص)
  bool get isEmpty => files.isEmpty && !hasText;

  factory SharedIntake.fromMap(Map<dynamic, dynamic> m) {
    final rawFiles = m['files'];
    final files = <SharedIntakeFile>[
      if (rawFiles is List)
        for (final f in rawFiles)
          if (f is Map) SharedIntakeFile.fromMap(f),
    ];
    final rawErrors = m['errors'];
    final errors = <String>[
      if (rawErrors is List)
        for (final e in rawErrors) e?.toString() ?? '',
    ].where((e) => e.isNotEmpty).toList();
    final time = m['time'];
    return SharedIntake(
      files: files,
      text: m['text']?.toString(),
      subject: m['subject']?.toString(),
      errors: errors,
      time: time is num ? time.toInt() : int.tryParse('$time') ?? 0,
    );
  }
}

class ShareIntake {
  ShareIntake._();

  static const MethodChannel _channel = MethodChannel('my_list/share_intake');
  static const EventChannel _events = EventChannel(
    'my_list/share_intake/events',
  );

  /// استقبال المشاركات يعمل على أندرويد فقط
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Stream<String>? _pending;

  /// يصدر "pending" كلما وصلت مشاركة جديدة
  static Stream<String> get onPending {
    if (!isSupported) return const Stream<String>.empty();
    return _pending ??= _events
        .receiveBroadcastStream()
        .map((e) => '$e')
        .handleError((Object _) {});
  }

  /// هل توجد مشاركة معلّقة الآن؟
  static Future<bool> hasPending() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('hasPending') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// يأخذ كل المشاركات المعلّقة ويفرغها من القائمة
  static Future<List<SharedIntake>> takePending() async {
    if (!isSupported) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('takePending');
      if (raw == null) return const [];
      return [
        for (final item in raw)
          if (item is Map) SharedIntake.fromMap(item),
      ];
    } catch (_) {
      return const [];
    }
  }
}
