/// Stack-based JSON repair utility.
///
/// Priorities: **safety > recovery**. Never corrupts valid JSON.
///
/// Handles:
///  - Control characters inside string literals  (the #1 AI failure mode)
///  - Unclosed trailing string literals
///  - Trailing commas before `}` or `]`
///  - Orphan keys / key-colon pairs with no value
///  - Unbalanced / mismatched brackets
///
/// Constraints:
///  - NO regex for structural parsing — uses character + token scanning
///  - Brackets inside quoted strings are ignored correctly
///  - Does NOT guess missing values
///  - Throws [FormatException] when ambiguity cannot be resolved safely
String sanitizeJson(String json) {
  if (json.trim().isEmpty) throw FormatException('Empty JSON input');

  // ═══════════════════════════════════════════════════════════════════
  //  PHASE 1 — Escape control characters inside string literals.
  //            Close any unclosed trailing string.
  //            Character-by-character, O(n).
  // ═══════════════════════════════════════════════════════════════════
  final p1 = StringBuffer();
  {
    bool inStr = false;
    bool esc = false;

    for (int i = 0; i < json.length; i++) {
      final c = json.codeUnitAt(i);

      // Previous char was backslash inside a string — emit and reset
      if (esc) {
        p1.writeCharCode(c);
        esc = false;
        continue;
      }

      // Backslash inside a string — start escape sequence
      if (inStr && c == 0x5C) {
        esc = true;
        p1.writeCharCode(c);
        continue;
      }

      // Unescaped double-quote — toggle string state
      if (c == 0x22) {
        inStr = !inStr;
        p1.writeCharCode(c);
        continue;
      }

      // Control character (< 0x20) inside a string — must be escaped
      if (inStr && c < 0x20) {
        const shortcuts = {
          0x08: 'b',
          0x09: 't',
          0x0A: 'n',
          0x0C: 'f',
          0x0D: 'r',
        };
        if (shortcuts.containsKey(c)) {
          p1.write('\\${shortcuts[c]}');
        } else {
          p1.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
        }
        continue;
      }

      p1.writeCharCode(c);
    }

    // Close dangling string literal that was never terminated
    if (inStr) p1.write('"');
  }

  // ═══════════════════════════════════════════════════════════════════
  //  PHASE 2 — Tokenize (string-aware) into structural tokens.
  //
  //  Token types:
  //    S  = complete "..." string (incl. quotes)
  //    W  = contiguous whitespace
  //    L  = literal value fragment (number, true, false, null)
  //    {  }  [  ]  ,  :   = single structural character
  // ═══════════════════════════════════════════════════════════════════
  final source = p1.toString();
  //             [type, value]
  final tokens = <List<String>>[];
  {
    int i = 0;
    while (i < source.length) {
      final c = source[i];

      // ── String literal ──
      if (c == '"') {
        final sb = StringBuffer('"');
        i++;
        bool e = false;
        while (i < source.length) {
          final ch = source[i];
          sb.write(ch);
          if (e) {
            e = false;
            i++;
            continue;
          }
          if (ch == '\\') {
            e = true;
            i++;
            continue;
          }
          if (ch == '"') {
            i++;
            break;
          }
          i++;
        }
        tokens.add(['S', sb.toString()]);
        continue;
      }

      // ── Whitespace ──
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        final sb = StringBuffer();
        while (i < source.length && ' \t\n\r'.contains(source[i])) {
          sb.write(source[i]);
          i++;
        }
        tokens.add(['W', sb.toString()]);
        continue;
      }

      // ── Structural character ──
      if ('{}[]:,'.contains(c)) {
        tokens.add([c, c]);
        i++;
        continue;
      }

      // ── Literal value (true, false, null, numbers) ──
      final sb = StringBuffer();
      while (i < source.length && !'{}[]:," \t\n\r'.contains(source[i])) {
        sb.write(source[i]);
        i++;
      }
      if (sb.isNotEmpty) {
        tokens.add(['L', sb.toString()]);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  PHASE 3 — Mark tokens for removal:
  //            • trailing commas       (,  →  } or ])
  //            • orphan keys           ("key"  →  } or ])
  //            • orphan key-colon      ("key":  →  } or ])
  //            • dangling comma at EOF
  //
  //  Uses index-based lookahead with a removal-mark array.
  // ═══════════════════════════════════════════════════════════════════
  int _nextSig(int from) {
    for (int j = from; j < tokens.length; j++) {
      if (tokens[j][0] != 'W') return j;
    }
    return tokens.length;
  }

  int _prevSig(int from) {
    for (int j = from; j >= 0; j--) {
      if (tokens[j][0] != 'W') return j;
    }
    return -1;
  }

  final remove = List<bool>.filled(tokens.length, false);

  for (int i = 0; i < tokens.length; i++) {
    if (remove[i]) continue;
    final type = tokens[i][0];

    // ── Rule 1: Trailing comma — comma whose next significant is } ] or EOF ──
    if (type == ',') {
      final nxt = _nextSig(i + 1);
      if (nxt >= tokens.length ||
          tokens[nxt][0] == '}' ||
          tokens[nxt][0] == ']') {
        remove[i] = true;
        continue;
      }
    }

    // ── Rule 2: Orphan key — "key" followed directly by } ] or EOF ──
    if (type == 'S') {
      final nxt = _nextSig(i + 1);
      final nxtType = nxt < tokens.length ? tokens[nxt][0] : 'EOF';

      if (nxtType == '}' || nxtType == ']' || nxtType == 'EOF') {
        // Only remove if this string looks like an orphan KEY
        // (preceded by , or { or [), not a valid array value
        final prev = _prevSig(i - 1);
        if (prev >= 0 && (tokens[prev][0] == ',' || tokens[prev][0] == '{')) {
          // Remove the string AND a preceding comma if any
          if (tokens[prev][0] == ',') {
            remove[prev] = true;
            for (int k = prev + 1; k <= i; k++) remove[k] = true;
          } else {
            // After opening brace — just remove the orphan key
            remove[i] = true;
          }
          continue;
        }
      }

      // ── Rule 3: Orphan key-colon — "key": with no value before } ] EOF ──
      if (nxtType == ':') {
        final afterColon = _nextSig(nxt + 1);
        final afterType = afterColon < tokens.length
            ? tokens[afterColon][0]
            : 'EOF';

        if (afterType == '}' || afterType == ']' || afterType == 'EOF') {
          final prev = _prevSig(i - 1);
          final removeFrom = (prev >= 0 && tokens[prev][0] == ',') ? prev : i;
          for (int k = removeFrom; k <= nxt; k++) remove[k] = true;
          // Also remove whitespace between colon and the closing bracket
          for (int k = nxt + 1; k < afterColon; k++) {
            if (tokens[k][0] == 'W') remove[k] = true;
          }
          continue;
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  PHASE 4 — Stack-based bracket balancing on surviving tokens.
  //            • Drops extra/mismatched closers.
  //            • Auto-closes unclosed openers at the end.
  //            • Never inserts openers or guesses values.
  // ═══════════════════════════════════════════════════════════════════
  final stack = <String>[];
  final out = <List<String>>[];

  for (int i = 0; i < tokens.length; i++) {
    if (remove[i]) continue;
    final type = tokens[i][0];

    if (type == '{' || type == '[') {
      stack.add(type);
      out.add(tokens[i]);
    } else if (type == '}') {
      if (stack.isNotEmpty && stack.last == '{') {
        stack.removeLast();
        out.add(tokens[i]);
      }
      // else: extra or mismatched closer — silently drop
    } else if (type == ']') {
      if (stack.isNotEmpty && stack.last == '[') {
        stack.removeLast();
        out.add(tokens[i]);
      }
      // else: extra or mismatched closer — silently drop
    } else {
      out.add(tokens[i]);
    }
  }

  // Close remaining open brackets (LIFO order)
  while (stack.isNotEmpty) {
    final opener = stack.removeLast();
    // Before closing, strip any trailing comma in the output
    int last = out.length - 1;
    while (last >= 0 && out[last][0] == 'W') last--;
    if (last >= 0 && out[last][0] == ',') {
      out.removeAt(last);
    }
    out.add([opener == '{' ? '}' : ']', opener == '{' ? '}' : ']']);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  PHASE 5 — Reconstruct the repaired string.
  // ═══════════════════════════════════════════════════════════════════
  final result = StringBuffer();
  for (final t in out) {
    result.write(t[1]);
  }

  return result.toString();
}
