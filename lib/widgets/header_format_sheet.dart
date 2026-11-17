// lib/widgets/header_format_sheet.dart
// -------------------------------------------------------------
// «صيغة تشبه المعروفة»: عندما يعثر التطبيق في النص المنسوخ على أسطر
// تبدو كرؤوس رسائل لكن لا تطابق أي صيغة معروفة (المضمّنة أو المخصّصة)،
// يعرض رسالة على المستخدم: يضيفها للتعرف أو يتجاهلها.
//
// تُستدعى مرة واحدة قبل بدء التحليل في «الفقاعات» وفي «التسليم».
// -------------------------------------------------------------

import 'package:flutter/material.dart';

import '../database_service.dart';
import '../services/detection/header_format.dart';
import '../services/settings_words.dart';

/// قوالب تجاهلها المستخدم في هذه الجلسة (لا يُسأل عنها مجددًا)
final Set<String> _dismissedTemplates = <String>{};

/// يفحص النص ويعرض اقتراح الصيغ غير المعروفة (إن وجدت).
/// يعيد true إذا أضاف المستخدم صيغًا جديدة (على المُستدعي إعادة التقسيم).
Future<bool> showHeaderFormatSuggestIfAny(
  BuildContext context,
  String rawText,
) async {
  if (rawText.trim().isEmpty) return false;

  final settings = DatabaseService.getSettings();
  final current = settings?.customHeaderFormats ?? const <String>[];
  final suggestions = HeaderFormats.suggestions(rawText, current)
      .where((s) => !_dismissedTemplates.contains(s.template))
      .toList();
  if (suggestions.isEmpty) return false;

  final add = await showDialog<bool>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        icon: const Icon(Icons.playlist_add_check_rounded),
        title: const Text('لقينا صيغة قريبة'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'هالسطور بتشبه هيدر الرسائل بس ما بتتعرف عليها الصيغ المعتمدة. '
                'بدك ضيفها للتعرف؟',
                style: TextStyle(fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 12),
              for (final s in suggestions)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Theme.of(ctx).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.sample,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.template,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Theme.of(ctx).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              for (final s in suggestions) {
                _dismissedTemplates.add(s.template);
              }
              Navigator.of(ctx).pop(false);
            },
            child: const Text('تجاهل'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('أضف للتعرف'),
          ),
        ],
      ),
    ),
  );

  if (add != true) return false;

  try {
    final s = DatabaseService.getSettings() ?? SettingsWords.defaults();
    final merged = <String>{
      ...s.customHeaderFormats,
      for (final sug in suggestions) sug.template,
    }.toList();
    s.customHeaderFormats = merged;
    await DatabaseService.saveSettings(s);
    return true;
  } catch (e) {
    debugPrint('showHeaderFormatSuggestIfAny save error: $e');
    return false;
  }
}
