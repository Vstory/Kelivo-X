/// Normalizes text captured from a process or PTY so it can be shown in a
/// plain [Text] widget.
///
/// Progress output from tools such as `git`, `pip`, `curl` or `docker` redraws
/// a single line by writing `\r` (carriage return) and painting the line again.
/// A terminal emulator replays that in place, so the user only ever sees the
/// newest frame. The workspace tool card renders captured output with a plain
/// [Text] widget, which has no glyph for `\r`: the control character is drawn
/// as a "tofu" box and every frame of the progress bar ends up on screen at
/// once (`Updating files: 55% (1461/2634)□Updating files: 56% ...`).
///
/// [normalizeTerminalText] replays those control characters the way a terminal
/// would, so the same output reads as a single, final line:
///
/// ```dart
/// normalizeTerminalText('10%\r20%\r30%');      // '30%'
/// normalizeTerminalText('a\rb\nx\ry');         // 'b\ny'
/// normalizeTerminalText('\x1b[31mred\x1b[0m'); // 'red'
/// ```
///
/// Specifically it:
/// - collapses `\r\n` to `\n`;
/// - overwrites the current line on `\r` (and steps back on `\b`);
/// - honours `ESC[K` / `ESC[2K` (erase to end of line / whole line);
/// - drops ANSI escape sequences, which have no visible width;
/// - drops other C0 control characters (tab and newline are kept);
/// - trims trailing spaces left over from padded progress frames.
String normalizeTerminalText(String input) {
  if (input.isEmpty || !_hasControlChars(input)) return input;
  final lines = input.split('\n');
  final out = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    if (i > 0) out.write('\n');
    out.write(_renderLine(lines[i]));
  }
  return out.toString();
}

/// True when [input] holds carriage returns, escape sequences or other control
/// characters that a plain text widget cannot render.
bool _hasControlChars(String input) {
  for (var i = 0; i < input.length; i++) {
    final unit = input.codeUnitAt(i);
    if (unit == 0x0D || unit == 0x1B || unit == 0x7F) return true;
    if (unit < 0x20 && unit != 0x09 && unit != 0x0A) return true;
  }
  return false;
}

/// Replays [line] column by column, the way a terminal would.
String _renderLine(String line) {
  final units = line.codeUnits;
  final rendered = <int>[];
  var column = 0;
  var i = 0;

  void put(int rune) {
    if (column < rendered.length) {
      rendered[column] = rune;
    } else {
      rendered.add(rune);
    }
    column++;
  }

  while (i < units.length) {
    final unit = units[i];

    if (unit == 0x1B) {
      final end = _escapeEnd(units, i);
      switch (_eraseOf(units, i, end)) {
        case _Erase.toEnd:
          if (column < rendered.length) {
            rendered.removeRange(column, rendered.length);
          }
        case _Erase.wholeLine:
          rendered.clear();
          column = 0;
        case _Erase.none:
          break;
      }
      i = end;
      continue;
    }

    if (unit == 0x0D) {
      column = 0;
      i++;
      continue;
    }
    if (unit == 0x08) {
      if (column > 0) column--;
      i++;
      continue;
    }
    if (unit == 0x09) {
      // A tab still paints a cell, so it is replayed as a normal column
      // instead of being dropped (the terminal only widens it).
      put(unit);
      i++;
      continue;
    }
    if (unit < 0x20 || unit == 0x7F) {
      // Drop control characters, which have no visible width.
      i++;
      continue;
    }
    if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < units.length) {
      final low = units[i + 1];
      if (low >= 0xDC00 && low <= 0xDFFF) {
        put((unit - 0xD800) * 0x400 + (low - 0xDC00) + 0x10000);
        i += 2;
        continue;
      }
    }
    put(unit);
    i++;
  }

  var end = rendered.length;
  while (end > 0 && (rendered[end - 1] == 0x20 || rendered[end - 1] == 0x09)) {
    end--;
  }
  return String.fromCharCodes(rendered.sublist(0, end));
}

/// Offset just past the escape sequence that starts at [start] (the ESC code
/// unit). Malformed sequences consume only the ESC so no real text is eaten.
int _escapeEnd(List<int> units, int start) {
  var i = start + 1;
  if (i >= units.length) return units.length;
  final kind = units[i];

  if (kind == 0x5B) {
    // '[' Control Sequence Introducer.
    i++;
    while (i < units.length && units[i] >= 0x30 && units[i] <= 0x3F) {
      i++; // Parameter bytes.
    }
    while (i < units.length && units[i] >= 0x20 && units[i] <= 0x2F) {
      i++; // Intermediate bytes.
    }
    if (i < units.length && units[i] >= 0x40 && units[i] <= 0x7E) return i + 1;
    return start + 1;
  }

  if (kind == 0x5D || kind == 0x50 || kind == 0x5E || kind == 0x5F) {
    // ']' P ^ _ String sequences, terminated by BEL or ST.
    i++;
    while (i < units.length) {
      if (units[i] == 0x07) return i + 1;
      if (units[i] == 0x1B && i + 1 < units.length && units[i + 1] == 0x5C) {
        return i + 2;
      }
      i++;
    }
    return units.length;
  }

  // Two-character escape (e.g. ESC ( B, ESC =, ESC >).
  if (kind == 0x28 || kind == 0x29 || kind == 0x2A || kind == 0x2B) {
    return i + 1 < units.length ? i + 2 : units.length;
  }
  return i + 1;
}

enum _Erase { none, toEnd, wholeLine }

/// Recognizes the `ESC[K` family, which erases part of the current line.
_Erase _eraseOf(List<int> units, int start, int end) {
  if (end - start < 3) return _Erase.none;
  if (units[start + 1] != 0x5B) return _Erase.none;
  if (units[end - 1] != 0x4B) return _Erase.none; // 'K'
  final params = String.fromCharCodes(units.sublist(start + 2, end - 1));
  if (params == '2') return _Erase.wholeLine;
  if (params.isEmpty || params == '0') return _Erase.toEnd;
  return _Erase.none;
}
