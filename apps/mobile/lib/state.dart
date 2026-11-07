import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api.dart';
import 'core/models.dart';

/// Demo build flags (flutter build web --dart-define=DEMO_PHONE=0900000001 --dart-define=SKIP_ONBOARDING=true)
/// used for screenshots and product demos; they never ship in a store build.
const String kDemoPhone = String.fromEnvironment('DEMO_PHONE');
const bool kSkipOnboarding = bool.fromEnvironment('SKIP_ONBOARDING');

final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('prefs not provided'));

final apiProvider = Provider<ApiClient>((ref) {
  final api = ApiClient();
  final prefs = ref.watch(prefsProvider);
  api.token = prefs.getString('access_token');
  return api;
});

class AuthState {
  final UserProfile? user;
  final bool booting;
  final bool sendingOtp;
  final bool verifying;

  const AuthState({this.user, this.booting = false, this.sendingOtp = false, this.verifying = false});

  bool get isLoggedIn => user != null;

  AuthState copyWith({
    UserProfile? user,
    bool? booting,
    bool? sendingOtp,
    bool? verifying,
    bool clearUser = false,
  }) =>
      AuthState(
        user: clearUser ? null : (user ?? this.user),
        booting: booting ?? this.booting,
        sendingOtp: sendingOtp ?? this.sendingOtp,
        verifying: verifying ?? this.verifying,
      );
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final prefs = ref.watch(prefsProvider);
    final api = ref.watch(apiProvider);
    final token = prefs.getString('access_token');
    api.token = token;
    if (token != null && token.isNotEmpty) {
      Future.microtask(refreshMe);
      return const AuthState(booting: true);
    }
    if (kDemoPhone.isNotEmpty) {
      Future.microtask(() => _demoLogin(kDemoPhone));
      return const AuthState(booting: true);
    }
    return const AuthState();
  }

  Future<void> _demoLogin(String phone) async {
    try {
      final code = await requestOtp(phone);
      if (code != null) await verifyOtp(phone, code);
    } catch (_) {
      state = const AuthState();
    }
  }

  Future<void> refreshMe() async {
    final api = ref.read(apiProvider);
    try {
      final data = await api.get('/api/v1/me') as Map<String, dynamic>;
      final user = UserProfile.fromJson(data['user'] as Map<String, dynamic>);
      state = AuthState(user: user);
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await signOut();
      } else {
        state = const AuthState();
      }
    } catch (_) {
      state = const AuthState();
    }
  }

  Future<String?> requestOtp(String phone) async {
    state = state.copyWith(sendingOtp: true);
    try {
      final data = await ref.read(apiProvider).post('/api/v1/auth/otp/request', body: {'phone': phone})
          as Map<String, dynamic>;
      return data['devCode']?.toString();
    } finally {
      state = state.copyWith(sendingOtp: false);
    }
  }

  Future<void> verifyOtp(String phone, String code) async {
    state = state.copyWith(verifying: true);
    try {
      final data = await ref.read(apiProvider).post('/api/v1/auth/otp/verify', body: {'phone': phone, 'code': code})
          as Map<String, dynamic>;
      final token = data['accessToken'] as String;
      final refresh = data['refreshToken'] as String;
      final prefs = ref.read(prefsProvider);
      await prefs.setString('access_token', token);
      await prefs.setString('refresh_token', refresh);
      ref.read(apiProvider).token = token;
      final user = UserProfile.fromJson(data['user'] as Map<String, dynamic>);
      state = AuthState(user: user);
    } finally {
      state = state.copyWith(verifying: false);
    }
  }

  Future<void> signOut() async {
    final prefs = ref.read(prefsProvider);
    final refresh = prefs.getString('refresh_token');
    final api = ref.read(apiProvider);
    if (refresh != null) {
      try {
        await api.post('/api/v1/auth/logout', body: {'refreshToken': refresh});
      } catch (_) {
        // ignore network errors on logout
      }
    }
    api.token = null;
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    state = const AuthState();
  }

  Future<void> updateProfile({String? nickname, String? bio, String? avatarKey}) async {
    final api = ref.read(apiProvider);
    final data = await api.put('/api/v1/me', body: {
      if (nickname != null) 'nickname': nickname,
      if (bio != null) 'bio': bio,
      if (avatarKey != null) 'avatarKey': avatarKey,
    }) as Map<String, dynamic>;
    state = state.copyWith(user: UserProfile.fromJson(data));
  }

  Future<void> submitKyc({required int tier, required String fullName, required String idNumber, String? dob}) async {
    final api = ref.read(apiProvider);
    await api.post('/api/v1/me/kyc', body: {
      'tier': tier,
      'fullName': fullName,
      'idNumber': idNumber,
      if (dob != null) 'dob': dob,
    });
    await refreshMe();
  }

  void setUser(UserProfile user) => state = AuthState(user: user);
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

class FeedState {
  final String tab;
  final String category;
  final List<CaseSummary> items;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final String? cursor;

  const FeedState({
    this.tab = 'need',
    this.category = 'all',
    this.items = const [],
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.cursor,
  });

  FeedState copyWith({
    String? tab,
    String? category,
    List<CaseSummary>? items,
    bool? loading,
    bool? loadingMore,
    String? error,
    String? cursor,
    bool clearError = false,
  }) =>
      FeedState(
        tab: tab ?? this.tab,
        category: category ?? this.category,
        items: items ?? this.items,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
        cursor: cursor ?? this.cursor,
      );
}

class FeedController extends Notifier<FeedState> {
  @override
  FeedState build() {
    Future.microtask(() => load(reset: true));
    return const FeedState(loading: true);
  }

  Future<void> setTab(String tab) async {
    if (state.tab == tab) return;
    state = state.copyWith(tab: tab, items: const [], loading: true, clearError: true, cursor: null);
    await load(reset: true);
  }

  Future<void> setCategory(String category) async {
    if (state.category == category) return;
    state = state.copyWith(category: category, items: const [], loading: true, clearError: true, cursor: null);
    await load(reset: true);
  }

  Future<void> load({bool reset = false}) async {
    final api = ref.read(apiProvider);
    if (reset) state = state.copyWith(loading: true, clearError: true);
    try {
      final data = await api.get('/api/v1/cases', query: {
        'tab': state.tab,
        'category': state.category,
        'limit': 20,
      }) as Map<String, dynamic>;
      final page = FeedPage.fromJson(data);
      state = state.copyWith(items: page.items, loading: false, cursor: page.nextCursor);
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || state.cursor == null || state.loading) return;
    state = state.copyWith(loadingMore: true);
    try {
      final data = await ref.read(apiProvider).get('/api/v1/cases', query: {
        'tab': state.tab,
        'category': state.category,
        'limit': 20,
        'cursor': state.cursor,
      }) as Map<String, dynamic>;
      final page = FeedPage.fromJson(data);
      state = state.copyWith(items: [...state.items, ...page.items], loadingMore: false, cursor: page.nextCursor);
    } on ApiException {
      state = state.copyWith(loadingMore: false);
    }
  }
}

final feedProvider = NotifierProvider<FeedController, FeedState>(FeedController.new);

final caseDetailProvider = FutureProvider.autoDispose.family<CaseDetail, String>((ref, id) async {
  final data = await ref.watch(apiProvider).get('/api/v1/cases/$id') as Map<String, dynamic>;
  return CaseDetail.fromJson(data);
});

final myCasesProvider = FutureProvider.autoDispose<List<CaseSummary>>((ref) async {
  final data = await ref.watch(apiProvider).get('/api/v1/my/cases') as Map<String, dynamic>;
  return ((data['items'] as List?) ?? const [])
      .map((e) => CaseSummary.fromJson(e as Map<String, dynamic>))
      .toList();
});

class NotificationsState {
  final List<NotificationItem> items;
  final int unread;

  const NotificationsState({required this.items, required this.unread});
}

final notificationsProvider = FutureProvider.autoDispose<NotificationsState>((ref) async {
  final data = await ref.watch(apiProvider).get('/api/v1/me/notifications') as Map<String, dynamic>;
  return NotificationsState(
    unread: (data['unreadCount'] as num?)?.toInt() ?? 0,
    items: ((data['items'] as List?) ?? const [])
        .map((e) => NotificationItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
});

final metaProvider = FutureProvider<MetaConfig>((ref) async {
  final api = ref.watch(apiProvider);
  final config = await api.get('/api/v1/meta/config') as Map<String, dynamic>;
  final templates = await api.get('/api/v1/meta/templates') as Map<String, dynamic>;
  final list = ((templates['items'] as List?) ?? const [])
      .map((e) => DebtTemplate.fromJson(e as Map<String, dynamic>))
      .toList();
  return MetaConfig.fromJson(config, list);
});

final creditorInviteProvider = FutureProvider.autoDispose.family<CreditorInvite, String>((ref, token) async {
  final data = await ref.watch(apiProvider).get('/api/v1/creditor/invite/$token') as Map<String, dynamic>;
  return CreditorInvite.fromJson(data);
});

final myContributionsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await ref.watch(apiProvider).get('/api/v1/me/contributions') as Map<String, dynamic>;
  return ((data['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
});

final myStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return await ref.watch(apiProvider).get('/api/v1/me/stats') as Map<String, dynamic>;
});

String randomIdempotencyKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
