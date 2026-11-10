/// Each search owns its loading flags. Stale responses cannot keep a new
/// search stuck in the loading-more state or clear its current request.
class CatalogRequestState {
  int generation = 0;
  bool isLoadingMore = false;

  int beginSearch() {
    isLoadingMore = false;
    return ++generation;
  }

  int? beginNextPage() {
    if (isLoadingMore) return null;
    isLoadingMore = true;
    return generation;
  }

  bool isCurrent(int request) => generation == request;

  void finishNextPage(int request) {
    if (isCurrent(request)) isLoadingMore = false;
  }
}
