import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/utils/terminal_text.dart';

void main() {
  test('keeps the last frame of a carriage-return progress line', () {
    const raw =
        'Updating files:  55% (1461/2634)\r'
        'Updating files:  56% (1476/2634)\r'
        'Updating files: 100% (2634/2634)\r'
        'Updating files: 100% (2634/2634), done.';
    expect(
      normalizeTerminalText(raw),
      'Updating files: 100% (2634/2634), done.',
    );
  });

  test('collapses CRLF and replays carriage returns per line', () {
    expect(normalizeTerminalText('a\r\nb'), 'a\nb');
    expect(normalizeTerminalText('a\rb\nx\ry'), 'b\ny');
    expect(normalizeTerminalText('10%\r20%\r30%'), '30%');
  });

  test('overwrites by rune, not by UTF-16 code unit', () {
    expect(normalizeTerminalText('文件：10%\r文件：99%'), '文件：99%');
    expect(normalizeTerminalText('🎉🎉\rX'), 'X🎉');
  });

  test('strips ANSI escape sequences', () {
    expect(normalizeTerminalText('\x1b[31mred\x1b[0m'), 'red');
    expect(normalizeTerminalText('\x1b]0;window title\x07text'), 'text');
    expect(
      normalizeTerminalText('\x1b]8;;https://example.com\x1b\\link'),
      'link',
    );
  });

  test('honours erase-to-end-of-line', () {
    expect(normalizeTerminalText('abcdef\r\x1b[Kxy'), 'xy');
    expect(normalizeTerminalText('abcdef\r\x1b[2Kxy'), 'xy');
  });

  test('trims padding left by shorter progress frames', () {
    expect(normalizeTerminalText('abcdefgh\rxy      '), 'xy');
  });

  test('keeps untouched text identical without allocating', () {
    const plain = 'plain output\nsecond line';
    expect(identical(normalizeTerminalText(plain), plain), isTrue);
    expect(normalizeTerminalText(''), '');
  });

  test('handles backspace and drops other control characters', () {
    expect(normalizeTerminalText('ab\bc'), 'ac');
    expect(normalizeTerminalText('a\x00\x07b'), 'ab');
    expect(normalizeTerminalText('col1\tcol2'), 'col1\tcol2');
  });

  test('keeps a tab as a column when the line is replayed', () {
    expect(normalizeTerminalText('a\tb\rc'), 'c\tb');
    expect(normalizeTerminalText('\t\rx'), 'x');
  });
}
