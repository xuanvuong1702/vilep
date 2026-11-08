import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../state.dart';
import '../../widgets.dart';

const _popular = <String>['trà sữa', 'nhậu', 'thua kèo', 'quà sinh nhật', 'mượn tiền'];

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<CaseSummary> _results = const [];
  List<String> _recent = const [];
  bool _loading = false;
  String? _error;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _recent = ref.read(prefsProvider).getStringList('recent_searches') ?? const [];
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () => _search(value));
  }

  void _remember(String term) {
    final next = [term, ..._recent.where((e) => e != term)].take(5).toList();
    setState(() => _recent = next);
    ref.read(prefsProvider).setStringList('recent_searches', next);
  }

  Future<void> _search(String term) async {
    final query = term.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiProvider).get('/api/v1/cases', query: {'q': query, 'limit': 30}) as Map<String, dynamic>;
      if (query.length >= 2) _remember(query);
      setState(() => _results = FeedPage.fromJson(data).items);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _searched = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V.surface,
      appBar: AppBar(
        title: const Text('Tìm case'),
        leading: IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back_rounded)),
      ),
      body: PageFrame(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (value) => _search(value),
                decoration: InputDecoration(
                  hintText: 'Tìm "trà sữa", "nhậu", tên bạn bè...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _controller.clear();
                            _search('');
                          },
                        ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const LoadingView(label: 'Đang tìm...')
                  : _error != null
                      ? EmptyState(emoji: '📡', title: 'Lỗi tìm kiếm', body: _error!)
                      : !_searched
                          ? _suggestions()
                          : _results.isEmpty
                              ? const EmptyState(
                                  emoji: '🫥',
                                  title: 'Không tìm thấy case',
                                  body: 'Thử từ khoá khác ngắn hơn, ví dụ "trà sữa".',
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                                      child: Text('${_results.length} kết quả',
                                          style: const TextStyle(fontSize: 12, color: V.muted, fontWeight: FontWeight.w600)),
                                    ),
                                    Expanded(
                                      child: ListView.builder(
                                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                        physics: const BouncingScrollPhysics(),
                                        itemCount: _results.length,
                                        itemBuilder: (context, index) {
                                          final item = _results[index];
                                          return Entrance(
                                            index: index,
                                            child: CaseCard(item: item, onTap: () => context.push('/case/${item.id}')),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestions() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      physics: const BouncingScrollPhysics(),
      children: [
        if (_recent.isNotEmpty) ...[
          Row(
            children: [
              const Text('Tìm gần đây', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  ref.read(prefsProvider).remove('recent_searches');
                  setState(() => _recent = const []);
                },
                child: const Text('Xoá', style: TextStyle(fontSize: 12, color: V.muted, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _recent
                .map((term) => _Suggestion(label: term, icon: Icons.history_rounded, onTap: () => _apply(term)))
                .toList(),
          ),
          const SizedBox(height: 26),
        ],
        const Text('Tìm nhanh', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _popular.map((term) => _Suggestion(label: term, onTap: () => _apply(term))).toList(),
        ),
        const SizedBox(height: 30),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: V.canvas, borderRadius: BorderRadius.circular(V.r16)),
          child: Row(
            children: [
              const Icon(Icons.tips_and_updates_outlined, size: 18, color: V.greenDark),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Mẹo: tìm theo món nợ ("trà sữa", "thua kèo") hoặc tên người đăng để thấy case của bạn bè.',
                  style: TextStyle(fontSize: 11.5, color: V.muted.withValues(alpha: 0.95), height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _apply(String term) {
    _controller.text = term;
    _search(term);
  }
}

class _Suggestion extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const _Suggestion({required this.label, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: V.surface,
          borderRadius: BorderRadius.circular(V.rPill),
          border: Border.all(color: V.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: V.faint),
              const SizedBox(width: 5),
            ],
            Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: V.ink2)),
          ],
        ),
      ),
    );
  }
}
