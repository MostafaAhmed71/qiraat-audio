import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'app_state.dart';
import 'catalog.dart';

const green = Color(0xFF102C2A),
    gold = Color(0xFFC5A46D),
    ivory = Color(0xFFF7F3E9);
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'app.qiraat.audio.playback',
      androidNotificationChannelName: 'تلاوات القرآن الكريم',
      androidNotificationOngoing: true,
    );
  }
  runApp(const ProviderScope(child: QiraatApp()));
}

final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomePage()),
    GoRoute(path: '/riwayat', builder: (context, state) => const RiwayatPage()),
    GoRoute(
      path: '/reciters/:id',
      builder: (context, state) =>
          RecitersPage(id: int.tryParse(state.pathParameters['id']!) ?? 0),
    ),
    GoRoute(
      path: '/suwar/:id',
      builder: (context, state) =>
          SuwarPage(id: int.tryParse(state.pathParameters['id']!) ?? 0),
    ),
    GoRoute(path: '/player', builder: (context, state) => const PlayerPage()),
    GoRoute(
      path: '/downloads',
      builder: (context, state) => const SavedPage(downloads: true),
    ),
    GoRoute(
      path: '/favorites',
      builder: (context, state) => const SavedPage(downloads: false),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsPage(),
    ),
  ],
  errorBuilder: (context, state) => const Frame(
    title: 'الصفحة غير موجودة',
    child: EmptyState(
      icon: Icons.explore_outlined,
      text: 'اختر إحدى الصفحات من القائمة',
    ),
  ),
);

class QiraatApp extends StatelessWidget {
  const QiraatApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'القراءات العشر | Qiraat Audio',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      fontFamily: 'NotoNaskhArabic',
      useMaterial3: true,
      scaffoldBackgroundColor: ivory,
      colorScheme: ColorScheme.fromSeed(
        seedColor: green,
        primary: green,
        secondary: gold,
        surface: ivory,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: ivory,
        foregroundColor: green,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE6DFD0)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    routerConfig: router,
    builder: (context, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
  );
}

class Ready extends ConsumerStatefulWidget {
  final Widget Function(BuildContext, Catalog, AppState) builder;
  const Ready({super.key, required this.builder});
  @override
  ConsumerState<Ready> createState() => _ReadyState();
}

class _ReadyState extends ConsumerState<Ready> {
  Future<void>? initialization;
  @override
  Widget build(BuildContext context) {
    final c = ref.watch(catalogProvider);
    final s = ref.watch(stateProvider);
    return c.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => EmptyState(
        icon: Icons.error_outline,
        text: 'تعذر قراءة فهرس التلاوات',
        action: () => ref.invalidate(catalogProvider),
        actionText: 'إعادة المحاولة',
      ),
      data: (data) {
        initialization ??= s.init(data);
        return FutureBuilder<void>(
          future: initialization,
          builder: (context, snap) {
            if (snap.hasError)
              return EmptyState(
                icon: Icons.storage_outlined,
                text:
                    'تعذر فتح التخزين المحلي. تحقق من مساحة الجهاز وإعدادات المتصفح.',
                actionText: 'إعادة المحاولة',
                action: () => setState(() => initialization = null),
              );
            if (!s.ready)
              return const Center(child: CircularProgressIndicator());
            return widget.builder(context, data, s);
          },
        );
      },
    );
  }
}

class Frame extends ConsumerWidget {
  final String title;
  final Widget child;
  const Frame({super.key, required this.title, required this.child});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final index = path == '/downloads'
        ? 2
        : path == '/favorites'
        ? 3
        : path == '/riwayat' ||
              path.startsWith('/reciters') ||
              path.startsWith('/suwar')
        ? 1
        : 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        leading: path != '/'
            ? IconButton(
                tooltip: 'رجوع',
                icon: const Icon(Icons.arrow_back),
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/'),
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'الإعدادات',
            icon: const Icon(Icons.tune),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: child,
          ),
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) =>
                context.go(['/', '/riwayat', '/downloads', '/favorites'][i]),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: 'الرئيسية',
              ),
              NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                label: 'الروايات',
              ),
              NavigationDestination(
                icon: Icon(Icons.download_for_offline_outlined),
                label: 'التنزيلات',
              ),
              NavigationDestination(
                icon: Icon(Icons.favorite_border),
                label: 'المفضلة',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stateProvider);
    if (s.current == null || GoRouterState.of(context).uri.path == '/player')
      return const SizedBox.shrink();
    return Material(
      color: green,
      child: ListTile(
        textColor: ivory,
        iconColor: gold,
        title: Text(
          'سورة ${s.catalog?.suwar[s.surah] ?? ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          s.current!.reciter,
          style: const TextStyle(color: ivory),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => context.push('/player'),
        trailing: StreamBuilder<bool>(
          stream: s.player.playingStream,
          initialData: s.player.playing,
          builder: (_, snap) => IconButton(
            tooltip: snap.data == true ? 'إيقاف مؤقت' : 'تشغيل',
            onPressed: s.busy ? null : s.toggle,
            icon: Icon(
              snap.data == true ? Icons.pause : Icons.play_arrow,
              color: gold,
            ),
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? action;
  final String? actionText;
  const EmptyState({
    super.key,
    required this.icon,
    required this.text,
    this.action,
    this.actionText,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: gold),
          const SizedBox(height: 20),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, height: 1.7),
          ),
          if (action != null)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: FilledButton(
                onPressed: action,
                child: Text(actionText ?? 'متابعة'),
              ),
            ),
        ],
      ),
    ),
  );
}

class Notice extends StatelessWidget {
  final String text;
  const Notice(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: gold.withValues(alpha: .15),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(text, style: const TextStyle(height: 1.7, color: green)),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) => Frame(
    title: 'القراءات العشر',
    child: Ready(
      builder: (context, c, s) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: green,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.graphic_eq, color: gold, size: 42),
                const SizedBox(height: 24),
                const Text(
                  'أنصت بقلبك',
                  style: TextStyle(
                    color: ivory,
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'رحلة استماع إلى القرآن الكريم\nاختر الرواية، ثم القارئ والسورة.',
                  style: TextStyle(color: ivory, height: 1.9, fontSize: 17),
                ),
                const SizedBox(height: 24),
                FilledButton.styleFrom(
                  backgroundColor: gold,
                  foregroundColor: green,
                ).letButton(context),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '٢٠ رواية • ${c.mushafs.map((m) => m.riwaya).toSet().length} رواية متاحة صوتيًا في المصدر',
            style: const TextStyle(color: green, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (c.mushafs
                  .where((m) => m.reciterId == 278)
                  .map((m) => m.riwaya)
                  .toSet()
                  .length ==
              20)
            Card(
              child: ListTile(
                leading: const Icon(Icons.headphones, color: green),
                title: const Text('الشيخ أحمد عيسى المعصراوي'),
                subtitle: const Text(
                  'متاح في الروايات العشرين • ستجده أول قائمة القراء. معظم الروايات تضم ٦٤ سورة، وحفص كامل.',
                ),
                onTap: () => context.push('/riwayat'),
              ),
            ),
          if (s.last != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.history, color: green),
                title: const Text('أكمل الاستماع'),
                subtitle: const Text('العودة إلى آخر سورة وموضع محفوظ'),
                trailing: const Icon(Icons.play_circle_outline),
                onTap: () {
                  unawaited(s.resumeLast());
                  context.push('/player');
                },
              ),
            ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.offline_bolt_outlined),
              title: const Text('مكتبتك دون إنترنت'),
              subtitle: Text('${s.downloaded.length} سورة محملة'),
              onTap: () => context.push('/downloads'),
            ),
          ),
          const Notice(
            'الفهرس متاح دون إنترنت. الصوت يحتاج اتصالًا عند الاستماع الأول، أو تنزيلًا مسبقًا. الروايات غير المتوفرة في المصدر تظهر بوضوح.',
          ),
          const Text(
            'مصادر التلاوات: MP3Quran • ن للقرآن وعلومه',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    ),
  );
}

extension on ButtonStyle {
  Widget letButton(BuildContext context) => FilledButton(
    style: this,
    onPressed: () => context.push('/riwayat'),
    child: const Text('ابدأ الاستماع  ←'),
  );
}

class RiwayatPage extends StatelessWidget {
  const RiwayatPage({super.key});
  @override
  Widget build(BuildContext context) => Frame(
    title: 'اختر الرواية',
    child: Ready(
      builder: (context, c, s) => ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: c.riwayat.length,
        itemBuilder: (context, i) {
          final r = c.riwayat[i];
          final mm = c.forRiwaya(r.id);
          final count = mm.map((m) => m.reciterId).toSet().length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (i.isEven)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
                  child: Text(
                    'قراءة ${r.qiraa}',
                    style: const TextStyle(
                      color: green,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: green.withValues(alpha: .08),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(color: green),
                    ),
                  ),
                  title: Text(
                    'رواية ${r.narrator}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    mm.isEmpty
                        ? 'غير متاحة منفردة في المصدر الحالي'
                        : '$count قارئ • ${mm.length} مصحف',
                  ),
                  trailing: Icon(
                    mm.isEmpty ? Icons.info_outline : Icons.chevron_left,
                    color: mm.isEmpty ? Colors.grey : green,
                  ),
                  onTap: () => context.push('/reciters/${r.id}'),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class RecitersPage extends StatefulWidget {
  final int id;
  const RecitersPage({super.key, required this.id});
  @override
  State<RecitersPage> createState() => _RecitersPageState();
}

class _RecitersPageState extends State<RecitersPage> {
  String query = '';
  @override
  Widget build(BuildContext context) => Frame(
    title: 'اختر القارئ',
    child: Ready(
      builder: (context, c, s) {
        final mm = c.forRiwaya(widget.id);
        final rr = c.riwayat.where((r) => r.id == widget.id).firstOrNull;
        if (mm.isEmpty)
          return const EmptyState(
            icon: Icons.headphones_outlined,
            text:
                'لا توجد تسجيلات مصنفة لهذه الرواية منفردة في المصدر الحالي. لن نعرض تسجيلات برواية أخرى بدلًا منها.',
          );
        final filtered = mm
            .where((m) => m.reciter.contains(query) || m.name.contains(query))
            .toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                children: [
                  Text(
                    rr?.label ?? '',
                    style: const TextStyle(color: green, fontSize: 17),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'ابحث باسم القارئ',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => query = v.trim()),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const EmptyState(
                      icon: Icons.search_off,
                      text: 'لا توجد نتائج مطابقة',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final m = filtered[i];
                        return Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: const CircleAvatar(
                              backgroundColor: green,
                              child: Icon(Icons.person_outline, color: gold),
                            ),
                            title: Text(
                              m.reciter,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${m.name}\n${m.surahs.length} سورة متاحة',
                              style: const TextStyle(height: 1.7),
                            ),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: () => context.push('/suwar/${m.id}'),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}

class SuwarPage extends StatefulWidget {
  final int id;
  const SuwarPage({super.key, required this.id});
  @override
  State<SuwarPage> createState() => _SuwarPageState();
}

class _SuwarPageState extends State<SuwarPage> {
  String query = '';
  @override
  Widget build(BuildContext context) => Frame(
    title: 'اختر السورة',
    child: Ready(
      builder: (context, c, s) {
        final m = c.mushafs.where((m) => m.id == widget.id).firstOrNull;
        if (m == null)
          return const EmptyState(
            icon: Icons.error_outline,
            text: 'المصحف غير موجود في الفهرس',
          );
        final ss = m.surahs
            .where((n) => c.suwar[n]!.contains(query) || '$n' == query)
            .toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.reciter,
                    style: const TextStyle(
                      color: green,
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(m.name),
                  if (kIsWeb && !m.webDownloads)
                    const Notice(
                      'الاستماع متاح. التنزيل داخل المتصفح غير متاح لهذا المصدر؛ استخدم تطبيق أندرويد للتنزيل والاستماع دون إنترنت.',
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: kIsWeb && !m.webDownloads
                        ? null
                        : () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('تنزيل السور المتاحة؟'),
                                content: Text(
                                  'سيتم تنزيل ${m.surahs.length} سورة بالتتابع. قد يحتاج ذلك إلى مساحة كبيرة ووقت طويل. يُفضّل اتصال Wi-Fi. على الويب أبق التطبيق مفتوحًا.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('إلغاء'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('تنزيل'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) await s.enqueue(m, m.surahs);
                          },
                    icon: const Icon(Icons.download_outlined),
                    label: Text(
                      'تنزيل ${m.surahs.length == 114 ? 'المصحف كاملًا' : 'السور المتاحة (${m.surahs.length})'}',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'ابحث باسم السورة أو رقمها',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => query = v.trim()),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ss.isEmpty
                  ? const EmptyState(
                      icon: Icons.search_off,
                      text: 'لا توجد سورة مطابقة في هذا المصحف',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: ss.length,
                      itemBuilder: (context, i) =>
                          SurahTile(m: m, number: ss[i], c: c, state: s),
                    ),
            ),
          ],
        );
      },
    ),
  );
}

class SurahTile extends StatelessWidget {
  final Mushaf m;
  final int number;
  final Catalog c;
  final AppState state;
  final bool showReciter;
  const SurahTile({
    super.key,
    required this.m,
    required this.number,
    required this.c,
    required this.state,
    this.showReciter = false,
  });
  @override
  Widget build(BuildContext context) {
    final keyName = m.key(number);
    final saved = state.downloaded.contains(keyName);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: green.withValues(alpha: .08),
                child: Text('$number'),
              ),
              title: Text(
                'سورة ${c.suwar[number]}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                showReciter
                    ? '${m.reciter} • ${m.name}'
                    : saved
                    ? 'متاحة دون إنترنت'
                    : 'استماع عبر الإنترنت',
              ),
              trailing: const Icon(Icons.play_circle_outline, color: green),
              onTap: () {
                unawaited(state.play(m, number));
                context.push('/player');
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'المفضلة',
                  icon: Icon(
                    state.favorites.contains(keyName)
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: gold,
                  ),
                  onPressed: () => state.favorite(keyName),
                ),
                if (!saved)
                  IconButton(
                    tooltip: 'تنزيل السورة',
                    icon: Icon(
                      state.activeDownload == keyName ||
                              state.queue.contains(keyName)
                          ? Icons.hourglass_top
                          : Icons.download_outlined,
                    ),
                    onPressed: kIsWeb && !m.webDownloads
                        ? null
                        : () => state.enqueue(m, [number]),
                  ),
                if (saved)
                  IconButton(
                    tooltip: 'حذف التنزيل',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => confirmDelete(context, state, keyName),
                  ),
                const SizedBox(width: 10),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> confirmDelete(BuildContext context, AppState s, String key) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('حذف التنزيل؟'),
      content: const Text('يمكنك تنزيل السورة مجددًا لاحقًا.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('حذف'),
        ),
      ],
    ),
  );
  if (ok == true) {
    try {
      await s.deleteDownload(key);
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حذف الملف، أعد المحاولة')),
        );
    }
  }
}

class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});
  @override
  Widget build(BuildContext context) => Frame(
    title: 'مشغل التلاوة',
    child: Ready(
      builder: (context, c, s) {
        final m = s.current;
        final n = s.surah;
        if (m == null || n == null)
          return EmptyState(
            icon: Icons.headphones,
            text: 'اختر رواية وقارئًا وسورة لتبدأ الاستماع',
            actionText: 'اختيار الرواية',
            action: () => context.go('/riwayat'),
          );
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              height: 190,
              decoration: BoxDecoration(
                color: green,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Center(
                child: Icon(Icons.graphic_eq_rounded, size: 96, color: gold),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'سورة ${c.suwar[n]}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 30,
                color: green,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              m.reciter,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19),
            ),
            Text(
              m.name,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.8, color: Colors.black54),
            ),
            const SizedBox(height: 20),
            if (s.error != null) Notice(s.error!),
            if (s.busy) const LinearProgressIndicator(),
            StreamBuilder<Duration?>(
              stream: s.player.durationStream,
              initialData: s.player.duration,
              builder: (context, dur) => StreamBuilder<Duration>(
                stream: s.player.positionStream,
                initialData: s.player.position,
                builder: (context, pos) {
                  final total = dur.data?.inMilliseconds ?? 0;
                  final at = (pos.data?.inMilliseconds ?? 0).clamp(0, total);
                  return Column(
                    children: [
                      Slider(
                        value: at.toDouble(),
                        min: 0,
                        max: total > 0 ? total.toDouble() : 1,
                        semanticFormatterCallback: (v) =>
                            time(Duration(milliseconds: v.toInt())),
                        onChanged: total == 0 || s.busy
                            ? null
                            : (v) => s.player.seek(
                                Duration(milliseconds: v.toInt()),
                              ),
                        onChangeEnd: (_) => s.savePosition(),
                      ),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(time(Duration(milliseconds: at.toInt()))),
                            Text(time(dur.data ?? Duration.zero)),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                children: [
                  IconButton(
                    tooltip: 'السورة السابقة',
                    onPressed: s.busy || m.surahs.first == n
                        ? null
                        : () => s.next(previous: true),
                    icon: const Icon(Icons.skip_previous),
                  ),
                  IconButton(
                    tooltip: 'تأخير ١٠ ثوانٍ',
                    onPressed: s.busy ? null : () => s.seekBy(-10),
                    icon: const Icon(Icons.replay_10),
                  ),
                  StreamBuilder<bool>(
                    stream: s.player.playingStream,
                    initialData: s.player.playing,
                    builder: (context, snap) => IconButton.filled(
                      iconSize: 42,
                      tooltip: snap.data == true ? 'إيقاف مؤقت' : 'تشغيل',
                      onPressed: s.busy
                          ? null
                          : s.error != null
                          ? () => s.play(m, n)
                          : s.toggle,
                      icon: Icon(
                        snap.data == true
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'تقديم ١٠ ثوانٍ',
                    onPressed: s.busy ? null : () => s.seekBy(10),
                    icon: const Icon(Icons.forward_10),
                  ),
                  IconButton(
                    tooltip: 'السورة التالية',
                    onPressed: s.busy || m.surahs.last == n ? null : s.next,
                    icon: const Icon(Icons.skip_next),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              children: [
                FilterChip(
                  label: const Text('تكرار السورة'),
                  selected: s.repeat,
                  onSelected: (_) => s.setRepeat(),
                ),
                IconButton(
                  tooltip: 'المفضلة',
                  onPressed: () => s.favorite(m.key(n)),
                  icon: Icon(
                    s.favorites.contains(m.key(n))
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: gold,
                  ),
                ),
                if (!s.downloaded.contains(m.key(n)))
                  IconButton(
                    tooltip: 'تنزيل السورة',
                    onPressed: kIsWeb && !m.webDownloads
                        ? null
                        : () => s.enqueue(m, [n]),
                    icon: const Icon(Icons.download_outlined),
                  ),
              ],
            ),
            if (kIsWeb && !m.webDownloads)
              const Notice(
                'التنزيل داخل المتصفح غير متاح لهذا المصدر. تطبيق أندرويد يدعم تنزيل هذه التسجيلات.',
              ),
            if (s.downloaded.contains(m.key(n)))
              const Center(
                child: Text(
                  'محفوظة للاستماع دون إنترنت',
                  style: TextStyle(color: green),
                ),
              ),
          ],
        );
      },
    ),
  );
}

String time(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

class SavedPage extends StatelessWidget {
  final bool downloads;
  const SavedPage({super.key, required this.downloads});
  @override
  Widget build(BuildContext context) => Frame(
    title: downloads ? 'التنزيلات' : 'المفضلة',
    child: Ready(
      builder: (context, c, s) {
        final keys = (downloads ? s.downloaded : s.favorites).toList()..sort();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (downloads && kIsWeb)
              const Notice(
                'على iPhone: أبق التطبيق مفتوحًا أثناء التنزيل. قد يحذف Safari الملفات عند ضغط المساحة أو مسح بيانات المواقع. التخزين الدائم غير مضمون، والتنزيلات غير المكتملة تبدأ من جديد.',
              ),
            if (downloads &&
                (s.downloading ||
                    s.queue.isNotEmpty ||
                    s.downloadError != null))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.downloading
                            ? 'جارٍ تنزيل السورة • ${(s.bytesReceived / 1048576).toStringAsFixed(1)} MB'
                            : 'التنزيل متوقف',
                      ),
                      const SizedBox(height: 12),
                      if (s.downloading)
                        LinearProgressIndicator(value: s.progress),
                      Text('${s.queue.length} في قائمة الانتظار'),
                      if (s.downloadError != null)
                        Text(
                          s.downloadError!,
                          style: const TextStyle(height: 1.8),
                        ),
                      Wrap(
                        children: [
                          TextButton(
                            onPressed: s.downloading
                                ? s.pauseDownload
                                : s.resumeDownloads,
                            child: Text(
                              s.downloading ? 'إيقاف التنزيل' : 'استئناف',
                            ),
                          ),
                          if (!s.downloading)
                            TextButton(
                              onPressed: s.clearQueue,
                              child: const Text('إلغاء القائمة'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (keys.isEmpty)
              EmptyState(
                icon: downloads
                    ? Icons.download_for_offline_outlined
                    : Icons.favorite_border,
                text: downloads
                    ? 'لم تنزّل أي سورة بعد. افتح قائمة السور واضغط زر التنزيل.'
                    : 'أضف التلاوات التي تحب العودة إليها باستخدام رمز القلب.',
              ),
            for (final key in keys) SavedTile(keyName: key, c: c, state: s),
          ],
        );
      },
    ),
  );
}

class SavedTile extends StatelessWidget {
  final String keyName;
  final Catalog c;
  final AppState state;
  const SavedTile({
    super.key,
    required this.keyName,
    required this.c,
    required this.state,
  });
  @override
  Widget build(BuildContext context) {
    final parts = keyName.split('_');
    if (parts.length != 2) return const SizedBox.shrink();
    final id = int.tryParse(parts[0]), number = int.tryParse(parts[1]);
    final m = c.mushafs.where((m) => m.id == id).firstOrNull;
    if (m == null || number == null || !m.surahs.contains(number))
      return const SizedBox.shrink();
    return SurahTile(
      m: m,
      number: number,
      c: c,
      state: state,
      showReciter: true,
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => Frame(
    title: 'الإعدادات والمعلومات',
    child: Ready(
      builder: (context, c, s) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Qiraat Audio',
            style: TextStyle(
              color: green,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text('القراءات العشر • إصدار 0.2.0'),
          const SizedBox(height: 24),
          const Notice(
            'فهرس الروايات والسور مضمّن في التطبيق ويعمل دون اتصال. يظهر فقط المحتوى المصنّف للرواية المختارة؛ لا تُستكمل المصاحف الناقصة بتسجيلات من رواية أخرى.',
          ),
          ListTile(
            leading: const Icon(Icons.verified_outlined),
            title: const Text('آخر جلب للفهرس'),
            subtitle: Text(c.checkedAt),
          ),
          const Divider(),
          const Text(
            'الاستماع دون إنترنت',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const Text(
            'اختر الرواية ثم القارئ، ونزّل سورة أو جميع السور المتاحة. تُشغّل النسخة المحلية تلقائيًا عند وجودها. يمكنك حذفها من التنزيلات.',
            style: TextStyle(height: 1.9),
          ),
          const SizedBox(height: 20),
          Text(
            kIsWeb ? 'Safari وiPhone' : 'أندرويد',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          Text(
            kIsWeb
                ? 'افتح الرابط في Safari ثم مشاركة ← إضافة إلى الشاشة الرئيسية. مساحة التخزين يحددها المتصفح وقد تُحذف الملفات. قد تمنع CORS تنزيل بعض المصادر. الخلفية والتنزيل عند قفل الشاشة غير مضمونين. قد يلزم الضغط على تشغيل بعد الانتقال التلقائي بسبب سياسة التشغيل في Safari.'
                : 'يدعم التطبيق جلسة صوتية وإشعار وسائط. قد تحتاج للسماح بالإشعارات، وقد تؤثر قيود البطارية الخاصة بالجهاز على التشغيل في الخلفية.',
            style: const TextStyle(height: 1.9),
          ),
          const SizedBox(height: 20),
          const Text(
            'المصدر والحقوق',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SelectableText(
            'MP3Quran — https://www.mp3quran.net/ar/api\nن للقرآن وعلومه — https://www.nquran.com/ar/categories/603\nالتسجيلات مستضافة لدى المصدر. لم يُتحقق من ترخيص شامل لإعادة التوزيع أو الاستخدام التجاري؛ لا نرفق الصوت داخل التطبيق ولا ندّعي ملكيته.',
            style: TextStyle(height: 1.9),
          ),
          const SizedBox(height: 20),
          const Text(
            'الخصوصية: لا حسابات ولا إعلانات ولا تحليلات. المفضلة والموضع والتنزيلات محفوظة على جهازك. يتصل التطبيق بخادم الصوت عند الاستماع أو التنزيل.',
            style: TextStyle(height: 1.9),
          ),
        ],
      ),
    ),
  );
}
