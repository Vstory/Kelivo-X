import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/workspace/workspace_tool_metadata.dart';
import 'package:Kelivo/features/chat/widgets/workspace_tool_detail.dart';
import 'package:Kelivo/features/chat/widgets/workspace_tool_ui.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

WorkspaceToolPart _shellPart({
  required String command,
  required String stdout,
}) {
  return WorkspaceToolPart(
    id: 'tc-shell',
    toolName: 'shell',
    arguments: {'command': command},
    content: stdout,
    metadata: WorkspaceToolMetadata(
      tool: 'shell',
      status: 'ok',
      command: command,
      stdoutPreview: stdout,
      exitCode: 0,
    ).toJson(),
  );
}

Widget _harness({required Widget child}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SizedBox(height: 640, width: 390, child: child)),
  );
}

class _ClipboardCapture {
  String? value;
}

/// Records whatever the widget under test writes to the system clipboard.
_ClipboardCapture _captureClipboard(WidgetTester tester) {
  final capture = _ClipboardCapture();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        capture.value =
            (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
  return capture;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('long shell output lives in a single scrollable', (tester) async {
    final stdout = List<String>.generate(
      200,
      (index) => 'output-line-$index',
    ).join('\n');

    await tester.pumpWidget(
      _harness(
        child: WorkspaceToolDetailBody(
          part: _shellPart(command: 'yes | head', stdout: stdout),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Scrollable), findsOneWidget);
    expect(find.text('Command'), findsOneWidget);
    expect(find.text('Output'), findsOneWidget);
    expect(find.textContaining('output-line-0'), findsOneWidget);
  });

  testWidgets('section copy icons copy command and output', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
          return null;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    const command = 'echo hello';
    const stdout = 'hello\nworld';

    await tester.pumpWidget(
      _harness(
        child: WorkspaceToolDetailBody(
          part: _shellPart(command: command, stdout: stdout),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Lucide.Copy), findsNWidgets(2));

    await tester.tap(find.byTooltip('Copy command'));
    await tester.pump();
    expect(copied, command);

    await tester.tap(find.byTooltip('Copy output'));
    await tester.pump();
    expect(copied, stdout);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('carriage-return progress collapses to its newest frame', (
    tester,
  ) async {
    const stdout =
        'Updating files:  55% (1461/2634)\r'
        'Updating files: 100% (2634/2634), done.';

    await tester.pumpWidget(
      _harness(
        child: WorkspaceToolDetailBody(
          part: _shellPart(command: 'git checkout main', stdout: stdout),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('\r'), findsNothing);
    expect(
      find.text('Updating files: 100% (2634/2634), done.'),
      findsOneWidget,
    );
    expect(find.textContaining('55%'), findsNothing);
  });

  testWidgets('section copy of output replays carriage returns', (
    tester,
  ) async {
    final copied = _captureClipboard(tester);

    await tester.pumpWidget(
      _harness(
        child: WorkspaceToolDetailBody(
          part: _shellPart(command: 'curl -O', stdout: '10%\r20%\r30%'),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Copy output'));
    await tester.pump();

    // The section button copies the output alone, replayed so that only the
    // newest progress frame survives.
    expect(copied.value, '30%');
    expect(copied.value, isNot(contains('\r')));
    expect(copied.value, isNot(contains('10%')));

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('header copy replays carriage returns across the whole card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final copied = _captureClipboard(tester);
    final part = _shellPart(command: 'curl -O', stdout: '10%\r20%\r30%');

    await tester.pumpWidget(
      _harness(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showWorkspaceToolDetail(context, part),
            child: const Text('open-detail'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-detail'));
    await tester.pumpAndSettle();

    expect(find.byKey(kWorkspaceToolDetailDesktopKey), findsOneWidget);

    await tester.tap(find.byTooltip('Copy'));
    await tester.pump();

    // The header button copies command plus output, so the command line stays
    // and only the replayed output follows it.
    expect(copied.value, 'curl -O\n30%');

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
