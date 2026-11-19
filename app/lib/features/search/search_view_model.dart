import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/repositories.dart';
import '../../app/stores.dart';
import '../../core/api/hiwiski_failure.dart';
import '../../core/common/wire.dart';
import '../../domain/search/search_models.dart';
import '../../domain/tags/tag.dart';

part 'search_view_model.g.dart';

/// The types of the filter bar: events, tasks, wiki, recipes.
///
/// "Tasks" covers the lists too — a chip of their own would only lengthen the bar.
enum SearchType {
  events({EntityTypes.event}),
  todos({EntityTypes.todo, EntityTypes.todoList}),
  wiki({EntityTypes.wikiPage}),
  recipes({EntityTypes.wikiPage});

  const SearchType(this.serverTypes);

  final Set<String> serverTypes;

  /// "Recipes" and "Wiki" are only told apart by the page kind.
  static SearchType of(SearchHitView hit, bool recipe) =>
      switch (hit.itemType) {
        EntityTypes.event => SearchType.events,
        EntityTypes.todo || EntityTypes.todoList => SearchType.todos,
        _ => recipe ? SearchType.recipes : SearchType.wiki,
      };
}

/// The search: online via the server, offline via the device.
@immutable
class SearchState {
  const SearchState({
    required this.term,
    required this.outcome,
    required this.hits,
    required this.recipes,
    required this.failure,
    required this.busy,
    required this.types,
    required this.includeArchived,
    required this.tags,
    required this.tagFilter,
  });

  /// The term the hits are for — what to highlight.
  final String term;

  /// `null` before the first search, and after a failed one.
  final SearchOutcome? outcome;

  /// The hits through the type and tag filter.
  final List<SearchHitView> hits;

  /// The ids of the hits that are recipes.
  final Set<String> recipes;

  /// What went wrong with the last search — shown in place of the hits.
  final HiwiskiFailure? failure;
  final bool busy;

  /// All selected means: do not filter.
  final Set<SearchType> types;

  /// Also the archive. Off by default and not remembered: whoever searches next
  /// time searches what is current.
  final bool includeArchived;

  final List<Tag> tags;
  final Set<String> tagFilter;

  /// Nothing found — offline that means "not found here", not "does not exist".
  bool get nothing =>
      hits.isEmpty && outcome != null && outcome?.jumpTo == null;
}

@riverpod
Stream<List<Tag>> _tags(Ref ref) =>
    ref.watch(tagRepositoryProvider).watchTags();

@riverpod
class SearchViewModel extends _$SearchViewModel {
  /// Which page holds the filter.
  static const _page = 'search';

  static const _area = TagFilterAreas.search;

  String _term = '';
  SearchOutcome? _outcome;
  Map<String, ({String tags, bool recipe})> _facts = const {};
  HiwiskiFailure? _failure;
  bool _busy = false;
  final _types = <SearchType>{...SearchType.values};
  bool _includeArchived = false;

  /// Counts the runs: only the newest one may show its answer. Without it, whichever
  /// request came back last won — "kin" hits under "kinder" — and the first to finish
  /// switched the loading strip off while the other still ran.
  int _generation = 0;

  /// The last text searched for, trimmed — what a changed filter searches again.
  String _query = '';

  @override
  Future<SearchState> build() async {
    ref.watch(tagFilterHoldProvider(_area, _page));
    final filter = ref.watch(
      tagFiltersProvider.select((f) => f[_area] ?? const <String>{}),
    );
    final tagUses = ref.watch(preferencesProvider.select((p) => p.tagUses));
    final tags = await ref.watch(_tagsProvider.future);
    final outcome = _outcome;
    return SearchState(
      term: _term,
      outcome: outcome,
      hits: [
        for (final hit in outcome?.hits ?? const <SearchHitView>[])
          if (_types.contains(
                SearchType.of(hit, _facts[hit.itemId]?.recipe ?? false),
              ) &&
              passesTagFilter(filter, _facts[hit.itemId]?.tags ?? ''))
            hit,
      ],
      recipes: {
        for (final MapEntry(:key, :value) in _facts.entries)
          if (value.recipe) key,
      },
      failure: _failure,
      busy: _busy,
      types: {..._types},
      includeArchived: _includeArchived,
      tags: rankTags(tags, tagUses),
      tagFilter: filter,
    );
  }

  void _changed() => ref.invalidateSelf();

  /// Searches for [value] — the archive left out unless asked for.
  Future<void> search(String value) async {
    final generation = ++_generation;
    final term = value.trim();
    _query = term;
    if (term.isEmpty) {
      _outcome = null;
      _term = '';
      _busy = false;
      _failure = null;
      _changed();
      return;
    }
    _busy = true;
    _changed();
    final repository = ref.read(searchRepositoryProvider);
    try {
      final serverTypes = _types.length == SearchType.values.length
          ? <String>{}
          : {for (final type in _types) ...type.serverTypes};
      final outcome = await repository.search(
        term,
        types: serverTypes,
        includeArchived: _includeArchived,
      );
      if (generation != _generation) return;
      final facts = await repository.facts([...outcome.hits, ?outcome.jumpTo]);
      if (!ref.mounted || generation != _generation) return;
      _outcome = outcome;
      _facts = facts;
      _term = term;
      _failure = null;
    } on HiwiskiFailure catch (failure) {
      if (!ref.mounted || generation != _generation) return;
      _outcome = null;
      _failure = failure;
    } finally {
      if (ref.mounted && generation == _generation) {
        _busy = false;
        _changed();
      }
    }
  }

  /// The same search once more — after it failed.
  Future<void> retry() => search(_query);

  void toggleType(SearchType type) {
    if (!_types.remove(type)) _types.add(type);
    // The search keeps its failure in its own state.
    search(_query).ignore();
  }

  void toggleArchived() {
    _includeArchived = !_includeArchived;
    // The search keeps its failure in its own state.
    search(_query).ignore();
  }

  void toggleTag(String id) =>
      ref.read(tagFilterStoreProvider).toggle(_area, id);

  void clearTags() => ref.read(tagFilterStoreProvider).clear(_area);
}
