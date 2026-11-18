import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/parse_text_screen.dart';
import 'screens/all_accounts_stats_screen.dart';
import 'screens/backup_screen.dart';
import 'database_service.dart';
import 'models.dart';
import 'theme/app_theme.dart';
import 'screens/timeline_analytics_screen.dart';
import 'screens/transaction_watch_screen.dart';
import 'services/share_import/share_import_controller.dart';
import 'services/trace/trace_service.dart';
import 'services/tx_history_service.dart';
import 'widgets/app_messages.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

Future<void>? _appInitFuture;
bool _hiveInitialized = false;

void _registerAdapterIfNeeded<T>(TypeAdapter<T> adapter) {
  if (!Hive.isAdapterRegistered(adapter.typeId)) {
    Hive.registerAdapter(adapter);
  }
}

Future<void> _initializeApp() {
  return _appInitFuture ??= () async {
    try {
      if (!_hiveInitialized) {
        await Hive.initFlutter();
        _hiveInitialized = true;
      }

      _registerAdapterIfNeeded(TransactionStatusAdapter());
      _registerAdapterIfNeeded(AccountTypeAdapter());
      _registerAdapterIfNeeded(CompanyMovementTypeAdapter());
      _registerAdapterIfNeeded(AccountAdapter());
      _registerAdapterIfNeeded(TransactionModelAdapter());
      _registerAdapterIfNeeded(BubbleQuickActionConfigAdapter());
      _registerAdapterIfNeeded(SettingsAdapter());
      _registerAdapterIfNeeded(ParsedTextAdapter());

      await DatabaseService.init();

      // شكل ومكان رسائل النجاح والخطأ (من الإعدادات)
      AppMessages.load();

      // سجل تعديلات الحركات: يراقب كل تغيير على الحركات من أي شاشة
      try {
        TxHistoryService.start();
      } catch (e) {
        debugPrint('TxHistory start error: $e');
      }

      // تتبّع مصدر الحركة (شركة ← مكتب): يحسب بالخلفية ويتحدث مع كل تغيير
      try {
        TraceService.start();
      } catch (e) {
        debugPrint('Trace start error: $e');
      }
    } catch (e, s) {
      _appInitFuture = null;
      debugPrint('Startup error: $e');
      debugPrintStack(stackTrace: s);
      rethrow;
    }
  }();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: MaterialApp(
        title: 'مدير الحسابات',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        // كل رسائل النجاح والخطأ بتنعرض بشكل موحّد وبالمكان المختار
        builder: (context, child) =>
            StyledScaffoldMessenger(child: child ?? const SizedBox.shrink()),
        home: const StartupSignatureScreen(),
      ),
    );
  }
}

class StartupSignatureScreen extends StatefulWidget {
  const StartupSignatureScreen({super.key});

  @override
  State<StartupSignatureScreen> createState() => _StartupSignatureScreenState();
}

class _StartupSignatureScreenState extends State<StartupSignatureScreen> {
  bool _done = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _startLoading();
  }

  Future<void> _startLoading() async {
    if (_error != null && mounted) {
      setState(() => _error = null);
    }
    try {
      await _initializeApp();
      if (!mounted) return;
      setState(() => _done = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF222426)
        : const Color(0xFFE7E7E4);
    final mutedInk = isDark ? const Color(0xFFBEBEB8) : const Color(0xFF686A6B);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _done
          ? const MainLayout()
          : Scaffold(
              key: const ValueKey('startup-signature'),
              backgroundColor: background,
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 220,
                        height: 220,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(50),
                          child: Image.asset(
                            'assets/icons/app_icon.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'مدير الحسابات',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: mutedInk,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (_error == null)
                        SizedBox(
                          width: 120,
                          child: LinearProgressIndicator(
                            minHeight: 3,
                            borderRadius: BorderRadius.circular(99),
                            color: mutedInk,
                            backgroundColor: mutedInk.withOpacity(0.18),
                          ),
                        )
                      else ...[
                        Text(
                          'تعذر تهيئة بيانات التطبيق',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.tonal(
                          onPressed: _startLoading,
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _openingParse = false;
  bool _checkingClipboard = false;
  String? _pendingClipboardText;
  String? _lastOpenedClipboardText;
  Timer? _clipboardTimer;

  late final List<Widget> _pages;

  late final AnimationController _parseController;
  late final Animation<double> _parseScale;

  /// استقبال الملفات المشاركة من تطبيقات أخرى (أندرويد)
  late final ShareImportController _shareImport = ShareImportController(
    contextOf: () => mounted ? context : null,
    openPage: (page) {
      if (!mounted) return;
      Navigator.of(context).push(_pageRoute(page));
    },
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _shareImport.start();
    });

    _pages = const [
      HomeScreen(),
      AllAccountsStatsScreen(),
      TransactionWatchScreen(),
      BackupScreen(),
      SettingsScreen(),
      TimelineAnalyticsScreen(),
    ];

    _parseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _parseScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.86,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.86,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 55,
      ),
    ]).animate(_parseController);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareImport.dispose();
    _clipboardTimer?.cancel();
    _parseController.dispose();
    super.dispose();
  }

  Future<void> _openParseText({String? initialText}) async {
    if (_openingParse) return;
    _openingParse = true;
    if (initialText != null && initialText.trim().isNotEmpty) {
      _lastOpenedClipboardText = initialText.trim();
      if (mounted) setState(() => _pendingClipboardText = null);
    }

    await _parseController.forward();

    if (!mounted) return;

    await Navigator.of(
      context,
    ).push(_pageRoute(ParseTextScreen(initialText: initialText)));

    if (!mounted) return;

    await _parseController.reverse();
    _openingParse = false;
  }

  PageRoute _pageRoute(Widget page) {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final fade = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        final slide = Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(fade);

        return FadeTransition(
          opacity: fade,
          child: SlideTransition(position: slide, child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,

      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: KeyedSubtree(
                key: ValueKey(_currentIndex),
                child: _pages[_currentIndex],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: _parseController,
        builder: (context, _) {
          return _CompactBottomBar(
            currentIndex: _currentIndex,
            onSelect: (i) => setState(() => _currentIndex = i),
            onParseTap: () => _openParseText(),
            parseScale: _parseScale.value,
          );
        },
      ),
    );
  }
}

class _CompactBottomBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onParseTap;
  final double parseScale;

  const _CompactBottomBar({
    required this.currentIndex,
    required this.onSelect,
    required this.onParseTap,
    required this.parseScale,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              height: 74,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    cs.surface.withOpacity(isDark ? 0.92 : 0.97),
                    cs.surfaceContainerHighest.withOpacity(
                      isDark ? 0.82 : 0.93,
                    ),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(isDark ? 0.08 : 0.7),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.22 : 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _BottomItem(
                      label: 'الرئيسية',
                      icon: Icons.home_outlined,
                      selectedIcon: Icons.home_rounded,
                      selected: currentIndex == 0,
                      onTap: () => onSelect(0),
                    ),
                  ),
                  Expanded(
                    child: _BottomItem(
                      label: 'الإحصائيات',
                      icon: Icons.bar_chart_rounded,
                      selectedIcon: Icons.insert_chart_rounded,
                      selected: currentIndex == 1,
                      onTap: () => onSelect(1),
                    ),
                  ),
                  Expanded(
                    child: _BottomItem(
                      label: 'المراقبة',
                      icon: Icons.radar_outlined,
                      selectedIcon: Icons.radar_rounded,
                      selected: currentIndex == 2,
                      onTap: () => onSelect(2),
                    ),
                  ),
                  Expanded(
                    child: _BottomItem(
                      label: 'النسخ',
                      icon: Icons.backup_outlined,
                      selectedIcon: Icons.backup_rounded,
                      selected: currentIndex == 3,
                      onTap: () => onSelect(3),
                    ),
                  ),
                  Expanded(
                    child: _BottomItem(
                      label: 'الإعدادات',
                      icon: Icons.settings_outlined,
                      selectedIcon: Icons.settings_rounded,
                      selected: currentIndex == 4,
                      onTap: () => onSelect(4),
                    ),
                  ),
                  Expanded(
                    child: _BottomItem(
                      label: 'زمنية',
                      icon: Icons.timeline,
                      selectedIcon: Icons.timeline_sharp,
                      selected: currentIndex == 5,
                      onTap: () => onSelect(5),
                    ),
                  ),
                  SizedBox(
                    width: 62,
                    child: Center(
                      child: Transform.scale(
                        scale: parseScale,
                        child: _ParseCircleButton(onTap: onParseTap),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onTap;

  const _BottomItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 22 : 0,
                height: 3,
                margin: const EdgeInsets.only(bottom: 5),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Icon(
                selected ? selectedIcon : icon,
                color: selected ? cs.primary : cs.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.2,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParseCircleButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ParseCircleButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                cs.primary,
                Color.lerp(cs.primary, cs.tertiary, 0.35) ?? cs.primary,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withOpacity(0.22),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
