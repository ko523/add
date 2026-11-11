import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const SavedCalculatorApp());
}

class SavedCalculatorApp extends StatelessWidget {
  const SavedCalculatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF101114);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '계산기',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB6F36B),
          brightness: Brightness.dark,
          surface: background,
        ),
        fontFamily: 'sans-serif',
      ),
      home: const CalculatorPage(),
    );
  }
}

class Calculation {
  const Calculation({
    required this.expression,
    required this.result,
    required this.createdAt,
  });

  final String expression;
  final String result;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'expression': expression,
        'result': result,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Calculation.fromJson(Map<String, dynamic> json) => Calculation(
        expression: json['expression'] as String,
        result: json['result'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  static const _historyKey = 'calculation_history_v1';
  static const _maxHistoryItems = 100;

  final _storage = SharedPreferencesAsync();
  final List<Calculation> _history = [];
  String _expression = '';
  String? _answer;
  bool _showError = false;
  bool _startFresh = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final stored = await _storage.getString(_historyKey);
      if (stored == null) return;
      final decoded = jsonDecode(stored) as List<dynamic>;
      final loaded = decoded
          .map((item) => Calculation.fromJson(item as Map<String, dynamic>))
          .toList();
      if (mounted) setState(() => _history.addAll(loaded));
    } on Object {
      // Ignore malformed old data so the calculator remains usable.
    }
  }

  Future<void> _saveHistory() async {
    final json = jsonEncode(_history.map((item) => item.toJson()).toList());
    await _storage.setString(_historyKey, json);
  }

  void _press(String key) {
    setState(() {
      _showError = false;
      if (key == 'AC') {
        _expression = '';
        _answer = null;
        _startFresh = false;
      } else if (key == '⌫') {
        if (_expression.isNotEmpty) {
          _expression = _expression.substring(0, _expression.length - 1);
        }
        _answer = null;
        _startFresh = false;
      } else if (key == '=') {
        _calculate();
      } else if (key == '±') {
        _toggleSign();
      } else if (key == '%') {
        _appendPercent();
      } else if ('+-×÷'.contains(key)) {
        _appendOperator(key);
      } else {
        _appendDigit(key);
      }
    });
  }

  void _appendDigit(String key) {
    if (_startFresh) {
      _expression = '';
      _answer = null;
      _startFresh = false;
    }
    if (key == '.') {
      final currentNumber = RegExp(r'\d*\.?\d*$').firstMatch(_expression)?.group(0) ?? '';
      if (currentNumber.contains('.')) return;
      _expression += currentNumber.isEmpty ? '0.' : '.';
      return;
    }
    _expression += key;
  }

  void _appendOperator(String key) {
    if (_startFresh && _answer != null) {
      _expression = _answer!;
      _answer = null;
      _startFresh = false;
    }
    if (_expression.isEmpty) {
      if (key == '-') _expression = '-';
      return;
    }
    if ('+-×÷'.contains(_expression[_expression.length - 1])) {
      _expression = _expression.substring(0, _expression.length - 1) + key;
    } else {
      _expression += key;
    }
    _answer = null;
    _startFresh = false;
  }

  void _appendPercent() {
    if (_expression.isEmpty) return;
    if (RegExp(r'[0-9)]$').hasMatch(_expression)) _expression += '%';
  }

  void _toggleSign() {
    if (_expression.isEmpty) {
      _expression = '-';
      return;
    }
    final match = RegExp(r'(-?\d*\.?\d+)%?$').firstMatch(_expression);
    if (match == null) return;
    final number = match.group(1)!;
    final toggled = number.startsWith('-') ? number.substring(1) : '-$number';
    _expression = _expression.replaceRange(match.start, match.end, '$toggled${match.group(0)!.endsWith('%') ? '%' : ''}');
  }

  Future<void> _calculate() async {
    if (_expression.trim().isEmpty) return;
    try {
      final value = _ExpressionParser(_expression).parse();
      final result = _formatNumber(value);
      final calculation = Calculation(
        expression: _expression,
        result: result,
        createdAt: DateTime.now(),
      );
      setState(() {
        _answer = result;
        _history.insert(0, calculation);
        if (_history.length > _maxHistoryItems) {
          _history.removeRange(_maxHistoryItems, _history.length);
        }
        _startFresh = true;
      });
      await _saveHistory();
    } on FormatException {
      setState(() {
        _answer = null;
        _showError = true;
      });
    } on Object {
      setState(() => _showError = true);
    }
  }

  String _formatNumber(double value) {
    if (!value.isFinite) throw const FormatException('계산할 수 없는 값입니다.');
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    final precise = value.toStringAsPrecision(10);
    if (!precise.contains('e')) {
      return precise.replaceFirst(RegExp(r'\.?0+$'), '');
    }
    final parts = precise.split('e');
    final mantissa = parts.first.replaceFirst(RegExp(r'\.?0+$'), '');
    return '${mantissa}e${parts.last}';
  }

  Future<void> _clearHistory() async {
    setState(_history.clear);
    await _saveHistory();
  }

  void _openHistory() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1B20),
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 16, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('계산 기록', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                    if (_history.isNotEmpty)
                      TextButton(onPressed: _clearHistory, child: const Text('전체 삭제')),
                    IconButton(
                      tooltip: '닫기',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _history.isEmpty
                    ? const Center(
                        child: Text('아직 계산 기록이 없습니다.', style: TextStyle(color: Colors.white54)),
                      )
                    : ListView.separated(
                        itemCount: _history.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                        itemBuilder: (context, index) {
                          final item = _history[index];
                          return ListTile(
                            title: Text(_displayExpression(item.expression), textAlign: TextAlign.right),
                            subtitle: Text(_formatDate(item.createdAt), textAlign: TextAlign.right),
                            trailing: Text('= ${item.result}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                            onTap: () {
                              setState(() {
                                _expression = item.result;
                                _answer = null;
                                _showError = false;
                                _startFresh = false;
                              });
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}.${two(local.month)}.${two(local.day)}  ${two(local.hour)}:${two(local.minute)}';
  }

  String _displayExpression(String expression) => expression
      .replaceAll('*', '×')
      .replaceAll('/', '÷');

  @override
  Widget build(BuildContext context) {
    final buttons = const [
      ['AC', '±', '%', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '-'],
      ['1', '2', '3', '+'],
      ['⌫', '0', '.', '='],
    ];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('계산기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    onPressed: _openHistory,
                    tooltip: '계산 기록',
                    icon: const Icon(Icons.history_rounded),
                  ),
                ],
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  alignment: Alignment.bottomRight,
                  padding: const EdgeInsets.fromLTRB(8, 20, 8, 26),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _expression.isEmpty ? '0' : _displayExpression(_expression),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 34, color: Colors.white70, fontWeight: FontWeight.w300),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _showError ? '계산할 수 없어요' : (_answer == null ? ' ' : '= $_answer'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 48,
                          color: _showError ? const Color(0xFFFF8178) : const Color(0xFFB6F36B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              for (final row in buttons)
                Expanded(
                  child: Row(
                    children: [
                      for (final key in row)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: _CalculatorButton(
                              label: key,
                              onPressed: () => _press(key),
                              type: _buttonType(key),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  _ButtonType _buttonType(String key) {
    if (key == '=') return _ButtonType.equals;
    if ('÷×-+'.contains(key)) return _ButtonType.operator;
    if (key == 'AC' || key == '±' || key == '%') return _ButtonType.utility;
    return _ButtonType.number;
  }
}

enum _ButtonType { number, utility, operator, equals }

class _CalculatorButton extends StatelessWidget {
  const _CalculatorButton({required this.label, required this.onPressed, required this.type});

  final String label;
  final VoidCallback onPressed;
  final _ButtonType type;

  @override
  Widget build(BuildContext context) {
    final background = switch (type) {
      _ButtonType.number => const Color(0xFF24262C),
      _ButtonType.utility => const Color(0xFF34363D),
      _ButtonType.operator => const Color(0xFF252A20),
      _ButtonType.equals => const Color(0xFFB6F36B),
    };
    final foreground = type == _ButtonType.equals
        ? const Color(0xFF171A12)
        : type == _ButtonType.operator
            ? const Color(0xFFB6F36B)
            : Colors.white;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(24),
          child: Center(
            child: Text(
              label,
              style: TextStyle(fontSize: label == 'AC' ? 21 : 27, color: foreground, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpressionParser {
  _ExpressionParser(String input) : _input = input.replaceAll('×', '*').replaceAll('÷', '/');

  final String _input;
  int _position = 0;

  double parse() {
    final result = _parseExpression();
    _skipSpaces();
    if (_position != _input.length) throw const FormatException('잘못된 수식입니다.');
    return result;
  }

  double _parseExpression() {
    var value = _parseTerm();
    while (true) {
      _skipSpaces();
      if (_take('+')) {
        value += _parseTerm();
      } else if (_take('-')) {
        value -= _parseTerm();
      } else {
        return value;
      }
    }
  }

  double _parseTerm() {
    var value = _parseFactor();
    while (true) {
      _skipSpaces();
      if (_take('*')) {
        value *= _parseFactor();
      } else if (_take('/')) {
        final divisor = _parseFactor();
        if (divisor == 0) throw const FormatException('0으로 나눌 수 없습니다.');
        value /= divisor;
      } else {
        return value;
      }
    }
  }

  double _parseFactor() {
    _skipSpaces();
    var sign = 1.0;
    if (_take('+')) {
      return _parseFactor();
    }
    if (_take('-')) sign = -1;

    double value;
    if (_take('(')) {
      value = _parseExpression();
      _skipSpaces();
      if (!_take(')')) throw const FormatException('괄호가 닫히지 않았습니다.');
    } else {
      value = _parseNumber();
    }

    _skipSpaces();
    while (_take('%')) {
      value /= 100;
      _skipSpaces();
    }
    return sign * value;
  }

  double _parseNumber() {
    _skipSpaces();
    final start = _position;
    var hasDigit = false;
    while (_position < _input.length && _isDigit(_input[_position])) {
      hasDigit = true;
      _position++;
    }
    if (_take('.')) {
      while (_position < _input.length && _isDigit(_input[_position])) {
        hasDigit = true;
        _position++;
      }
    }
    if (!hasDigit) throw const FormatException('숫자를 입력해 주세요.');
    return double.parse(_input.substring(start, _position));
  }

  bool _isDigit(String char) => char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57;

  bool _take(String char) {
    if (_position < _input.length && _input[_position] == char) {
      _position++;
      return true;
    }
    return false;
  }

  void _skipSpaces() {
    while (_position < _input.length && _input[_position].trim().isEmpty) {
      _position++;
    }
  }
}
