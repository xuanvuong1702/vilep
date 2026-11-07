import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../state.dart';
import '../../widgets.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<CaseSummary> _results = const [];
  bool _loading = false;
  String? _error;
  bool _searched = false;

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
      setState(() => _results = FeedPage.fromJson(data).items);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() {
        _loading = false;
        _searched = true;
      });
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
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
                        ? const EmptyState(
                            emoji: '🔎',
                            title: 'Tìm khoản nợ vui',
                            body: 'Thử "trà sữa", "nhậu", "thua kèo" hoặc tên người đăng.',
                          )
                        : _results.isEmpty
                            ? const EmptyState(
                                emoji: '🫥',
                                title: 'Không tìm thấy case',
                                body: 'Thử từ khoá khác ngắn hơn, ví dụ "trà sữa".',
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                itemCount: _results.length,
                                itemBuilder: (context, index) {
                                  final item = _results[index];
                                  return CaseCard(item: item, onTap: () => context.push('/case/${item.id}'));
                                },
                              ),
          ),
        ],
      ),
    );
  }
}
