import 'package:flutter_test/flutter_test.dart';
import 'package:court_ocr_scanner/main.dart';

void main() {
  group('strict court date helpers', () {
    test('normalizes dates with slash, dash, or dot', () {
      expect(normalizeCourtDate('7-10-2026'), '07/10/2026');
      expect(normalizeCourtDate('07.10.2026'), '07/10/2026');
      expect(normalizeCourtDate('07/10/2026'), '07/10/2026');
    });
    test('rejects impossible or unrecognized dates', () {
      expect(normalizeCourtDate('31/02/2026'), isEmpty);
      expect(normalizeCourtDate('not a date'), isEmpty);
      expect(parseStrictDate('31/02/2026'), isNull);
    });
    test('month/year follows hearing date', () {
      expect(monthYear('16/12/2026'), 'Dec2026');
      expect(monthYear(''), isEmpty);
    });
  });
}
