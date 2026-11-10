import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/services/catalog_request_state.dart';

void main() {
  test(
    'changing a query during pagination permits the next query to paginate',
    () {
      final state = CatalogRequestState();
      state.beginSearch();
      final oldPage = state.beginNextPage()!;
      final query = state.beginSearch();
      expect(state.isLoadingMore, isFalse);
      final currentPage = state.beginNextPage()!;
      state.finishNextPage(oldPage);
      expect(state.isLoadingMore, isTrue);
      expect(state.isCurrent(oldPage), isFalse);
      expect(state.isCurrent(query), isTrue);
      state.finishNextPage(currentPage);
      expect(state.isLoadingMore, isFalse);
    },
  );

  test('a query has at most one pagination request in flight', () {
    final state = CatalogRequestState()..beginSearch();
    expect(state.beginNextPage(), isNotNull);
    expect(state.beginNextPage(), isNull);
  });
}
