import 'package:flutter/material.dart';
import 'package:flip_card/flip_card.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'dart:convert';
import 'dart:ui';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const MyApp());
}

// РЕЦЕПТ УСПЕХА: Игнорирование скроллбаров Windows
class NoScrollbarBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Cards',
      scrollBehavior: NoScrollbarBehavior(),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A237E),
          primary: const Color(0xFF1A237E),
          secondary: Colors.amber,
        ),
  cardTheme: CardThemeData( // Используем CardThemeData вместо CardTheme
  elevation: 10.0, // Добавьте .0, чтобы явно указать double
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(24),
  ),
),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A237E),
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
      ),
      home: const QuizScreen(),
    );
  }
}

// --- МОДЕЛЬ ДАННЫХ ---
class TestCard {
  final int? id;
  final String question;
  final List<String> options;
  final int correctIndex;

  TestCard({this.id, required this.question, required this.options, required this.correctIndex});

  Map<String, dynamic> toMap() => {
        'question': question,
        'options': jsonEncode(options),
        'correct_index': correctIndex,
      };

  factory TestCard.fromMap(Map<String, dynamic> map) => TestCard(
        id: map['id'],
        question: map['question'],
        options: List<String>.from(jsonDecode(map['options'])),
        correctIndex: map['correct_index'],
      );
}

// --- БАЗА ДАННЫХ ---
class DbHelper {
  static Database? _db;
  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  Future<Database> _init() async {
    String path = p.join(await getDatabasesPath(), 'smart_cards_v1.db');
    return await openDatabase(path, version: 1, onCreate: (db, v) async {
      await db.execute('CREATE TABLE quiz(id INTEGER PRIMARY KEY AUTOINCREMENT, question TEXT, options TEXT, correct_index INTEGER)');
    });
  }

  Future<List<TestCard>> getCards() async {
    final db = await database;
    final res = await db.query('quiz');
    return res.map((m) => TestCard.fromMap(m)).toList();
  }

  Future<void> add(TestCard c) async => (await database).insert('quiz', c.toMap());
  Future<void> update(TestCard c) async => (await database).update('quiz', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
  Future<void> delete(int id) async => (await database).delete('quiz', where: 'id = ?', whereArgs: [id]);
}

// --- ЭКРАН ВИКТОРИНЫ ---
class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final ValueNotifier<List<TestCard>> _cardsNotifier = ValueNotifier([]);
  final Map<int, int> _answers = {};
  int _correct = 0, _wrong = 0;

  @override
  void initState() { super.initState(); _refresh(); }

  void _refresh() async {
    _cardsNotifier.value = await DbHelper().getCards();
    setState(() { _answers.clear(); _correct = 0; _wrong = 0; });
  }

  void _onSelect(int cardIdx, int optIdx, int correctIdx) {
    if (_answers.containsKey(cardIdx)) return;
    setState(() {
      _answers[cardIdx] = optIdx;
      if (optIdx == correctIdx) {
        _correct++;
      } else {
        _wrong++;
      }
    });
    if (_answers.length == _cardsNotifier.value.length) _showFinishDialog();
  }

  void _showFinishDialog() {
    double score = _cardsNotifier.value.isEmpty ? 0 : (_correct / _cardsNotifier.value.length) * 5;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text("Тест завершен! 🏆"),
      content: Text("Оценка: ${score.toStringAsFixed(1)}\nВерно: $_correct | Ошибок: $_wrong"),
      actions: [ElevatedButton(onPressed: () { Navigator.pop(ctx); _refresh(); }, child: const Text("Повторить"))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Text("Smart Cards: $_correct / $_wrong"),
        actions: [
          IconButton(icon: const Icon(Icons.dashboard_customize), onPressed: _openEditor),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) => true,
        child: ValueListenableBuilder<List<TestCard>>(
          valueListenable: _cardsNotifier,
          builder: (context, cards, _) {
            if (cards.isEmpty) return const Center(child: Text("БД пуста. Перейдите в редактор."));
            return PageView.builder(
              itemCount: cards.length,
              controller: PageController(viewportFraction: 0.88),
              itemBuilder: (context, i) => _buildFlipCard(cards[i], i),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFlipCard(TestCard card, int index) {
    bool answered = _answers.containsKey(index);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 580, maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
          child: FlipCard(
            flipOnTouch: answered,
            front: _buildFront(card, index),
            back: _buildBack(card),
          ),
        ),
      ),
    );
  }

  Widget _buildFront(TestCard card, int index) {
    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white, Colors.blue.shade50]),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text("ВОПРОС ${index + 1}", style: TextStyle(color: Colors.indigo.withOpacity(0.4), letterSpacing: 2, fontWeight: FontWeight.bold, fontSize: 11)),
            const SizedBox(height: 20),
            Text(card.question, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF2C3E50))),
            const Spacer(),
            ...List.generate(card.options.length, (idx) => _buildOptionWidget(index, idx, card.correctIndex, card.options[idx])),
          ],
        ),
      ),
    );
  }

  Widget _buildBack(TestCard card) {
    return Card(
      color: const Color(0xFF1A237E),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.stars, color: Colors.amber, size: 70),
            const SizedBox(height: 20),
            const Text("ВЕРНЫЙ ОТВЕТ:", style: TextStyle(color: Colors.white60, letterSpacing: 2)),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(card.options[card.correctIndex], textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionWidget(int cardIdx, int optIdx, int correctIdx, String text) {
    bool selected = _answers[cardIdx] == optIdx;
    bool isCorrect = optIdx == correctIdx;

    Color bgColor = Colors.white;
    Color textColor = Colors.black87;

    if (selected) {
      bgColor = isCorrect ? Colors.green.shade600 : Colors.red.shade600;
      textColor = Colors.white;
    }

    return GestureDetector(
      onTap: () => _onSelect(cardIdx, optIdx, correctIdx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? Colors.transparent : Colors.indigo.withOpacity(0.1)),
          boxShadow: selected ? [BoxShadow(color: bgColor.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))] : [],
        ),
        child: Text(text, style: TextStyle(color: textColor, fontSize: 16, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  void _openEditor() async {
    await Navigator.push(context, MaterialPageRoute(builder: (c) => const EditorScreen()));
    _refresh();
  }
}

// --- ЭКРАН РЕДАКТОРА ---
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  List<TestCard> _list = [];
  @override
  void initState() { super.initState(); _load(); }
  void _load() async {
    final data = await DbHelper().getCards();
    setState(() => _list = data);
  }

  void _showForm([TestCard? card]) {
    final qC = TextEditingController(text: card?.question);
    final oC = List.generate(4, (i) => TextEditingController(text: card != null ? card.options[i] : ''));
    int localCorrect = card?.correctIndex ?? 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(card == null ? "Создать карту" : "Редактировать"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: qC, decoration: const InputDecoration(labelText: "Вопрос")),
                const SizedBox(height: 15),
                ...List.generate(4, (i) => RadioListTile<int>(
                  contentPadding: EdgeInsets.zero,
                  title: TextField(controller: oC[i], decoration: InputDecoration(hintText: "Вариант ${i + 1}")),
                  value: i,
                  groupValue: localCorrect,
                  onChanged: (val) => setDialogState(() => localCorrect = val!),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Отмена")),
            ElevatedButton(
              onPressed: () async {
                final newCard = TestCard(id: card?.id, question: qC.text, options: oC.map((e) => e.text).toList(), correctIndex: localCorrect);
                card == null ? await DbHelper().add(newCard) : await DbHelper().update(newCard);
                Navigator.pop(ctx); _load();
              },
              child: const Text("Сохранить"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("База вопросов")),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _showForm(), label: const Text("Добавить"), icon: const Icon(Icons.add)),
      body: ListView.builder(
        itemCount: _list.length,
        padding: const EdgeInsets.all(10),
        itemBuilder: (context, i) => Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            title: Text(_list[i].question, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("Ответ: ${_list[i].options[_list[i].correctIndex]}", style: const TextStyle(color: Colors.green)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.edit, color: Colors.indigo), onPressed: () => _showForm(_list[i])),
                IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () async { await DbHelper().delete(_list[i].id!); _load(); }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
