import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'dart:math';

// ==========================================
// 1. DATA MODELS & CONSTANTS
// ==========================================

const int kTotalMonths = 26;
const int kDaysPerMonth = 14;
// Month names as requested (using Latin ordinal names)
const List<String> kMonthNames = [
  "Primus", "Secundus", "Tertius", "Quartus", "Quintus", "Sextus",
  "Septimus", "Octavus", "Nonus", "Decimus", "Undecimus", "Duodecimus",
  "Tertius Decimus", "Quartus Decimus", "Quintus Decimus", "Sextus Decimus",
  "Septimus Decimus", "Octavus Decimus", "Nonus Decimus", "Vicesimus",
  "Vicesimus Primus", "Vicesimus Secundus", "Vicesimus Tertius", "Vicesimus Quartus",
  "Vicesimus Quintus", "Vicesimus Sextus"
];

class ChronoDate {
  final int monthIndex; // 0 to 25
  final int dayIndex;   // 0 to 13 (Day 1 to 14)
  final bool isHyperday;

  ChronoDate({
    required this.monthIndex,
    required this.dayIndex,
    this.isHyperday = false,
  });

  // Unique ID for persistence keys
  String get id => isHyperday ? "hyperday" : "m${monthIndex}_d$dayIndex";

  String get displayName {
    if (isHyperday) return "HYPERDAY";
    return "${kMonthNames[monthIndex]} - Day ${dayIndex + 1}";
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChronoDate &&
        other.monthIndex == monthIndex &&
        other.dayIndex == dayIndex &&
        other.isHyperday == isHyperday;
  }

  @override
  int get hashCode => Object.hash(monthIndex, dayIndex, isHyperday);
}

// ==========================================
// 2. STATE MANAGEMENT (PROVIDER)
// ==========================================

class ChronoProvider with ChangeNotifier {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  SharedPreferences? _prefs;

  // Day ID -> Progress (0-100)
  Map<String, double> _progressMap = {};

  // For chart data
  List<double> _currentMonthRadarData = List.filled(6, 0.0);

  ChronoProvider() {
    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    await _initNotifications();
    _loadData();
  }

  Future<void> _initNotifications() async {
    tz_data.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap
      },
    );

    // Create channels
    await _createNotificationChannels();
  }

  Future<void> _createNotificationChannels() async {
    const AndroidNotificationChannel highPriorityChannel = AndroidNotificationChannel(
      'high_importance_channel', // id
      'High Importance Notifications', // title
      description: 'This channel is used for important notifications.', // description
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    );

     const AndroidNotificationChannel alarmChannel = AndroidNotificationChannel(
      'alarm_channel', // id
      'Alarm Notifications', // title
      description: 'Channel for alarms', // description
      importance: Importance.high,
      playSound: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(highPriorityChannel);

     await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(alarmChannel);
  }


  void _loadData() {
    if (_prefs == null) return;
    final keys = _prefs!.getKeys();
    for (String key in keys) {
      if (key.startsWith("m") || key == "hyperday") {
         // Assuming keys are like m0_d1_progress
         if (key.endsWith("_progress")) {
            final id = key.replaceAll("_progress", "");
            _progressMap[id] = _prefs!.getDouble(key) ?? 0.0;
         }
      }
    }
    _calculateChartData();
    notifyListeners();
  }

  double getProgress(String id) {
    return _progressMap[id] ?? 0.0;
  }

  Future<void> setProgress(String id, double value) async {
    _progressMap[id] = value;
    await _prefs?.setDouble("${id}_progress", value);
    _calculateChartData();
    notifyListeners();
  }

  // --- Chart Logic ---
  // We have 14 days in a month. Radar chart has 6 axes.
  // We map:
  // Axis 1: Days 1-2
  // Axis 2: Days 3-4
  // Axis 3: Days 5-6
  // Axis 4: Days 7-8
  // Axis 5: Days 9-11
  // Axis 6: Days 12-14
  void _calculateChartData() {
    // Determine "current month" based on real date or just default to first month for demo?
    // User requirement: "visualize the overall progress of the current month"
    // We need a mapping from Real Date to Chrono Date.

    ChronoDate current = getCurrentChronoDate();
    int mIndex = current.monthIndex;

    List<double> axisSums = List.filled(6, 0.0);
    List<int> axisCounts = [2, 2, 2, 2, 3, 3]; // 14 days total

    // Helper to get progress safely
    double p(int dIndex) => getProgress("m${mIndex}_d$dIndex");

    axisSums[0] = p(0) + p(1);
    axisSums[1] = p(2) + p(3);
    axisSums[2] = p(4) + p(5);
    axisSums[3] = p(6) + p(7);
    axisSums[4] = p(8) + p(9) + p(10);
    axisSums[5] = p(11) + p(12) + p(13);

    for (int i = 0; i < 6; i++) {
      _currentMonthRadarData[i] = axisSums[i] / axisCounts[i]; // Average
    }
  }

  List<double> get currentMonthRadarData => _currentMonthRadarData;

  // --- Date Logic ---
  ChronoDate getCurrentChronoDate() {
    // 26 months * 14 days + 1 = 365 days.
    // Assume Year starts Jan 1.
    final now = DateTime.now();
    final startOfYear = DateTime(now.year, 1, 1);
    final diff = now.difference(startOfYear).inDays; // 0 to 364 (or 365 on leap)

    if (diff >= 364) {
      // Hyperday (Day 365 or 366)
      return ChronoDate(monthIndex: 25, dayIndex: 0, isHyperday: true);
    }

    int totalDays = diff;
    int month = (totalDays / kDaysPerMonth).floor();
    int day = totalDays % kDaysPerMonth;

    // Safety clamp
    if (month >= kTotalMonths) {
       return ChronoDate(monthIndex: 25, dayIndex: 0, isHyperday: true);
    }

    return ChronoDate(monthIndex: month, dayIndex: day);
  }

  // --- Alarm / Notification Logic ---
  Future<void> checkPermissions() async {
    await Permission.notification.request();
    await Permission.scheduleExactAlarm.request();
  }

  Future<void> scheduleReminder(ChronoDate date) async {
    await checkPermissions();
    // Schedule for 9 AM "tomorrow" relative to real world?
    // Or just a demo notification 5 seconds later for testing?
    // For a real calendar app, we'd map ChronoDate back to DateTime.
    // Let's schedule it 5 seconds later for demo purposes.

    await flutterLocalNotificationsPlugin.show(
      date.hashCode,
      'Reminder: ${date.displayName}',
      'Don\'t forget your goals today!',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'default_channel',
          'General Reminders',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  Future<void> scheduleAlarm(ChronoDate date) async {
    await checkPermissions();

    await flutterLocalNotificationsPlugin.zonedSchedule(
      date.hashCode + 1000,
      'Alarm: ${date.displayName}',
      'Time to check in!',
      tz.TZDateTime.now(tz.UTC).add(const Duration(seconds: 10)),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'alarm_channel',
          'Alarm Notifications',
          importance: Importance.high,
          priority: Priority.high,
          fullScreenIntent: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> scheduleUrgentAlarm(ChronoDate date) async {
    await checkPermissions();

    // High priority, potentially overriding DND if channel allows (needs special setup on phone)
    await flutterLocalNotificationsPlugin.zonedSchedule(
      date.hashCode + 2000,
      'URGENT: ${date.displayName}',
      'IMMEDIATE ACTION REQUIRED',
      tz.TZDateTime.now(tz.UTC).add(const Duration(seconds: 5)),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          visibility: NotificationVisibility.public,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}

// ==========================================
// 3. UI IMPLEMENTATION
// ==========================================

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChronoProvider()),
      ],
      child: const ChronoApp(),
    ),
  );
}

class ChronoApp extends StatelessWidget {
  const ChronoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chrono Fort',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF111422),
        primaryColor: const Color(0xFF1337ec),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF1337ec),
          secondary: Color(0xFF7c3aed),
          surface: Color(0xFF191e33),
        ),
        useMaterial3: true,
        fontFamily: 'Manrope', // Ensure font is added or default will be used
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: const [
            Icon(Icons.calendar_month, color: Color(0xFF1337ec)),
            SizedBox(width: 8),
            Text('Chrono Fort', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: const Color(0xFF111422).withOpacity(0.8),
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1337ec).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: const [
                Icon(Icons.today, size: 16, color: Color(0xFF1337ec)),
                SizedBox(width: 4),
                Text('TODAY', style: TextStyle(color: Color(0xFF1337ec), fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          )
        ],
      ),
      body: Column(
        children: [
          // Hexagon Chart Section
          const SizedBox(height: 20),
          SizedBox(
            height: 250,
            child: const HexagonChart(),
          ),
          const SizedBox(height: 20),
          Padding(
             padding: const EdgeInsets.symmetric(horizontal: 16.0),
             child: Row(
               mainAxisAlignment: MainAxisAlignment.spaceBetween,
               children: [
                 const Text("Year Cycle", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                 Text("${kTotalMonths} Months", style: TextStyle(color: Colors.grey[400], fontSize: 12)),
               ],
             ),
          ),
          const SizedBox(height: 10),
          // Scrollable List
          Expanded(
            child: ListView.builder(
              itemCount: kTotalMonths + 1, // +1 for Hyperday
              itemBuilder: (context, index) {
                if (index == kTotalMonths) {
                  return const HyperdayCard();
                }
                return MonthTile(monthIndex: index);
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF191e33).withOpacity(0.9),
        selectedItemColor: const Color(0xFF1337ec),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.calendar_view_month), label: 'Calendar'),
          BottomNavigationBarItem(icon: Icon(Icons.event), label: 'Events'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: const Color(0xFF1337ec),
        tooltip: 'Add Event',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ==========================================
// 4. CHART WIDGET
// ==========================================

class HexagonChart extends StatelessWidget {
  const HexagonChart({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ChronoProvider>(context);
    final data = provider.currentMonthRadarData; // List of 6 doubles

    return RadarChart(
      RadarChartData(
        dataSets: [
          RadarDataSet(
            fillColor: const Color(0xFF1337ec).withOpacity(0.2),
            borderColor: const Color(0xFF1337ec),
            entryRadius: 3,
            dataEntries: data.map((e) => RadarEntry(value: e)).toList(),
            borderWidth: 2,
          ),
        ],
        radarBackgroundColor: Colors.transparent,
        borderData: FlBorderData(show: false),
        radarBorderData: const BorderSide(color: Colors.transparent),
        titlePositionPercentageOffset: 0.1,
        titleTextStyle: const TextStyle(color: Colors.grey, fontSize: 10),
        getTitle: (index, angle) {
          const titles = ['Focus', 'Strength', 'Spirit', 'Intellect', 'Social', 'Rest'];
          return RadarChartTitle(text: titles[index]);
        },
        tickCount: 3,
        ticksTextStyle: const TextStyle(color: Colors.transparent),
        gridBorderData: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
      ),
    );
  }
}

// ==========================================
// 5. MONTH & DAY WIDGETS
// ==========================================

class MonthTile extends StatelessWidget {
  final int monthIndex;

  const MonthTile({super.key, required this.monthIndex});

  @override
  Widget build(BuildContext context) {
    // Check if this is the current month to auto-expand or highlight?
    // For simplicity, just build the tile.

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF191e33),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ExpansionTile(
        title: Text(
          kMonthNames[monthIndex],
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        subtitle: const Text("14 Days", style: TextStyle(fontSize: 10, color: Colors.grey)),
        leading: Icon(Icons.circle, size: 12, color: Colors.white.withOpacity(0.2)), // Status dot
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: kDaysPerMonth,
              itemBuilder: (context, dayIndex) {
                return DayCell(
                  date: ChronoDate(monthIndex: monthIndex, dayIndex: dayIndex),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class DayCell extends StatelessWidget {
  final ChronoDate date;

  const DayCell({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ChronoProvider>(context);
    final progress = provider.getProgress(date.id);

    Color color;
    if (progress >= 100) {
      color = Colors.greenAccent;
    } else if (progress >= 50) {
      color = Colors.yellowAccent;
    } else {
      color = Colors.white.withOpacity(0.1); // Gray
    }

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          boxShadow: progress >= 50 ? [
            BoxShadow(color: color.withOpacity(0.4), blurRadius: 4, spreadRadius: 1)
          ] : [],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () {
            showDialog(
              context: context,
              builder: (ctx) => DayActionDialog(date: date),
            );
          },
        ),
      ),
    );
  }
}

class HyperdayCard extends StatelessWidget {
  const HyperdayCard({super.key});

  @override
  Widget build(BuildContext context) {
    final date = ChronoDate(monthIndex: 25, dayIndex: 0, isHyperday: true);

    return GestureDetector(
      onTap: () {
         showDialog(
          context: context,
          builder: (ctx) => DayActionDialog(date: date),
        );
      },
      child: Container(
        margin: const EdgeInsets.all(16),
        height: 120,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1337ec), Color(0xFF7c3aed)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: const Color(0xFF1337ec).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Stack(
          children: [
            // Decorative background pattern simulation
            Positioned.fill(
              child: Opacity(
                opacity: 0.1,
                child: Image.network('https://www.transparenttextures.com/patterns/stardust.png',
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => Container(), // Fallback
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.white, size: 32),
                  const SizedBox(height: 8),
                  const Text("HYPERDAY", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  Text("The Time Between Cycles", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 6. DIALOG WIDGET
// ==========================================

class DayActionDialog extends StatefulWidget {
  final ChronoDate date;

  const DayActionDialog({super.key, required this.date});

  @override
  State<DayActionDialog> createState() => _DayActionDialogState();
}

class _DayActionDialogState extends State<DayActionDialog> {
  late double _currentProgress;

  @override
  void initState() {
    super.initState();
    _currentProgress = Provider.of<ChronoProvider>(context, listen: false).getProgress(widget.date.id);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ChronoProvider>(context, listen: false);

    return AlertDialog(
      backgroundColor: const Color(0xFF191e33),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.date.displayName, style: const TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Goal Progress", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 10),
          Row(
            children: [
              Text("0%", style: TextStyle(color: Colors.grey[600], fontSize: 10)),
              Expanded(
                child: Slider(
                  value: _currentProgress,
                  min: 0,
                  max: 100,
                  activeColor: const Color(0xFF1337ec),
                  inactiveColor: Colors.white.withOpacity(0.1),
                  label: '${_currentProgress.toInt()}%',
                  semanticFormatterCallback: (double value) {
                    return '${value.toInt()} percent';
                  },
                  onChanged: (val) {
                    setState(() {
                      _currentProgress = val;
                    });
                  },
                  onChangeEnd: (val) {
                    provider.setProgress(widget.date.id, val);
                  },
                ),
              ),
              Text("100%", style: TextStyle(color: Colors.grey[600], fontSize: 10)),
            ],
          ),
          Text("${_currentProgress.toInt()}%", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 20),
          const Divider(color: Colors.white10),
          const SizedBox(height: 10),
          // Buttons
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.notifications_none),
              label: const Text("Set Reminder"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.05),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                provider.scheduleReminder(widget.date);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reminder Set!")));
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.alarm),
              label: const Text("Set Alarm"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.05),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                provider.scheduleAlarm(widget.date);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Alarm Set!")));
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.warning_amber_rounded),
              label: const Text("URGENT ALARM"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withOpacity(0.2),
                foregroundColor: Colors.redAccent,
              ),
              onPressed: () {
                provider.scheduleUrgentAlarm(widget.date);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("URGENT Alarm Scheduled!")));
              },
            ),
          ),
        ],
      ),
    );
  }
}
