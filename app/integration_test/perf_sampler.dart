// Host-side CPU sampler for integration_test/perf_test.dart.
//
// Connects to the app's VM service, listens for the test's `hiwiski.perf` events and
// breaks the CPU samples of each signalled window down by function: where the time
// goes, and which of the app's functions (lib/) it was spent under.
//
// dart run integration_test/perf_sampler.dart ws://127.0.0.1:<port>/<token>/ws build/perf/cpu.json
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  final service = await vmServiceConnectUri(args[0]);
  final out = File(args[1]);
  final results = <String, Object?>{};
  await service.streamListen(EventStreams.kExtension);
  stdout.writeln('sampler connected');
  await for (final event in service.onExtensionEvent) {
    if (event.extensionKind != 'hiwiski.perf') continue;
    final data = event.extensionData!.data;
    final name = data['name'] as String;
    final start = data['start'] as int;
    final end = data['end'] as int;
    final cpu = await service.getCpuSamples(
      event.isolate!.id!,
      start,
      end - start,
    );
    final breakdown = _breakdown(cpu);
    results[name] = breakdown;
    // The raw stacks too, to break them down differently afterwards.
    File('${out.path}.$name.raw.json').writeAsStringSync(
      jsonEncode({
        'functions': [
          for (final f in cpu.functions ?? const <ProfileFunction>[])
            {'name': _name(f), 'url': f.resolvedUrl ?? ''},
        ],
        'stacks': [
          for (final sample in cpu.samples ?? const <CpuSample>[]) sample.stack,
        ],
      }),
    );
    out.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
    stdout.writeln('CPU $name ${breakdown['samples']} samples');
  }
}

Map<String, Object?> _breakdown(CpuSamples cpu) {
  final functions = cpu.functions ?? const <ProfileFunction>[];
  String name(int i) {
    final function = functions[i].function;
    if (function is FuncRef) {
      final owner = function.owner;
      final prefix = switch (owner) {
        ClassRef(:final name) => '$name.',
        FuncRef(:final name) => '$name.',
        _ => '',
      };
      return '$prefix${function.name}';
    }
    if (function is NativeFunction) return 'native ${function.name}';
    return '$function';
  }

  String url(int i) => functions[i].resolvedUrl ?? '';
  bool ours(int i) =>
      url(i).contains('package:hiwiski/') || url(i).contains('/app/lib/');

  final self = <String, int>{};
  final selfLib = <String, int>{};
  final inclusive = <String, int>{};
  final samples = cpu.samples ?? const <CpuSample>[];
  for (final sample in samples) {
    final stack = sample.stack ?? const <int>[];
    if (stack.isEmpty) continue;
    self.update(name(stack.first), (v) => v + 1, ifAbsent: () => 1);
    final library = url(stack.first).split('/').take(2).join('/');
    selfLib.update(library, (v) => v + 1, ifAbsent: () => 1);
    final seen = <String>{};
    for (final i in stack) {
      if (!ours(i)) continue;
      final n = '${name(i)}  (${url(i).split('/').last})';
      if (seen.add(n)) inclusive.update(n, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  List<String> top(Map<String, int> counts, int k) => [
    for (final e
        in (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .take(k))
      '${e.value}  ${e.key}',
  ];
  return {
    'samples': samples.length,
    'period_us': cpu.samplePeriod,
    'self_top': top(self, 15),
    'self_by_library': top(selfLib, 8),
    'app_inclusive_top': top(inclusive, 20),
  };
}

String _name(ProfileFunction profileFunction) {
  final function = profileFunction.function;
  if (function is FuncRef) {
    final owner = function.owner;
    final prefix = switch (owner) {
      ClassRef(:final name) => '$name.',
      FuncRef(:final name) => '$name.',
      _ => '',
    };
    return '$prefix${function.name}';
  }
  if (function is NativeFunction) return 'native ${function.name}';
  return '$function';
}
