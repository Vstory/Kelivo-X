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

  testWidgets('copied output replays carriage returns', (tester) async {
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
    expect(copied, 'curl -O\n30%');

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
