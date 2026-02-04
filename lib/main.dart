import 'package:flutter/material.dart';
import 'dart:async';
import 'esp32_service.dart';

void main() => runApp(const WheelProApp());

class WheelProApp extends StatelessWidget {
  const WheelProApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121417),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyanAccent, brightness: Brightness.dark),
      ),
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  final List<SessionResult> _history = [];
  
  // Settings State
  int _testDuration = 10;
  bool _forceMock = false;

  @override
  Widget build(BuildContext context) {
    final List<Widget> _screens = [
      ProDashboard(
        duration: _testDuration,
        forceMock: _forceMock,
        onResult: (res) => setState(() => _history.insert(0, res)),
      ),
      ProgressScreen(history: _history),
      SettingsScreen(
        duration: _testDuration,
        forceMock: _forceMock,
        onDurationChanged: (v) => setState(() => _testDuration = v),
        onMockChanged: (v) => setState(() => _forceMock = v),
      ),
    ];

    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: Colors.cyanAccent,
        backgroundColor: const Color(0xFF1E2127),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.bolt), label: "Test"),
          BottomNavigationBarItem(icon: Icon(Icons.analytics), label: "History"),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Settings"),
        ],
      ),
    );
  }
}

class ProDashboard extends StatefulWidget {
  final int duration;
  final bool forceMock;
  final Function(SessionResult) onResult;
  const ProDashboard({super.key, required this.onResult, required this.duration, required this.forceMock});

  @override
  State<ProDashboard> createState() => _ProDashboardState();
}

class _ProDashboardState extends State<ProDashboard> {
  final Esp32Service esp = Esp32Service();
  Maneuver? selectedManeuver;
  int countdown = 0;
  int timerLeft = 0;
  bool isTesting = false;
  int? lastScore;
  List<WheelData> sessionData = [];

  final List<Maneuver> maneuvers = [
    Maneuver(name: "Straight Line", instructions: "Drive straight for the duration."),
    Maneuver(name: "360° Pivot", instructions: "Spin on the spot.", isPivot: true),
  ];

  @override
  void initState() { super.initState(); esp.start(); }

  void startSequence() {
    setState(() { countdown = 3; lastScore = null; });
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (countdown > 1) setState(() => countdown--);
      else { t.cancel(); runTest(); }
    });
  }

  void runTest() {
    setState(() { countdown = 0; isTesting = true; timerLeft = widget.duration; sessionData.clear(); });
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (timerLeft > 1) setState(() => timerLeft--);
      else { t.cancel(); finishTest(); }
    });
  }

  void finishTest() {
    double scoreValue = 0;
    if (sessionData.isNotEmpty) {
      if (selectedManeuver!.isPivot) {
        double mirrorError = sessionData.map((d) => (d.rpmL - d.rpmR).abs()).reduce((a, b) => a + b) / sessionData.length;
        scoreValue = (100 - (mirrorError * 4)).clamp(0, 100);
      } else {
        double drift = sessionData.map((d) => d.rpmDiff).reduce((a, b) => a + b) / sessionData.length;
        scoreValue = (100 - (drift * 6)).clamp(0, 100);
      }
    }
    int finalScore = scoreValue.toInt();
    widget.onResult(SessionResult(selectedManeuver!.name, finalScore, DateTime.now()));
    setState(() { isTesting = false; timerLeft = 0; lastScore = finalScore; });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WheelData>(
      stream: esp.stream,
      builder: (context, snapshot) {
        // Use logic from widget settings
        final d = (widget.forceMock) ? WheelData.mock(moving: isTesting) : (snapshot.data ?? WheelData.mock());
        if (isTesting) sessionData.add(d);

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (countdown > 0) ...[
                  const Text("GET READY", style: TextStyle(letterSpacing: 4, color: Colors.grey)),
                  Text("$countdown", style: const TextStyle(fontSize: 140, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                ] else if (isTesting) ...[
                  _buildActiveTestView(d),
                ] else if (lastScore != null) ...[
                  _buildResultView(),
                ] else ...[
                  _buildManeuverSelection(),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveTestView(WheelData d) {
    return Column(
      children: [
        Text("${timerLeft}s", style: const TextStyle(fontSize: 80, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
        const SizedBox(height: 20),
        GridView.count(
          shrinkWrap: true,
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.4,
          children: [
            _liveMetricTile("Right RPM", d.rpmR.toStringAsFixed(2)),
            _liveMetricTile("Left RPM", d.rpmL.toStringAsFixed(2)),
            _liveMetricTile("Speed m/s", d.speedMS.toStringAsFixed(2)),
            _liveMetricTile("Diff", d.rpmDiff.toStringAsFixed(2)),
          ],
        ),
      ],
    );
  }

  Widget _liveMetricTile(String label, String value) => Container(
    decoration: BoxDecoration(color: const Color(0xFF1E2127), borderRadius: BorderRadius.circular(15)),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    ]),
  );

  Widget _buildResultView() => Column(
    children: [
      const Text("RESULT", style: TextStyle(letterSpacing: 4, color: Colors.grey)),
      Text("$lastScore%", style: const TextStyle(fontSize: 120, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
      const SizedBox(height: 40),
      ElevatedButton(onPressed: () => setState(() => lastScore = null), child: const Text("TRY AGAIN")),
    ],
  );

  Widget _buildManeuverSelection() => Column(
    children: [
      const Text("SELECT MANEUVER", style: TextStyle(letterSpacing: 2, color: Colors.grey)),
      const SizedBox(height: 20),
      ...maneuvers.map((m) => ListTile(
        title: Text(m.name, textAlign: TextAlign.center),
        onTap: () => setState(() => selectedManeuver = m),
        tileColor: selectedManeuver == m ? Colors.cyanAccent.withOpacity(0.1) : null,
      )),
      if (selectedManeuver != null) ...[
        const SizedBox(height: 20),
        Text(selectedManeuver!.instructions, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: startSequence, child: const Text("START")),
      ]
    ],
  );
}

// --- TAB 2: HISTORY ---
class ProgressScreen extends StatelessWidget {
  final List<SessionResult> history;
  const ProgressScreen({super.key, required this.history});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("History")),
      body: history.isEmpty ? const Center(child: Text("No data.")) : ListView.builder(
        itemCount: history.length,
        itemBuilder: (context, index) => ListTile(
          title: Text(history[index].name),
          trailing: Text("${history[index].score}%"),
        ),
      ),
    );
  }
}

// --- TAB 3: SETTINGS ---
class SettingsScreen extends StatelessWidget {
  final int duration;
  final bool forceMock;
  final Function(int) onDurationChanged;
  final Function(bool) onMockChanged;

  const SettingsScreen({super.key, required this.duration, required this.forceMock, required this.onDurationChanged, required this.onMockChanged});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text("Test Configuration", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
          ListTile(
            title: const Text("Maneuver Duration"),
            subtitle: Text("$duration seconds"),
            trailing: SizedBox(
              width: 150,
              child: Slider(
                value: duration.toDouble(),
                min: 5, max: 30, divisions: 5,
                onChanged: (v) => onDurationChanged(v.toInt()),
              ),
            ),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text("Force Demo Mode"),
            subtitle: const Text("Uses mock data instead of ESP32"),
            value: forceMock,
            onChanged: onMockChanged,
          ),
        ],
      ),
    );
  }
}