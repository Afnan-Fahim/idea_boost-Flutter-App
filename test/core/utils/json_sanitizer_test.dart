import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ideaboost/core/utils/json_sanitizer.dart';

/// Helper: sanitize, then decode — must produce valid JSON that round-trips.
Map<String, dynamic> _fix(String raw) =>
    jsonDecode(sanitizeJson(raw)) as Map<String, dynamic>;

List<dynamic> _fixList(String raw) =>
    jsonDecode(sanitizeJson(raw)) as List<dynamic>;

void main() {
  // ═══════════════════════════════════════════════════════════════════
  //  GROUP 1 — Valid JSON must pass through UNCHANGED
  // ═══════════════════════════════════════════════════════════════════
  group('Valid JSON passthrough (no corruption)', () {
    test('simple object', () {
      const input = '{"name": "hello", "count": 42}';
      expect(jsonDecode(sanitizeJson(input)), jsonDecode(input));
    });

    test('nested arrays and objects', () {
      const input =
          '{"a": [1, 2, 3], "b": {"c": true, "d": null}, "e": "test"}';
      expect(jsonDecode(sanitizeJson(input)), jsonDecode(input));
    });

    test('strings with special chars (quotes, backslash, unicode)', () {
      const input = r'{"msg": "He said \"hello\\world\"", "emoji": "\u2764"}';
      expect(jsonDecode(sanitizeJson(input)), jsonDecode(input));
    });

    test('empty object and array', () {
      expect(jsonDecode(sanitizeJson('{}')), {});
      expect(jsonDecode(sanitizeJson('[]')), []);
    });

    test('deeply nested structure', () {
      const input = '{"a":{"b":{"c":{"d":[1,2,{"e":"f"}]}}}}';
      expect(jsonDecode(sanitizeJson(input)), jsonDecode(input));
    });

    test('string containing braces/brackets', () {
      const input = '{"code": "if (x > 0) { arr[0] = 1; }"}';
      expect(jsonDecode(sanitizeJson(input)), jsonDecode(input));
    });

    test('string containing escaped quotes', () {
      const input = '{"text": "She said \\"wow\\""}';
      expect(jsonDecode(sanitizeJson(input)), jsonDecode(input));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  GROUP 2 — Control characters inside strings (the #1 AI failure)
  // ═══════════════════════════════════════════════════════════════════
  group('Control character escaping', () {
    test('literal newline inside string value', () {
      // This is the EXACT failure from the HashtagGenerator logs
      final raw = '{"hashtags": "#CozyFeelings, #GoodVibes,\n#WarmSmiles"}';
      final result = _fix(raw);
      expect(result['hashtags'], contains('#CozyFeelings'));
      expect(result['hashtags'], contains('#WarmSmiles'));
    });

    test('literal tab inside string value', () {
      final raw = '{"text": "hello\tworld"}';
      final result = _fix(raw);
      expect(result['text'], contains('hello'));
      expect(result['text'], contains('world'));
    });

    test('literal carriage return inside string', () {
      final raw = '{"text": "line1\rline2"}';
      final result = _fix(raw);
      expect(result['text'], isNotEmpty);
    });

    test('multiple control chars in one string', () {
      final raw = '{"bio": "Hi!\nI am\ttesting\r\nthis."}';
      final result = _fix(raw);
      expect(result['bio'], contains('Hi!'));
      expect(result['bio'], contains('this.'));
    });

    test('control chars in array values', () {
      final raw = '{"comments": ["Great\npost!", "Love\tit!"]}';
      final result = _fix(raw);
      final comments = result['comments'] as List;
      expect(comments.length, greaterThanOrEqualTo(1));
      // All control chars should be escaped, content preserved
      expect(comments.first.toString(), contains('Great'));
    });

    test('null byte in string', () {
      final raw = '{"text": "before\x00after"}';
      final result = _fix(raw);
      expect(result['text'], contains('before'));
    });

    test('backspace in string', () {
      final raw = '{"text": "oops\x08fix"}';
      final result = _fix(raw);
      expect(result['text'], isNotEmpty);
    });

    test('form feed in string', () {
      final raw = '{"text": "page\x0Cbreak"}';
      final result = _fix(raw);
      expect(result['text'], isNotEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  GROUP 3 — Trailing commas
  // ═══════════════════════════════════════════════════════════════════
  group('Trailing commas', () {
    test('trailing comma in object', () {
      final result = _fix('{"a": 1, "b": 2,}');
      expect(result, {'a': 1, 'b': 2});
    });

    test('trailing comma in array', () {
      final result = _fix('{"items": [1, 2, 3,]}');
      expect(result['items'], [1, 2, 3]);
    });

    test('trailing comma with whitespace', () {
      final result = _fix('{"a": 1 ,  }');
      expect(result, {'a': 1});
    });

    test('multiple trailing commas (nested)', () {
      final result = _fix('{"a": [1, 2,], "b": 3,}');
      expect(result['a'], [1, 2]);
      expect(result['b'], 3);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  GROUP 4 — Orphan keys (truncated AI responses)
  // ═══════════════════════════════════════════════════════════════════
  group('Orphan key removal', () {
    test('orphan key before closing brace', () {
      final result = _fix('{"friendly": ["a", "b"], "humorous"}');
      expect(result.containsKey('friendly'), true);
      expect((result['friendly'] as List).first, 'a');
      expect(result.containsKey('humorous'), false);
    });

    test('orphan key-colon before closing brace', () {
      final result = _fix('{"friendly": ["a"], "humorous": }');
      expect(result['friendly'], ['a']);
    });

    test('orphan key with comma before closing brace', () {
      final result = _fix('{"a": 1, "b": 2, "orphan"}');
      expect(result, {'a': 1, 'b': 2});
    });

    test('orphan key-colon at EOF (no closing brace)', () {
      final result = _fix('{"a": 1, "orphan": ');
      expect(result, {'a': 1});
    });

    test('sole orphan key in empty object', () {
      final result = _fix('{"orphan_key"}');
      expect(result, {});
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  GROUP 5 — Unbalanced brackets
  // ═══════════════════════════════════════════════════════════════════
  group('Bracket balancing', () {
    test('missing closing brace', () {
      final result = _fix('{"a": 1, "b": 2');
      expect(result, {'a': 1, 'b': 2});
    });

    test('missing closing bracket in array', () {
      final result = _fix('{"items": [1, 2, 3}');
      expect(result['items'], [1, 2, 3]);
    });

    test('missing both ] and }', () {
      final result = _fix('{"items": [1, 2');
      expect(result['items'], [1, 2]);
    });

    test('extra closing brace is dropped', () {
      final result = _fix('{"a": 1}}');
      expect(result, {'a': 1});
    });

    test('extra closing bracket is dropped', () {
      final result = _fix('{"items": [1, 2]]}');
      expect(result['items'], [1, 2]);
    });

    test('mismatched brackets (] where } expected)', () {
      // Should drop the mismatched ] and auto-close with }
      final raw = '{"a": 1]';
      final sanitized = sanitizeJson(raw);
      final result = jsonDecode(sanitized);
      expect(result['a'], 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  GROUP 6 — Unclosed strings
  // ═══════════════════════════════════════════════════════════════════
  group('Unclosed string repair', () {
    test('unclosed string at end of value', () {
      final result = _fix('{"text": "hello world}');
      expect(result['text'], contains('hello world'));
    });

    test('unclosed string truncated mid-sentence', () {
      final result = _fix('{"bio": "I love codin');
      expect(result['bio'], contains('I love codin'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  GROUP 7 — Real-world AI response failures (from production logs)
  // ═══════════════════════════════════════════════════════════════════
  group('Real AI response failures', () {
    test('hashtag with literal newlines (exact production crash)', () {
      final raw =
          '{"hashtags": "#CozyFeelings, #GoodVibesOnly, '
          '#ApproachableYou, #WarmSmiles, #FriendlyFaces,\n'
          '#SpreadLove, #KindnessMatters, #BeYourself"}';
      final result = _fix(raw);
      expect(result['hashtags'], contains('#CozyFeelings'));
      expect(result['hashtags'], contains('#BeYourself'));
    });

    test('comment generator truncated mid-tone', () {
      final raw =
          '{"friendly": ["Nice post!", "Love it!"], "humorous": ["LOL 😂", "Dead 💀"], "supportive"';
      final result = _fix(raw);
      // friendly and humorous are complete — must be preserved
      expect(result.containsKey('friendly'), true);
      expect(result.containsKey('humorous'), true);
      // supportive was orphan key — must be dropped
      expect(result.containsKey('supportive'), false);
    });

    test('comment generator with trailing comma + orphan key', () {
      final raw =
          '{"friendly": ["Great!"], "engaging_question": ["What do you think?"], "hate_to_art"}';
      final result = _fix(raw);
      expect(result['friendly'], ['Great!']);
      expect(result['engaging_question'], ['What do you think?']);
    });

    test('viral rewrite with control chars in rewritten text', () {
      final raw =
          '{"rewritten": "🔥 This is INSANE!\nYou NEED to see this!\nDrop a ❤️ if you agree!"}';
      final result = _fix(raw);
      expect(result['rewritten'], contains('INSANE'));
      expect(result['rewritten'], contains('agree'));
    });

    test('script generator truncated voiceover array', () {
      final raw =
          '{"hook": "Wait for it...", "voiceover": ["Line 1", "Line 2", "Line 3';
      final result = _fix(raw);
      expect(result['hook'], 'Wait for it...');
      expect(result['voiceover'], isList);
    });

    test('shot ideas with mixed issues', () {
      final raw =
          '{"shot_ideas": "1. Overhead shot of coffee\n2. Close-up of steam\n3. Pour shot,"}';
      final result = _fix(raw);
      expect(result['shot_ideas'], contains('Overhead'));
      expect(result['shot_ideas'], contains('Pour shot'));
    });

    test('large multi-tone comment response with truncation', () {
      final raw =
          '''{"friendly": ["You look amazing! 😊", "Such a vibe! ✨", "Love this!", "Keep shining! 🌟", "Beautiful post!"], "humorous": ["Me trying to be this cool: 🤡", "BRB stealing this look 😂", "My WiFi dropped seeing this 💀", "This broke my scroll! 😆", "I can't even right now"], "supportive": ["You're doing incredible!", "So proud of you! 💪", "Never stop being you!", "This made my day better", "Absolutely stunning work!"], "thought_provoking": ["What inspired you?", "This really makes you think", "The deeper meaning here though", "Love the storytelling", "There's so much to unpack here"], "engaging_question''';
      final result = _fix(raw);
      // Complete tones must be preserved
      expect(result.containsKey('friendly'), true);
      expect((result['friendly'] as List).length, greaterThanOrEqualTo(4));
      expect(result.containsKey('humorous'), true);
      expect(result.containsKey('supportive'), true);
      expect(result.containsKey('thought_provoking'), true);
      // Truncated engaging_question should be dropped (orphan key)
      expect(result.containsKey('engaging_question'), false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  GROUP 8 — Edge cases / adversarial
  // ═══════════════════════════════════════════════════════════════════
  group('Edge cases', () {
    test('empty input throws FormatException', () {
      expect(() => sanitizeJson(''), throwsFormatException);
      expect(() => sanitizeJson('   '), throwsFormatException);
    });

    test('string value containing JSON-like content', () {
      final result = _fix(
        '{"example": "The JSON looks like {\\"key\\": \\"val\\"}"}',
      );
      expect(result['example'], contains('key'));
    });

    test('numeric values preserved', () {
      final result = _fix('{"int": 42, "float": 3.14, "neg": -7}');
      expect(result['int'], 42);
      expect(result['float'], 3.14);
      expect(result['neg'], -7);
    });

    test('boolean and null preserved', () {
      final result = _fix('{"a": true, "b": false, "c": null}');
      expect(result['a'], true);
      expect(result['b'], false);
      expect(result['c'], null);
    });

    test('top-level array', () {
      final result = _fixList('[1, 2, 3]');
      expect(result, [1, 2, 3]);
    });

    test('deeply nested with trailing comma', () {
      final result = _fix('{"a": {"b": {"c": [1, 2,],},},}');
      expect(result['a']['b']['c'], [1, 2]);
    });

    test('whitespace-only between tokens', () {
      final result = _fix('{  "a"  :  1  ,  "b"  :  2  }');
      expect(result, {'a': 1, 'b': 2});
    });

    test('escaped backslash before quote', () {
      // The string value is: a backslash followed by the end of string
      const input = r'{"path": "C:\\Users\\test"}';
      final result = _fix(input);
      expect(result['path'], contains('Users'));
    });
  });
}
