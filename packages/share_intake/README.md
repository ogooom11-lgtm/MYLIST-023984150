# share_intake

بلجن محلي لأندرويد لتطبيق `my_list`: يستقبل الملفات والنصوص اللي يشاركها
المستخدم من تطبيقات ثانية (Excel / CSV / نص عادي / تصدير محادثات واتساب)،
ينسخها إلى مجلد الكاش، ثم يعلم Dart عبر قناة أحداث، وDart يأخذها عبر قناة
الأوامر.

## القنوات

- MethodChannel `my_list/share_intake`:
  - `takePending` → قائمة المشاركات المعلّقة ويفرغها:
    `[{action, files: [{path, name, mimeType, size}], text, subject, errors, time}]`
  - `hasPending` → `true` إن وجدت مشاركة معلّقة
- EventChannel `my_list/share_intake/events`: يصدر `"pending"` عند وصول
  مشاركة جديدة.

## ملاحظات

- الحد الأقصى: 10 ملفات، 30 ميغابايت لكل ملف.
- الملفات تُنسخ إلى `cacheDir/share_intake/`، ومسارات إشارات `file://` التي
  تشير إلى مجلد بيانات التطبيق تُرفض.
- أندرويد فقط؛ `ShareIntake.isSupported` يرجع `false` على بقية المنصات.
