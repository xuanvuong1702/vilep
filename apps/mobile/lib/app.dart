import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'features/auth/login_page.dart';
import 'features/case/case_detail_page.dart';
import 'features/cases/my_cases_page.dart';
import 'features/certificate/certificate_page.dart';
import 'features/create/create_case_page.dart';
import 'features/creditor/creditor_page.dart';
import 'features/feed/feed_page.dart';
import 'features/feed/search_page.dart';
import 'features/notifications/notifications_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/profile/bank_accounts_page.dart';
import 'features/profile/kyc_page.dart';
import 'features/profile/profile_page.dart';
import 'features/shell/app_shell.dart';
import 'state.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final prefs = ref.watch(prefsProvider);
  final refresh = ValueNotifier<int>(0);
  ref.listen(authProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  final seenOnboarding = prefs.getBool('seen_onboarding') ?? false;

  return GoRouter(
    initialLocation: (seenOnboarding || kSkipOnboarding) ? '/discover' : '/onboarding',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final requiresAuth = state.uri.path.startsWith('/my') ||
          state.uri.path.startsWith('/notifications') ||
          state.uri.path.startsWith('/me') ||
          state.uri.path.startsWith('/create') ||
          state.uri.path.startsWith('/certificate');
      if (requiresAuth && !auth.isLoggedIn && !auth.booting) {
        return '/login?next=${Uri.encodeComponent(state.uri.toString())}';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingPage()),
      GoRoute(path: '/login', builder: (context, state) => LoginPage(next: state.uri.queryParameters['next'])),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/discover', builder: (context, state) => const FeedPage()),
          GoRoute(path: '/my', builder: (context, state) => const MyCasesPage()),
          GoRoute(path: '/notifications', builder: (context, state) => const NotificationsPage()),
          GoRoute(path: '/me', builder: (context, state) => const ProfilePage()),
        ],
      ),
      GoRoute(path: '/search', builder: (context, state) => const SearchPage()),
      GoRoute(path: '/case/:id', builder: (context, state) => CaseDetailPage(caseId: state.pathParameters['id']!)),
      GoRoute(path: '/create', builder: (context, state) => const CreateCasePage()),
      GoRoute(path: '/creditor/:token', builder: (context, state) => CreditorPage(token: state.pathParameters['token']!)),
      GoRoute(path: '/certificate/:id', builder: (context, state) => CertificatePage(caseId: state.pathParameters['id']!)),
      GoRoute(path: '/kyc', builder: (context, state) => const KycPage()),
      GoRoute(path: '/banks', builder: (context, state) => const BankAccountsPage()),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🧭', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              Text(state.error?.toString() ?? 'Không tìm thấy trang',
                  textAlign: TextAlign.center, style: const TextStyle(color: V.muted)),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => context.go('/discover'), child: const Text('Về trang chủ')),
            ],
          ),
        ),
      ),
    ),
  );
});

class VilepApp extends ConsumerWidget {
  const VilepApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Ví Lép',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: router,
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
