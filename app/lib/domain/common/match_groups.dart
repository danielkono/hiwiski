/// The groups of a regular expression's match that always take part.
///
/// `Match.group` is nullable because a group may stay out of a match (`(a)?`). A
/// group that is not optional in its pattern is always there once the pattern
/// matched — [groupOf] says so instead of a `!`, and names the group if the pattern
/// and the code ever drift apart.
extension MatchGroups on Match {
  String groupOf(int index) =>
      group(index) ??
      (throw StateError('group $index of "$pattern" did not take part'));
}
