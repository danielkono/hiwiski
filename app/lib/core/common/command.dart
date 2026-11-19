/// Marks a ViewModel method that changes something and answers with what the view
/// needs next: the id of what it created, the result to show, whether it fit.
///
/// A ViewModel answers through its state (`view_model_commands`); a method that
/// only reads belongs into the state. A command may return its result: the view
/// runs it through a Riverpod `Mutation` declared next to it in the ViewModel's
/// file, watches the mutation for "running" and its error, and reacts to its
/// success with `ref.listen` — instead of awaiting it with flags of its own.
const command = Command._();

/// See [command].
final class Command {
  const Command._();
}
