import 'package:ansible_node/services/error_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingReporter extends ErrorReporter {
  final List<({Object error, bool fatal, String? context})> events = [];

  @override
  void report(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? context,
  }) {
    events.add((error: error, fatal: fatal, context: context));
  }
}

void main() {
  group('ErrorReporter seam', () {
    final original = ErrorReporter.instance;

    tearDown(() {
      ErrorReporter.instance = original;
    });

    test('defaults to a no-op logging reporter', () {
      expect(ErrorReporter.instance, isA<LoggingErrorReporter>());
    });

    test('LoggingErrorReporter.report does not throw', () {
      const LoggingErrorReporter().report(
        StateError('boom'),
        StackTrace.current,
        fatal: true,
        context: 'test',
      );
    });

    test('instance is replaceable and receives reported errors', () {
      final recorder = _RecordingReporter();
      ErrorReporter.instance = recorder;

      ErrorReporter.instance.report(
        ArgumentError('bad'),
        null,
        fatal: true,
        context: 'startup',
      );

      expect(recorder.events, hasLength(1));
      expect(recorder.events.single.fatal, isTrue);
      expect(recorder.events.single.context, 'startup');
      expect(recorder.events.single.error, isA<ArgumentError>());
    });
  });
}
