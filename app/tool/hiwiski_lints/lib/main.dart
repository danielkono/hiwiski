import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/async_state.dart';
import 'src/clock_now.dart';
import 'src/layer_boundaries.dart';
import 'src/no_magic_dimensions.dart';
import 'src/no_string_literals.dart';
import 'src/scaffold_in_frames.dart';
import 'src/synced_writes.dart';
import 'src/view_model_commands.dart';
import 'src/view_model_names.dart';

/// The entry point the analysis server looks for: a top-level `plugin`.
final plugin = HiwiskiLintsPlugin();

class HiwiskiLintsPlugin extends Plugin {
  @override
  String get name => 'hiwiski_lints';

  @override
  void register(PluginRegistry registry) {
    registry.registerLintRule(NoStringLiterals());
    registry.registerLintRule(NoMagicDimensions());
    registry.registerLintRule(LayerBoundaries());
    registry.registerLintRule(ScaffoldInFrames());
    registry.registerLintRule(ViewModelNames());
    registry.registerLintRule(AsyncState());
    registry.registerLintRule(ViewModelCommands());
    registry.registerLintRule(SyncedWrites());
    registry.registerLintRule(ClockNow());
  }
}
