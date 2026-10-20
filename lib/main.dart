import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();
  runApp(const SsbFitnessApp());
}

// ---------------------------------------------------------------------------
// NOTIFICATION SERVICE
// ---------------------------------------------------------------------------
Future<void> initNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

Future<void> scheduleSsbAlerts() async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'ssb_cadet_channel',
    'SSB Discipline Alerts',
    importance: Importance.max,
    priority: Priority.high,
  );
  const NotificationDetails notificationDetails =
      NotificationDetails(android: androidDetails);

  // Trigger test alerts / schedule daily discipline triggers
  await flutterLocalNotificationsPlugin.show(
    0,
    '04:00 AM Shift Wakeup',
    'Drink 500ml water immediately. Hydration fuels muscle stamina.',
    notificationDetails,
  );
  await flutterLocalNotificationsPlugin.show(
    1,
    '01:30 PM Shift Over: Gym Bound',
    'Head straight to the gym. Do not go home first. Form begins today.',
    notificationDetails,
  );
}

// ---------------------------------------------------------------------------
// DATABASE HELPER
// ---------------------------------------------------------------------------
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('ssb_tracker.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE weight_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        weight REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE pullup_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        step INTEGER NOT NULL,
        reps INTEGER NOT NULL
      )
    ''');
  }

  Future<int> insertWeight(double weight) async {
    final db = await instance.database;
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return await db.insert('weight_logs', {'date': dateStr, 'weight': weight});
  }

  Future<List<Map<String, dynamic>>> getWeightLogs() async {
    final db = await instance.database;
    return await db.query('weight_logs', orderBy: 'id DESC');
  }

  Future<int> insertPullUpLog(int step, int reps) async {
    final db = await instance.database;
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return await db.insert('pullup_logs', {'date': dateStr, 'step': step, 'reps': reps});
  }

  Future<List<Map<String, dynamic>>> getPullUpLogs() async {
    final db = await instance.database;
    return await db.query('pullup_logs', orderBy: 'id DESC');
  }
}

// ---------------------------------------------------------------------------
// APPLICATION ROOT
// ---------------------------------------------------------------------------
class SsbFitnessApp extends StatelessWidget {
  const SsbFitnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SSB NCC Prep',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121417),
        primaryColor: const Color(0xFF2E7D32),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4CAF50),
          secondary: Color(0xFF81C784),
          surface: Color(0xFF1E2228),
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF1E2228),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final List<Widget> _screens = const [
    DashboardScreen(),
    WorkoutRoutineScreen(),
    PullUpTrackerScreen(),
    WeightLogScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF181B20),
        indicatorColor: const Color(0xFF2E7D32),
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.timer_outlined), label: 'Timer'),
          NavigationDestination(icon: Icon(Icons.fitness_center), label: 'Routines'),
          NavigationDestination(icon: Icon(Icons.trending_up), label: 'Pull-Ups'),
          NavigationDestination(icon: Icon(Icons.monitor_weight_outlined), label: 'Weight'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. DASHBOARD & 90-MIN SEGMENTED TIMER
// ---------------------------------------------------------------------------
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Phase seconds: Warmup (10m), Strength (50m), Cardio (20m), Cooldown (10m)
  final List<int> _phaseDurations = [600, 3000, 1200, 600];
  final List<String> _phaseNames = [
    'Warm-Up & Mobility',
    'Strength Training',
    'Conditioning & Finishers',
    'Cool-Down & Recovery'
  ];
  int _currentPhaseIndex = 0;
  int _secondsLeftInPhase = 600;
  bool _isRunning = false;
  Timer? _timer;

  void _toggleTimer() {
    if (_isRunning) {
      _timer?.cancel();
      setState(() => _isRunning = false);
    } else {
      setState(() => _isRunning = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_secondsLeftInPhase > 0) {
          setState(() => _secondsLeftInPhase--);
        } else {
          if (_currentPhaseIndex < _phaseDurations.length - 1) {
            setState(() {
              _currentPhaseIndex++;
              _secondsLeftInPhase = _phaseDurations[_currentPhaseIndex];
            });
          } else {
            _timer?.cancel();
            setState(() => _isRunning = false);
          }
        }
      });
    }
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _currentPhaseIndex = 0;
      _secondsLeftInPhase = _phaseDurations[0];
    });
  }

  String _formatTime(int totalSeconds) {
    int m = totalSeconds ~/ 60;
    int s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentPhaseName = _phaseNames[_currentPhaseIndex];
    final progress = 1.0 - (_secondsLeftInPhase / _phaseDurations[_currentPhaseIndex]);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SSB Protocol: 90-Min Session'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active),
            tooltip: 'Sync Shift Reminders',
            onPressed: () async {
              await scheduleSsbAlerts();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Shift notifications synced!')),
                );
              }
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                child: Column(
                  children: [
                    Text(
                      'CURRENT STAGE',
                      style: TextStyle(letterSpacing: 1.5, color: Colors.grey[400], fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      currentPhaseName,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF81C784)),
                    ),
                    const SizedBox(height: 24),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 200,
                          height: 200,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 10,
                            backgroundColor: Colors.white10,
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
                          ),
                        ),
                        Text(
                          _formatTime(_secondsLeftInPhase),
                          style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _toggleTimer,
                          icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow),
                          label: Text(_isRunning ? 'Pause' : 'Start Stage'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: _resetTimer,
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Discipline Directives', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Divider(color: Colors.white10),
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.alarm, color: Colors.amber),
                      title: Text('Shift Finish at 01:30 PM'),
                      subtitle: Text('Directly to the gym. No couch stops.'),
                    ),
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.water_drop, color: Colors.lightBlue),
                      title: Text('1.0L Gym Hydration'),
                      subtitle: Text('Maintain steady water intake across the 90 minutes.'),
                    ),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. 5-DAY SPLIT ROUTINES
// ---------------------------------------------------------------------------
class WorkoutRoutineScreen extends StatelessWidget {
  const WorkoutRoutineScreen({super.key});

  final List<Map<String, dynamic>> routines = const [
    {
      'day': 'Monday: Chest & Triceps (Push)',
      'exercises': [
        'Bench Press (Barbell/DB): 4 sets × 10–12 reps',
        'Incline Dumbbell Press: 3 sets × 12 reps',
        'Chest Flyes (Cable/DB): 3 sets × 15 reps',
        'Tricep Overhead Extension: 3 sets × 12 reps',
        'Tricep Pushdowns (Cable): 3 sets × 15 reps',
        'Finisher: Incline Treadmill Walk (20m, 8-10 incline, 5 km/h)'
      ]
    },
    {
      'day': 'Tuesday: Back & Biceps (Pull)',
      'exercises': [
        'Lat Pulldowns: 4 sets × 12 reps (Heavy overload)',
        'Seated Cable Rows: 4 sets × 12 reps',
        'Hyperextensions (Lower Back): 3 sets × 15 reps',
        'Bicep Dumbbell Curls: 3 sets × 12 reps',
        'Hammer Curls: 3 sets × 12 reps',
        'Progression: 3 sets × 10 Scapular Pull-ups',
        'Finisher: Steady Rower or Cycling (20m)'
      ]
    },
    {
      'day': 'Wednesday: Legs & SSB Core',
      'exercises': [
        'Goblet or Barbell Squats: 4 sets × 12 reps',
        'Lunges: 3 sets × 12 reps per leg',
        'Leg Press or Extensions: 3 sets × 15 reps',
        'Plank: 3 sets × 1 min hold',
        'Hanging Leg Raises: 3 sets × 15–20 reps',
        'Finisher: Stair Climber / Stepper (20m)'
      ]
    },
    {
      'day': 'Thursday: Shoulders & Abs',
      'exercises': [
        'Overhead DB Press: 4 sets × 10–12 reps',
        'DB Lateral Raises: 4 sets × 15 reps',
        'Face Pulls or Rear Flyes: 3 sets × 15 reps',
        'Bicycle Crunches: 3 sets × 20 reps',
        'Russian Twists: 3 sets × 20 reps',
        'Finisher: Incline Treadmill Walk (20m)'
      ]
    },
    {
      'day': 'Friday: SSB Stamina & Full Body',
      'exercises': [
        'Strict Push-ups: 4 sets × 15–20 reps (chest to floor)',
        'Negative Pull-ups: 4 sets × 5 reps (5-sec descent)',
        'Inverted Rows (Smith Bar): 3 sets × 10 reps',
        'Bodyweight Squats: 4 sets × 25 reps',
        'Finisher: HIIT Treadmill (1m sprint / 1m walk, 20m)'
      ]
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SSB 5-Day Split'), backgroundColor: Colors.transparent),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: routines.length,
        itemBuilder: (context, index) {
          final item = routines[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              title: Text(item['day'], style: const TextStyle(fontWeight: FontWeight.bold)),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: (item['exercises'] as List<String>)
                        .map((ex) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('• ', style: TextStyle(color: Color(0xFF4CAF50))),
                                  Expanded(child: Text(ex)),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. PULL-UP PROGRESSION BOARD
// ---------------------------------------------------------------------------
class PullUpTrackerScreen extends StatefulWidget {
  const PullUpTrackerScreen({super.key});

  @override
  State<PullUpTrackerScreen> createState() => _PullUpTrackerScreenState();
}

class _PullUpTrackerScreenState extends State<PullUpTrackerScreen> {
  int _selectedStep = 1;
  final TextEditingController _repsController = TextEditingController();
  List<Map<String, dynamic>> _logs = [];

  final List<String> _stepTitles = [
    'Step 1: Scapular Pull-ups (Target: 3 × 10 reps)',
    'Step 2: Lat Pulldown / Cable Rows Overload',
    'Step 3: Negative Pull-ups (Target: 4 × 5, 5s descent)',
    'SSB Directives: Clean Dead-Hang Unassisted (Target: 6-10)'
  ];

  @override
  void initState() {
    super.initState();
    _refreshLogs();
  }

  void _refreshLogs() async {
    final data = await DatabaseHelper.instance.getPullUpLogs();
    setState(() => _logs = data);
  }

  void _submitLog() async {
    final reps = int.tryParse(_repsController.text);
    if (reps != null && reps > 0) {
      await DatabaseHelper.instance.insertPullUpLog(_selectedStep, reps);
      _repsController.clear();
      _refreshLogs();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pull-Up Ladder'), backgroundColor: Colors.transparent),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Select Training Phase', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButton<int>(
                      isExpanded: true,
                      value: _selectedStep,
                      items: [1, 2, 3, 4]
                          .map((val) => DropdownMenuItem(
                                value: val,
                                child: Text(_stepTitles[val - 1], style: const TextStyle(fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (val) => setState(() => _selectedStep = val!),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _repsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Completed Reps / Sets Completed',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                        onPressed: _submitLog,
                        child: const Text('Record Pull-Up Session'),
                      ),
                    )
      
