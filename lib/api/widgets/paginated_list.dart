import 'package:flutter/material.dart';

import '../tatami_exception.dart';
import 'api_error_view.dart';

/// Sinal genérico de "uma página com cursor opaco do Tatami".
///
/// Implemente este contrato em qualquer Page DTO (`StudentsPage`,
/// `OrdersPage`, `NotificationsPage`...) para que o widget abaixo possa
/// renderizar paginação infinita sem conhecer o tipo do item.
abstract class PageLike<T> {
  List<T> get items;
  String? get nextCursor;
  bool get hasMore;
}

/// Adapter para passar Page DTOs do API que não estendem [PageLike] sem
/// precisarmos refatorar todos eles. Cria um wrapper inline.
class PageView<T> implements PageLike<T> {
  const PageView({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  @override
  final List<T> items;
  @override
  final String? nextCursor;
  @override
  final bool hasMore;
}

typedef PageFetcher<T> = Future<PageView<T>> Function(String? cursor);
typedef ItemBuilder<T> = Widget Function(BuildContext context, T item, int index);

/// Lista paginada por cursor. Carrega a primeira página no init; quando o
/// scroll chega perto do fim, dispara a próxima. Mostra:
///   - Loading inicial (CircularProgressIndicator central)
///   - Erro inicial → ApiErrorView com onRetry
///   - Lista vazia → emptyBuilder (se passado) ou texto padrão
///   - Erro no meio do scroll → linha inline com Tentar de novo
///
/// Uso típico:
/// ```dart
/// PaginatedList<ApiStudent>(
///   fetcher: (cursor) async {
///     final page = await ref.read(studentRepoProvider).list(
///       academyId,
///       filter: StudentFilter(limit: 50, cursor: cursor),
///     );
///     return PageView(
///       items: page.items,
///       nextCursor: page.nextCursor,
///       hasMore: page.hasMore,
///     );
///   },
///   itemBuilder: (ctx, s, i) => StudentTile(s),
/// );
/// ```
class PaginatedList<T> extends StatefulWidget {
  const PaginatedList({
    super.key,
    required this.fetcher,
    required this.itemBuilder,
    this.emptyBuilder,
    this.separatorBuilder,
    this.padding,
    this.scrollController,
    this.prefetchThreshold = 300,
  });

  final PageFetcher<T> fetcher;
  final ItemBuilder<T> itemBuilder;
  final WidgetBuilder? emptyBuilder;
  final IndexedWidgetBuilder? separatorBuilder;
  final EdgeInsetsGeometry? padding;
  final ScrollController? scrollController;

  /// Pixels antes do fim da lista para começar a buscar a próxima página.
  final double prefetchThreshold;

  @override
  State<PaginatedList<T>> createState() => PaginatedListState<T>();
}

class PaginatedListState<T> extends State<PaginatedList<T>> {
  final List<T> _items = [];
  String? _nextCursor;
  bool _hasMore = true;
  bool _loadingFirst = true;
  bool _loadingMore = false;
  Object? _firstError;
  Object? _moreError;

  ScrollController? _ownController;
  ScrollController get _controller =>
      widget.scrollController ?? (_ownController ??= ScrollController());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _loadFirst();
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _ownController?.dispose();
    super.dispose();
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loadingFirst = true;
      _firstError = null;
      _items.clear();
      _nextCursor = null;
      _hasMore = true;
    });
    try {
      final page = await widget.fetcher(null);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loadingFirst = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _firstError = e;
        _loadingFirst = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await widget.fetcher(_nextCursor);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _moreError = e;
        _loadingMore = false;
      });
    }
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    if (pos.maxScrollExtent - pos.pixels < widget.prefetchThreshold) {
      _loadMore();
    }
  }

  /// Permite que o caller force um refresh — útil em pull-to-refresh ou
  /// ao mudar filtro.
  Future<void> reload() => _loadFirst();

  @override
  Widget build(BuildContext context) {
    if (_loadingFirst) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_firstError != null) {
      return ApiErrorView(error: _firstError!, onRetry: _loadFirst);
    }
    if (_items.isEmpty) {
      return widget.emptyBuilder?.call(context) ??
          const Center(child: Text('Nada por aqui ainda.'));
    }

    // +1 slot para footer (loading more / retry / sentinela "end").
    final showFooter = _hasMore || _moreError != null;
    final itemCount = _items.length + (showFooter ? 1 : 0);

    final list = ListView.separated(
      controller: _controller,
      padding: widget.padding,
      itemCount: itemCount,
      separatorBuilder: (ctx, i) =>
          widget.separatorBuilder?.call(ctx, i) ?? const SizedBox.shrink(),
      itemBuilder: (ctx, i) {
        if (i >= _items.length) return _footer();
        return widget.itemBuilder(ctx, _items[i], i);
      },
    );

    return RefreshIndicator(
      onRefresh: _loadFirst,
      child: list,
    );
  }

  Widget _footer() {
    if (_moreError != null) {
      return ApiErrorView(
        error: _moreError!,
        onRetry: _loadMore,
        compact: true,
      );
    }
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    // Sentinela invisível mas com altura mínima — ajuda a triggar o
    // _loadMore() em listas pequenas que cabem na viewport.
    return const SizedBox(height: 64);
  }
}

/// Forçar refresh externamente. Use `GlobalKey<PaginatedListState<T>>()`
/// como key e chame `.currentState?.reload()`.
typedef PaginatedListKey<T> = GlobalKey<PaginatedListState<T>>;

/// Helper para a forma `TatamiException` quando o caller quiser saber.
TatamiException? errorAsTatami(Object e) {
  if (e is TatamiException) return e;
  return null;
}
