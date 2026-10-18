import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;

void main() => runApp(const CourtOcrApp());

class CourtOcrApp extends StatelessWidget {
  const CourtOcrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Court OCR Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF173B63)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      home: const RegisterPage(),
    );
  }
}

class FieldSpec {
  final String column;
  final String label;
  final String hint;
  const FieldSpec(this.column, this.label, [this.hint = '']);
}

const fieldSpecs = <FieldSpec>[
  FieldSpec('A', 'SR NO'),
  FieldSpec('B', 'REGISTER NO'),
  FieldSpec('C', 'RECIPT DATE (DD/MM/YYYY)'),
  FieldSpec('D', 'MONTH/YEAR (receipt date)'),
  FieldSpec('E', 'FIR / CASE NO'),
  FieldSpec('F', 'UNDER SECTION'),
  FieldSpec('G', 'POLICE STATION'),
  FieldSpec('H', 'ORDER TYPE'),
  FieldSpec('I', 'COURT NAME'),
  FieldSpec('J', 'PESHI / NEXT HEARING DATE (DD/MM/YYYY)'),
  FieldSpec('K', 'MONTH/YEAR (Peshi date)'),
  FieldSpec('L', 'ARREST YES/NO'),
  FieldSpec('M', 'DATE OF ARREST (DD/MM/YYYY)'),
  FieldSpec('N', 'WHETHER PESHI HAPPENED'),
  FieldSpec('O', 'REMARK / ACTION PLAN'),
  FieldSpec('P', 'ISSUE DATE (DD/MM/YYYY)'),
  FieldSpec('Q', 'DESIGNATION'),
  FieldSpec('R', 'NAME'),
  FieldSpec('S', 'ADDRESS'),
  FieldSpec('T', 'MOBILE NO. OF PERSON SUMMONED'),
  FieldSpec('U', 'POSTING PLACE'),
  FieldSpec('V', 'THROUGH SUPERINTENDENT'),
  FieldSpec('W', 'MARK TO / ASSIGNED PERSON'),
  FieldSpec('X', 'STATUS'),
  FieldSpec('Y', 'REASON'),
  FieldSpec('Z', 'STATUS / DAYS TO EXECUTE'),
  FieldSpec('AA', 'FINAL STATUS ON SUMMON'),
  FieldSpec('AB', 'COMPLIANCE REPORT SENT TO COURT'),
  FieldSpec('AC', 'COMPLIANCE REPORT FORMAT'),
  FieldSpec('AD', 'CURRENT DATE (DD/MM/YYYY)'),
  FieldSpec('AE', 'SUMMON FOR'),
  FieldSpec('AF', 'AREA / JURISDICTION'),
  FieldSpec('AG', 'MOBILE NO.'),
  FieldSpec('AH', 'CURRENT DATE (DD/MM/YYYY)'),
  FieldSpec('AI', 'RECEIVED DAYS'),
  FieldSpec('AJ', 'SUMMON BRANCH DAYS TO EXECUTE'),
  FieldSpec('AK', 'SUMMON GET IN DAYS'),
  FieldSpec('AL', 'PARVIKAR NAME'),
  FieldSpec('AM', 'PURPOSE OF SUMMON'),
  FieldSpec('AN', 'WHETHER WITNESS CALLED'),
  FieldSpec('AO', 'REASON FOR NOT CALLING'),
  FieldSpec('AQ', 'WHETHER WITNESS ATTENDED COURT'),
  FieldSpec('AR', 'EVIDENCE RECORDED'),
  FieldSpec('AS', 'REASON EVIDENCE NOT RECORDED'),
  FieldSpec('AT', 'REQUEST REASON'),
  FieldSpec('AU', 'EVIDENCE TIME'),
  FieldSpec('AV', 'REMARKS'),
  FieldSpec('AW', 'STATUS OF RECORDING'),
  FieldSpec('AX', 'DELAY IN RECEIVING SUMMONS'),
  FieldSpec('AY', 'STATUS OF DELAY'),
  FieldSpec('AZ', 'POSTINGS'),
  FieldSpec('BA', 'EXECUTION DAYS'),
  FieldSpec('BB', 'CATEGORY'),
  FieldSpec('BC', 'CNR'),
];

int colIndex(String letters) {
  var result = 0;
  for (final code in letters.codeUnits) {
    result = result * 26 + code - 64;
  }
  return result - 1;
}

String fmtDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

DateTime? parseStrictDate(String date) {
  final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(date.trim());
  if (match == null) return null;
  final day = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final year = int.tryParse(match.group(3)!);
  if (day == null || month == null || year == null || year < 1 ||
      month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  final parsed = DateTime(year, month, day);
  // DateTime normalizes impossible dates (for example, 31 February); reject them.
  if (parsed.year != year || parsed.month != month || parsed.day != day) return null;
  return parsed;
}

String normalizeCourtDate(String raw) {
  final m = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$').firstMatch(raw.trim());
  if (m == null) return '';
  final candidate = '${m.group(1)!.padLeft(2, '0')}/${m.group(2)!.padLeft(2, '0')}/${m.group(3)}';
  return parseStrictDate(candidate) == null ? '' : candidate;
}

String monthYear(String date) {
  final parsed = parseStrictDate(date);
  if (parsed == null) return '';
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${months[parsed.month - 1]}${parsed.year}';
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _picker = ImagePicker();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _values = {};
  final List<String> _defaultAssignees = [
    'SHO CITY', 'SHO BAHIN', 'EHC SUBHASH CHAND', 'SPO RAMESH 246',
    'CT RAVI 1497 PWL', 'EHC KARTAR 118', 'CT AJAY 99',
    'CT NASEEM KHAN 473', 'EHC HASAN'
  ];
  List<String> _assignees = [];
  String _cloudVisionEndpoint = '';
  String _rawText = '';
  String? _workbookPath;
  Uint8List? _workbookBytes;
  bool _busy = false;
  String _status = 'Configure Cloud Vision backend, then scan a document or open an Excel register.';

  @override
  void initState() {
    super.initState();
    for (final spec in fieldSpecs) {
      _controllers[spec.column] = TextEditingController();
      _values[spec.column] = '';
    }
    _values['H'] = 'SUMMON';
    _values['L'] = 'NO';
    _values['N'] = 'NOT UPDATED';
    _values['O'] = 'NONE';
    _values['V'] = 'NOT MENTIONED';
    _values['W'] = 'UNASSIGNED';
    _values['X'] = 'PENDING';
    _values['AE'] = 'PRIVATE PERSON';
    _values['AF'] = 'WITHIN DISTRICT';
    _values['AM'] = 'ACCUSED';
    _values['AB'] = 'NO';
    _values['AD'] = fmtDate(DateTime.now());
    _values['AH'] = fmtDate(DateTime.now());
    _values['AV'] = 'NONE';
    _loadSettings();
    _loadCloudVisionEndpoint();
    _setDefaultDates();
    _loadBundledWorkbook();
  }

  void _setDefaultDates() {
    final now = DateTime.now();
    _values['C'] = fmtDate(now);
    _values['D'] = monthYear(fmtDate(now));
    _values['P'] = fmtDate(now);
    // Hearing date must come from the document or verified court data.
    _values['J'] = '';
    _values['K'] = '';
    _values['AD'] = fmtDate(now);
    _values['AH'] = fmtDate(now);
    _syncControllers();
  }

  Future<void> _loadBundledWorkbook() async {
    try {
      final data = await rootBundle.load('assets/GH.xlsx');
      if (!mounted) return;
      setState(() {
        _workbookBytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        _workbookPath = 'GH.xlsx (built-in template)';
        _status = 'GH.xlsx loaded. Scan a document, review fields, and export a new register copy.';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Open GH.xlsx to begin. Built-in workbook could not load: $e');
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('assignees');
    if (!mounted) return;
    setState(() => _assignees = saved == null ? List.of(_defaultAssignees) : saved);
  }


  Future<void> _loadCloudVisionEndpoint() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _cloudVisionEndpoint = prefs.getString('cloudVisionEndpoint') ?? '');
  }

  Future<void> _configureCloudVision() async {
    final controller = TextEditingController(text: _cloudVisionEndpoint);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Google Cloud Vision OCR'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter your secure backend HTTPS URL ending in /ocr. Do not put a Google Cloud API key in this app. The backend must call Cloud Vision with language hints en and hi.'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Cloud Vision backend HTTPS URL',
                  hintText: 'https://your-service.run.app/ocr',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == null) {
      controller.dispose();
      return;
    }
    final endpoint = saved.trim();
    if (endpoint.isNotEmpty) {
      final uri = Uri.tryParse(endpoint);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Use a valid HTTPS backend URL.')),
          );
        }
        controller.dispose();
        return;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cloudVisionEndpoint', endpoint);
    if (mounted) {
      setState(() => _cloudVisionEndpoint = endpoint);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(endpoint.isEmpty ? 'Cloud Vision endpoint cleared.' : 'Cloud Vision endpoint saved.')),
      );
    }
    controller.dispose();
  }

  Future<String> _recognizeWithCloudVision(String imagePath) async {
    if (_cloudVisionEndpoint.trim().isEmpty) {
      throw Exception('Cloud Vision is not configured. Open the OCR settings and save your secure backend HTTPS URL.');
    }
    final uri = Uri.parse(_cloudVisionEndpoint.trim());
    final bytes = await File(imagePath).readAsBytes();
    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'imageBase64': base64Encode(bytes),
        'languageHints': ['en', 'hi'],
      }),
    ).timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Cloud Vision backend returned HTTP ${response.statusCode}: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid response from Cloud Vision backend.');
    }
    final text = decoded['text'];
    if (text is! String) {
      throw Exception('Cloud Vision backend response is missing the text field.');
    }
    return text;
  }

  Future<void> _saveAssignees() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('assignees', _assignees);
  }

  void _syncControllers() {
    for (final spec in fieldSpecs) {
      _controllers[spec.column]?.text = _values[spec.column] ?? '';
    }
  }

  void _setValue(String column, String value) {
    _values[column] = value;
    if (_controllers[column]?.text != value) _controllers[column]?.text = value;
    if (column == 'C') _values['D'] = monthYear(value);
    if (column == 'J') _values['K'] = monthYear(value);
    if (column == 'I' && value.trim().isNotEmpty) {
      _values['B'] = _registrationForCourt(value.trim(), _values['C']);
    }
    if (column == 'C' || column == 'J') {
      _updateCalculatedFields();
    }
    if (column == 'C' && (_values['I'] ?? '').trim().isNotEmpty) {
      _values['B'] = _registrationForCourt(_values['I']!.trim(), value);
    }
    if (column == 'P' && value.trim().isEmpty) _values['P'] = _values['C'] ?? '';
    if (mounted) setState(() {});
  }

  String _registrationForCourt(String court, [String? date]) {
    if (_workbookBytes == null || court.trim().isEmpty) return '';
    final targetDate = (date ?? _values['C'] ?? fmtDate(DateTime.now())).trim();
    try {
      final excel = Excel.decodeBytes(_workbookBytes!);
      final sheet = excel.tables['Sheet1'];
      if (sheet == null) return '1';
      var highest = 0;
      for (var r = 1; r < sheet.maxRows; r++) {
        final existingCourt = sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIndex('I'), rowIndex: r)).value?.toString().trim() ?? '';
        if (existingCourt.toLowerCase() != court.trim().toLowerCase()) continue;
        final dateValue = sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIndex('C'), rowIndex: r)).value;
        final existingDate = _normalizeWorkbookDate(dateValue);
        if (existingDate != targetDate) continue;
        final raw = sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIndex('B'), rowIndex: r)).value?.toString().trim() ?? '';
        final number = int.tryParse(raw);
        if (number != null && number > highest) highest = number;
      }
      return '${highest + 1}';
    } catch (_) {
      return '1';
    }
  }

  String _normalizeWorkbookDate(dynamic value) {
    if (value == null) return '';
    if (value is DateTime) return fmtDate(value);
    final raw = value.toString().trim();
    final strict = parseStrictDate(raw);
    if (strict != null) return fmtDate(strict);
    final iso = DateTime.tryParse(raw);
    if (iso != null) return fmtDate(iso);
    return raw;
  }

  int? _daysBetween(String from, String to) {
    final a = parseStrictDate(from);
    final b = parseStrictDate(to);
    if (a == null || b == null) return null;
    return b.difference(a).inDays;
  }

  void _updateCalculatedFields() {
    final now = fmtDate(DateTime.now());
    _values['AD'] = now;
    _values['AH'] = now;
    final receivedAge = _daysBetween(_values['C'] ?? '', now);
    _values['AI'] = receivedAge == null ? '' : '$receivedAge';
    final toHearing = _daysBetween(_values['C'] ?? '', _values['J'] ?? '');
    _values['AJ'] = toHearing == null ? '' : '$toHearing';
    _values['AK'] = toHearing == null ? '' : '$toHearing';
    _controllers['AD']?.text = _values['AD']!;
    _controllers['AH']?.text = _values['AH']!;
    _controllers['AI']?.text = _values['AI']!;
    _controllers['AJ']?.text = _values['AJ']!;
    _controllers['AK']?.text = _values['AK']!;
  }

  Future<void> _scan(ImageSource source) async {
    try {
      final image = await _picker.pickImage(source: source, imageQuality: 95);
      if (image == null) return;
      setState(() { _busy = true; _status = 'Reading document text…'; });
      final recognizedText = await _recognizeWithCloudVision(image.path);
      _rawText = recognizedText;
      _applyOcr(recognizedText);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = recognizedText.trim().isEmpty
            ? 'No text detected. Enter the details manually.'
            : 'Google Cloud Vision OCR complete (English/Hindi). Review and correct every field before saving.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _status = 'Scan failed: $e'; });
    }
  }

  void _applyOcr(String text) {
    // Start a fresh OCR record so fields from a previous document do not leak into this one.
    for (final key in _values.keys.toList()) {
      _values[key] = '';
    }
    _values['H'] = 'SUMMON';
    _values['L'] = 'NO';
    _values['N'] = 'NOT UPDATED';
    _values['O'] = 'NONE';
    _values['V'] = 'NOT MENTIONED';
    _values['W'] = 'UNASSIGNED';
    _values['X'] = 'PENDING';
    _values['AB'] = 'NO';
    _values['AE'] = 'PRIVATE PERSON';
    _values['AF'] = 'WITHIN DISTRICT';
    _values['AM'] = 'ACCUSED';
    _values['AV'] = 'NONE';
    final lines = text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final all = lines.join('\n');
    final now = fmtDate(DateTime.now());
    _values['C'] = now;
    _values['D'] = monthYear(now);
    _values['P'] = now;
    // Do not invent a hearing date when OCR has not found a labelled date.
    _values['J'] = '';
    _values['K'] = '';
    _values['AD'] = now;
    _values['AH'] = now;
    final cnr = RegExp(r'\bCNR\s*(?:NO\.?|NUMBER)?\s*[:#-]?\s*([A-Z0-9]{12,18})\b', caseSensitive: false).firstMatch(all);
    if (cnr != null) _values['BC'] = cnr.group(1)!.toUpperCase();

    final fir = RegExp(r'\b(?:FIR\s*(?:NO\.?|NUMBER)?\s*[:#-]?\s*)?(\d{1,5}\s*/\s*\d{4})\b', caseSensitive: false).firstMatch(all);
    if (fir != null) {
      _values['E'] = fir.group(1)!.replaceAll(RegExp(r'\s+'), '');
    } else {
      final caseNo = RegExp(r'\b(?:COMI|CR|CRM|CNR|CASE)\s*[/.-]\s*[A-Z0-9/-]+\b', caseSensitive: false).firstMatch(all);
      _values['E'] = caseNo?.group(0)?.replaceAll(RegExp(r'\s+'), '') ?? '';
    }

    final section = RegExp(r'(?:U/S|UNDER\s+SECTION|SECTIONS?)\s*[:.-]?\s*([0-9A-Z ,./()\-]{1,45})', caseSensitive: false).firstMatch(all);
    if (section != null) _values['F'] = section.group(1)!.trim().split('\n').first;

    final ps = RegExp(r'(?:P\.?S\.?|POLICE\s+STATION)\s*[:.-]?\s*([A-Z][A-Z .-]{2,35}?)(?=\s{2,}|,|/|FIR|\bNO\b|$)', caseSensitive: false, multiLine: true).firstMatch(all);
    if (ps != null) {
      final name = ps.group(1)!.trim().split(RegExp(r'\s{2,}|,|FIR|DATE|CASE', caseSensitive: false)).first.trim();
      _values['G'] = name.toUpperCase().startsWith('PS ') ? name.toUpperCase() : 'PS ${name.toUpperCase()}';
    }

    final normalizedText = all.toUpperCase().replaceAll(RegExp(r'[\s_]+'), ' ');
    // Specific types before generic WARRANT / SUMMON so mixed headings don't misclassify.
    final orderPatterns = <MapEntry<RegExp, String>>[
      MapEntry(RegExp(r'NON[ -]?BA[I1]LABLE\s+WARRANT|NON[ -]?BALLABLE\s+WARRANT'), 'NON BAILABLE WARRANT'),
      MapEntry(RegExp(r'BA[I1]LABLE\s+WARRANT|BALLABLE\s+WARRANT'), 'BAILABLE WARRANT'),
      MapEntry(RegExp(r'WARRANT\s+OF\s+ARREST'), 'WARRANT OF ARREST'),
      MapEntry(RegExp(r'ARREST\s+WARRANT'), 'ARREST WARRANT'),
      MapEntry(RegExp(r'SUMMONS?\s+TO\s+WITNESS'), 'SUMMONS'),
      MapEntry(RegExp(r'\bSUMMONS?\b'), 'SUMMONS'),
      MapEntry(RegExp(r'\bPROCLAMATION\b'), 'PROCLAMATION'),
      MapEntry(RegExp(r'\bNOTICE\b'), 'NOTICE'),
      MapEntry(RegExp(r'\bBAIL\b'), 'BAIL'),
    ];
    for (final entry in orderPatterns) {
      if (entry.key.hasMatch(normalizedText)) {
        _values['H'] = entry.value;
        break;
      }
    }

    final datePattern = r'(\d{1,2}[./-]\d{1,2}[./-]\d{4})';
    String normalizeDate(String s) => normalizeCourtDate(s);
    // Prefer labelled dates: warrants commonly list PREVIOUS DATE, NEXT DATE,
    // and the issue date separately. Do not accidentally use PREVIOUS DATE as Peshi.
    // Accept common OCR spellings around the label, but never choose the last arbitrary
    // date: warrant return-by dates and previous dates are not necessarily the next hearing.
    final nextDate = RegExp('N[E3]XT\\s*D[A4]TE\\s*[:：-]?\\s*$datePattern', caseSensitive: false).firstMatch(all);
    if (nextDate != null) {
      final parsed = normalizeDate(nextDate.group(1)!);
      if (parsed.isNotEmpty) _values['J'] = parsed;
    }
    final issueDate = RegExp(
      '(?:DATED\\s*,?\\s*THIS\\s+DAY\\s+OF|GIVEN\\s+UNDER[^\\n]{0,100}?THIS)\\s*$datePattern',
      caseSensitive: false,
    ).firstMatch(all);
    if (issueDate != null) {
      final parsed = normalizeDate(issueDate.group(1)!);
      if (parsed.isNotEmpty) _values['P'] = parsed;
    }
    // If formal label extraction missed the date, a summons often says “appear ... on
    // the day DD-MM-YYYY”; accept only that explicit appearance-date context.
    final appearDate = RegExp('(?:appear before (?:this )?Court|appear before me)[^\\n]{0,180}?(?:on the day|on)\\s*$datePattern', caseSensitive: false).firstMatch(all);
    if ((_values['J'] ?? '').isEmpty && appearDate != null) {
      final parsed = normalizeDate(appearDate.group(1)!);
      if (parsed.isNotEmpty) _values['J'] = parsed;
    }
    _values['K'] = monthYear(_values['J'] ?? '');

    final courtLine = lines.firstWhere(
      (line) => RegExp(r'\b(JMIC|CJ[M]?|ACJM|CJM|ADJ|SESSIONS|DISTRICT JUDGE|JMFC)\b', caseSensitive: false).hasMatch(line),
      orElse: () => '',
    );
    if (courtLine.isNotEmpty) _values['I'] = courtLine;
    final designation = RegExp(
      r'\b(LEGAL\s+ADVISOR|NODAL\s+OFFICER|DIRECTOR\s+RFSL|DIRECTOR\s+READER|HEAD\s+MASTER|HOME\s+GUARD|ADVOCATE|SHO|DSP|SP|SI|LSI|PSI|ASI|ESI|EHC|LHC|L\s*/\s*ASI|L\s*/\s*CT|RCT|HC|CT|MHC|SPO|MM|HGH|CLERK)\b',
      caseSensitive: false,
    ).firstMatch(all);
    if (designation != null) _values['Q'] = designation.group(0)!.toUpperCase().replaceAll(RegExp(r'\s*/\s*'), '/');

    final nameLine = lines.firstWhere(
      (line) => RegExp(r'\b(?:VERSUS|VS\.?|STATE OF|IN THE MATTER OF|S/O|D/O|W/O|F/O|SON OF|DAUGHTER OF|WIFE OF)\b', caseSensitive: false).hasMatch(line),
      orElse: () => '',
    );
    if (nameLine.isNotEmpty) _values['R'] = nameLine;

    // GH.xlsx column T is the mobile number field, not a present-address field.
    final mobileMatch = RegExp(r'\b[6-9]\d{9}\b').firstMatch(all);
    if (mobileMatch != null) _values['T'] = mobileMatch.group(0)!;
    final addressMatch = RegExp(
      r'(?:ADDRESS|R/O|RESIDENT\s+OF|RESIDENCE)\s*[:.-]?\s*([^\n]{5,180})',
      caseSensitive: false,
    ).firstMatch(all);
    if (addressMatch != null) {
      _values['S'] = addressMatch.group(1)!.trim().replaceAll(RegExp(r'\s{2,}'), ' ');
    }

    final roleText = all.toLowerCase();
    if (roleText.contains('witness')) _values['AM'] = 'WITNESS';
    if (roleText.contains('accused') || roleText.contains('accused person')) _values['AM'] = 'ACCUSED';
    if (RegExp(r'\bpolice\b|\bsh[o0]\b|\bconstable\b|\bhead constable\b', caseSensitive: false).hasMatch(all)) {
      _values['AE'] = 'POLICE';
    }

    // Show likely missing/uncertain case identifiers for manual correction.
    if ((_values['E'] ?? '').isEmpty) _values['E'] = '*NOTE* CASE NO NOT FOUND';
    _syncControllers();
  }

  Future<void> _chooseWorkbook() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['xlsx'], withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    setState(() {
      _workbookPath = result.files.single.name;
      _workbookBytes = result.files.single.bytes!;
      _status = 'Loaded ${result.files.single.name}. New records will be appended.';
    });
  }

  Future<void> _saveExcel() async {
    try {
      setState(() { _busy = true; _status = 'Preparing Excel workbook…'; });
      for (final column in ['C', 'J', 'P', 'M', 'AD', 'AH']) {
        final value = (_values[column] ?? '').trim();
        if (value.isNotEmpty && parseStrictDate(value) == null) {
          throw FormatException('Invalid date in column $column: "$value". Use DD/MM/YYYY.');
        }
      }
      final Excel excel;
      if (_workbookBytes != null) {
        excel = Excel.decodeBytes(_workbookBytes!);
      } else {
        excel = Excel.createExcel();
      }
      final sheet = excel.tables['Sheet1'];
      if (sheet == null) {
        throw Exception('The selected workbook must contain the GH.xlsx target sheet named Sheet1.');
      }
      // Add CNR as a new final column; do not shift or replace existing columns.
      final cnrHeaderCell = sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: colIndex('BC'), rowIndex: 0,
      ));
      final cnrHeader = cnrHeaderCell.value?.toString().trim() ?? '';
      if (cnrHeader.isEmpty) {
        cnrHeaderCell.value = const TextCellValue('CNR');
      } else if (cnrHeader.toUpperCase() != 'CNR') {
        throw Exception('Column BC is already in use by "$cnrHeader". Add CNR after the existing last column to avoid changing your workbook.');
      }
      const expectedHeaders = <String, String>{
        'A': 'SR NO', 'B': 'REGISTER NO', 'C': 'RECIPT DATE', 'D': 'MONTH/YEAR',
        'E': 'FIR', 'F': 'US', 'G': 'PS', 'H': 'ORDER', 'I': 'COURT NAME',
        'J': 'PESHI DATE', 'K': 'MONTH/YEAR', 'P': 'ISSUE DATE', 'Q': 'DESIGNATION',
        'R': 'NAME', 'S': 'ADDRESS', 'T': 'MOBIEL NO. OF PERSON SUMMONED',
        'W': 'MARK TO', 'AE': 'SUMMON FOR', 'AF': 'AREA OF TAMILI', 'AM': 'PURPOSE OF SUMMON',
        'L': 'ARREST YES/NO', 'M': 'DATE OF ARREST', 'N': 'Whether Peshi Happened or not',
        'O': 'REMARK', 'U': 'Posting place', 'V': 'THROUGH SP', 'X': 'STATUS',
        'Y': 'REASON', 'Z': 'Status of get days to Execute', 'AA': 'FINAL STATUS ON SUMMON',
        'AB': 'compliance report sent to court', 'AC': 'compliance report format',
        'AD': 'CURRANT DATE', 'AG': 'MOBILE NO', 'AH': 'CURRENT DATE',
        'AI': 'RECEIVED DAYS', 'AJ': 'Summon Branch get days to execute',
        'AK': 'summon get in days', 'AL': 'PARVI KAR NAME', 'AN': 'Whether Witness Called',
        'AO': 'reason for not calling', 'AQ': 'Whether Witness Attendent court',
        'AR': 'Whether Evidence Recorded or Not', 'AS': 'REASON NOT RECORDED EVIDENCE',
        'AT': 'REQUEST REASON', 'AU': 'EVIDENCE TIME', 'AV': 'REMARKS',
        'AW': 'Status of Recording', 'AX': 'Delay in recieving Summons',
        'AY': 'Status of delay', 'AZ': 'POSTINGS', 'BA': 'EXECUTION DAYS', 'BB': 'CATAGORY',
      };
      for (final entry in expectedHeaders.entries) {
        final actual = sheet.cell(CellIndex.indexByColumnRow(
          columnIndex: colIndex(entry.key), rowIndex: 0,
        )).value?.toString().trim() ?? '';
        if (actual.toUpperCase() != entry.value.toUpperCase()) {
          throw Exception('Sheet1 column ${entry.key} must be "${entry.value}"; found "$actual". Please select the original GH.xlsx workbook.');
        }
      }
      final row = sheet.maxRows;
      final scanDate = (_values['C'] ?? '').trim().isEmpty ? fmtDate(DateTime.now()) : _values['C']!.trim();
      _values['C'] = scanDate;
      _values['D'] = monthYear(scanDate);
      // Preserve blank issue dates; a receipt date is not the court's issue date.
      _values['K'] = monthYear(_values['J'] ?? '');
      _updateCalculatedFields();

      // Serial number restarts each scan date; registration is counted per court and date.
      var dailyCount = 0;
      for (var r = 1; r < sheet.maxRows; r++) {
        final existingValue = sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIndex('C'), rowIndex: r)).value;
        final existingDate = _normalizeWorkbookDate(existingValue);
        if (existingDate == scanDate) dailyCount++;
      }
      _values['A'] = '${dailyCount + 1}';
      final court = (_values['I'] ?? '').trim();
      _values['B'] = court.isEmpty ? '' : _registrationForCourt(court, scanDate);

      for (final spec in fieldSpecs) {
        final value = (_values[spec.column] ?? '').trim();
        sheet.cell(CellIndex.indexByColumnRow(
          columnIndex: colIndex(spec.column), rowIndex: row,
        )).value = TextCellValue(value);
      }
      final bytes = excel.encode();
      if (bytes == null) throw Exception('Excel encoding failed.');
      _workbookBytes = Uint8List.fromList(bytes);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/Court_OCR_Register_${DateTime.now().millisecondsSinceEpoch}.xlsx');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      setState(() { _busy = false; _status = 'Record appended to Sheet1. Share/save this updated workbook; open the exported file next time to continue from it.'; });
      await Share.shareXFiles([XFile(file.path)], text: 'Court OCR Scanner Excel register');
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _status = 'Excel export failed: $e'; });
    }
  }

  Future<void> _manageAssignees() async {
    final input = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
        title: const Text('Manage W assignee options'),
        content: SizedBox(
          width: 500,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: input, decoration: const InputDecoration(labelText: 'Add officer/person')),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () {
                final value = input.text.trim();
                if (value.isNotEmpty && !_assignees.contains(value)) {
                  _assignees.add(value); input.clear(); refresh(() {});
                }
              },
              child: const Text('Add option'),
            ),
            SizedBox(
              height: 260, width: double.maxFinite,
              child: ListView.builder(
                itemCount: _assignees.length,
                itemBuilder: (_, i) => ListTile(
                  dense: true,
                  title: Text(_assignees[i]),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => refresh(() => _assignees.removeAt(i)),
                  ),
                  onTap: () async {
                    final edit = TextEditingController(text: _assignees[i]);
                    final changed = await showDialog<String>(
                      context: ctx,
                      builder: (dctx) => AlertDialog(
                        title: const Text('Edit option'),
                        content: TextField(controller: edit, autofocus: true),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(dctx, edit.text.trim()), child: const Text('Save')),
                        ],
                      ),
                    );
                    if (changed != null && changed.isNotEmpty) refresh(() => _assignees[i] = changed);
                  },
                ),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () async {
            await _saveAssignees();
            if (mounted) setState(() {});
            if (ctx.mounted) Navigator.pop(ctx);
          }, child: const Text('Save settings')),
        ],
      )),
    );
  }

  Widget _buildField(FieldSpec spec) {
    if (spec.column == 'W') {
      return DropdownButtonFormField<String>(
        value: (_values['W'] ?? '') == 'UNASSIGNED'
            ? 'UNASSIGNED'
            : ((_values['W'] ?? '').isNotEmpty && _assignees.contains(_values['W']) ? _values['W'] : null),
        decoration: InputDecoration(labelText: '${spec.column} — ${spec.label}'),
        items: [
          const DropdownMenuItem(value: 'UNASSIGNED', child: Text('Unassigned')),
          ..._assignees.map((e) => DropdownMenuItem(value: e, child: Text(e))),
          const DropdownMenuItem(value: '__manual__', child: Text('Enter manually…')),
        ],
        onChanged: (value) async {
          if (value == '__manual__') {
            final controller = TextEditingController();
            final manual = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Enter officer/person'),
                content: TextField(controller: controller, autofocus: true),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Use name')),
                ],
              ),
            );
            if (manual != null && manual.isNotEmpty) _setValue('W', manual);
          } else if (value != null) {
            _setValue('W', value);
          }
        },
      );
    }
    final dropdownOptions = <String, List<String>>{
      'H': ['SUMMON', 'NOTICE', 'BAILABLE WARRANT', 'NON BAILABLE WARRANT', 'CONDITIONAL WARRANT', 'WARRANT OF ARREST', 'OTHER'],
      'L': ['NO', 'YES', 'PENDING'],
      'N': ['NOT UPDATED', 'YES', 'NO'],
      'V': ['NOT MENTIONED', 'YES', 'NO'],
      'X': ['PENDING', 'IN PROCESS', 'EXECUTED', 'RETURNED', 'CANCELLED', 'CLOSED'],
      'AB': ['NO', 'YES', 'PENDING'],
      'AE': ['PRIVATE PERSON', 'POLICE', 'OTHER GOVERNMENT PERSON'],
      'AF': ['WITHIN DISTRICT', 'OUT OF DISTRICT', 'OUT OF STATE'],
      'AM': ['ACCUSED', 'WITNESS', 'POLICE PERSON', 'PRIVATE PERSON', 'OTHER'],
      'AN': ['NOT UPDATED', 'YES', 'NO'],
      'AQ': ['NOT UPDATED', 'YES', 'NO'],
      'AR': ['NOT UPDATED', 'YES', 'NO'],
    };
    if (dropdownOptions.containsKey(spec.column)) {
      final options = dropdownOptions[spec.column]!;
      final current = _values[spec.column] ?? '';
      return DropdownButtonFormField<String>(
        value: options.contains(current) ? current : options.first,
        decoration: InputDecoration(labelText: '${spec.column} — ${spec.label}'),
        items: options.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (v) { if (v != null) _setValue(spec.column, v); },
      );
    }
    return TextFormField(
      controller: _controllers[spec.column],
      minLines: spec.column == 'R' || spec.column == 'S' ? 2 : 1,
      maxLines: spec.column == 'R' || spec.column == 'S' ? 3 : 1,
      decoration: InputDecoration(
        labelText: '${spec.column} — ${spec.label}',
        hintText: spec.hint.isNotEmpty
            ? spec.hint
            : (['C', 'J', 'P', 'M', 'AD', 'AH'].contains(spec.column) ? 'DD/MM/YYYY' : null),
      ),
      onChanged: (v) {
        _values[spec.column] = v;
        if (spec.column == 'C') {
          _values['D'] = monthYear(v);
          _controllers['D']?.text = _values['D']!;
        }
        if (spec.column == 'J') {
          _values['K'] = monthYear(v);
          _controllers['K']?.text = _values['K']!;
        }
        if (spec.column == 'I') {
          _values['B'] = _registrationForCourt(v, _values['C']);
          _controllers['B']?.text = _values['B']!;
        }
        if (spec.column == 'C' || spec.column == 'J') {
          _updateCalculatedFields();
        }
        if (spec.column == 'C' && (_values['I'] ?? '').trim().isNotEmpty) {
          _values['B'] = _registrationForCourt(_values['I']!.trim(), v);
          _controllers['B']?.text = _values['B']!;
        }
        if (spec.column == 'P' && v.trim().isEmpty) {
          _values['P'] = _values['C'] ?? '';
        }
      },
    );
  }

  @override
  void dispose() {
    for (final c in _controllers.values) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Court OCR Scanner'),
        actions: [
          IconButton(tooltip: 'Configure Google Cloud Vision OCR', onPressed: _configureCloudVision, icon: const Icon(Icons.document_scanner_outlined)),
          IconButton(tooltip: 'Manage W assignees', onPressed: _manageAssignees, icon: const Icon(Icons.settings)),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: FilledButton.icon(
                  onPressed: _busy ? null : () => _scan(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt), label: const Text('Scan document'),
                )),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _scan(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library), label: const Text('Choose image'),
                )),
              ]),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _chooseWorkbook,
                icon: const Icon(Icons.file_open),
                label: Text(_workbookPath == null ? 'Open GH.xlsx workbook' : 'Workbook: $_workbookPath'),
              ),
              const SizedBox(height: 8),
              if (_busy) const LinearProgressIndicator(),
              Text(_status, style: Theme.of(context).textTheme.bodySmall),
              if (_rawText.isNotEmpty)
                Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Raw OCR text'),
                      content: SizedBox(width: 500, child: SingleChildScrollView(child: SelectableText(_rawText))),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
                    ),
                  ),
                  icon: const Icon(Icons.text_snippet_outlined), label: const Text('View scanned text'),
                )),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
              children: [
                Text('Review and edit before saving', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text('Review all extracted fields before saving. Existing Sheet1 columns, other sheets, and prior records are preserved. Daily serial and court register numbers restart/count by receipt date. Dates use DD/MM/YYYY.'),
                const SizedBox(height: 12),
                ...fieldSpecs.map((spec) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildField(spec),
                )),
                const SizedBox(height: 4),
                FilledButton.icon(
                  onPressed: _busy ? null : _saveExcel,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save / Export Excel'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      for (final key in _values.keys) { _values[key] = ''; }
                      _values['H'] = 'SUMMON';
                      _values['L'] = 'NO';
                      _values['N'] = 'NOT UPDATED';
                      _values['O'] = 'NONE';
                      _values['V'] = 'NOT MENTIONED';
                      _values['W'] = 'UNASSIGNED';
                      _values['X'] = 'PENDING';
                      _values['AB'] = 'NO';
                      _values['AE'] = 'PRIVATE PERSON';
                      _values['AF'] = 'WITHIN DISTRICT';
                      _values['AM'] = 'ACCUSED';
                      _values['AV'] = 'NONE';
                      _setDefaultDates();
                      _updateCalculatedFields();
                      _rawText = '';
                      _status = 'Form cleared. Ready for the next document.';
                    });
                  },
                  icon: const Icon(Icons.restart_alt), label: const Text('Clear form for next document'),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
