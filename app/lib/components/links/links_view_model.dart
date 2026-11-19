import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/link_index.dart';
import '../../domain/links/link_index.dart';

part 'links_view_model.g.dart';

/// The link index the link widgets resolve against: what a reference in a text points
/// to, what an item links to and what links to it. On the device, so offline too.
@riverpod
class LinksViewModel extends _$LinksViewModel {
  @override
  LinkIndex build() => ref.watch(linkIndexProvider);
}
