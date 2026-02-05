import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart'; 
import 'esp32_service.dart';

void main() => runApp(const WheelProApp());

class WheelProApp extends StatelessWidget {
  const WheelProApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // ACCESSIBILITY: High-contrast Light Theme for outdoor visibility
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
          primary: Colors.blue.shade900,
        ),
        // ACCESSIBILITY: Larger default text for easier reading
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 18, color: Colors.black),
          bodyMedium: TextStyle(fontSize: 16, color: Colors.black87),
          headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black),
        ),
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
  int _testDuration = 10;
  bool _forceMock = false;

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
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
      body: screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: Colors.blue.shade900,
        unselectedItemColor: Colors.grey.shade600,
        backgroundColor: Colors.grey.shade100,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.bolt, size: 28), label: "Test"),
          BottomNavigationBarItem(icon: Icon(Icons.history, size: 28), label: "History"),
          BottomNavigationBarItem(icon: Icon(Icons.settings, size: 28), label: "Settings"),
        ],
      ),
    );
  }
}

// --- TAB 1: DASHBOARD ---
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
    Maneuver(
      name: "Straight Line", 
      steps: [
        ManeuverStep(text: "Lean slightly forward for stability.", imagePath: "assets/images/wheeling_forward.png"),
        ManeuverStep(text: "Use long, smooth strokes on the handrims."),
        ManeuverStep(text: "Look 5 meters ahead to stay straight."),
      ]
    ),
    Maneuver(
      name: "360° Pivot", 
      isPivot: true,
      steps: [
        ManeuverStep(text: "Pull one handrim back while pushing the other forward.", imagePath: "assets/images/wheeling_on_spot.png"),
        ManeuverStep(text: "Keep the wheelchair within its own length."),
      ]
    ),
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
        double symmetry = sessionData.map((d) => (d.rpmL - d.rpmR).abs()).reduce((a, b) => a + b) / sessionData.length;
        scoreValue = (100 - (symmetry * 4)).clamp(0, 100);
      } else {
        double drift = sessionData.map((d) => d.rpmDiff).reduce((a, b) => a + b) / sessionData.length;
        scoreValue = (100 - (drift * 6)).clamp(0, 100);
      }
    }
    widget.onResult(SessionResult(selectedManeuver!.name, scoreValue.toInt(), DateTime.now()));
    setState(() { isTesting = false; timerLeft = 0; lastScore = scoreValue.toInt(); });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WheelData>(
      stream: esp.stream,
      builder: (context, snapshot) {
        final d = (widget.forceMock) ? WheelData.mock(moving: isTesting) : (snapshot.data ?? WheelData.mock());
        if (isTesting) sessionData.add(d);

        return SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (countdown > 0) _buildCountdown()
                  else if (isTesting) _buildActiveTest(d)
                  else if (lastScore != null) _buildResultView()
                  else _buildSelectionView(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCountdown() => Text("$countdown", style: TextStyle(fontSize: 160, fontWeight: FontWeight.bold, color: Colors.blue.shade900));

  Widget _buildActiveTest(WheelData d) => Column(
    children: [
      Text("${timerLeft}s", style: const TextStyle(fontSize: 80, fontWeight: FontWeight.bold)),
      const SizedBox(height: 30),
      GridView.count(
        shrinkWrap: true, crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 1.2,
        children: [
          _tile("Left RPM", d.rpmL.toStringAsFixed(1)), _tile("Right RPM", d.rpmR.toStringAsFixed(1)),
          _tile("Speed m/s", d.speedMS.toStringAsFixed(2)), _tile("Difference", d.rpmDiff.toStringAsFixed(1)),
        ],
      ),
    ],
  );

  Widget _tile(String l, String v) => Container(
    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.blue.shade100)),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(l, style: const TextStyle(fontSize: 14, color: Colors.black54)),
      Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
    ]),
  );

  Widget _buildResultView() => Column(
    children: [
      const Text("SCORE", style: TextStyle(fontSize: 20, letterSpacing: 2)),
      Text("$lastScore%", style: TextStyle(fontSize: 140, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
      const SizedBox(height: 40),
      SizedBox(
        width: 200, height: 60,
        child: ElevatedButton(onPressed: () => setState(() => lastScore = null), child: const Text("FINISH", style: TextStyle(fontSize: 18))),
      ),
    ],
  );

  Widget _buildSelectionView() => Column(
    children: [
      const Text("SELECT TRIAL", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 20),
      ...maneuvers.map((m) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          tileColor: selectedManeuver == m ? Colors.blue.shade100 : Colors.grey.shade100,
          title: Text(m.name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
          onTap: () => setState(() => selectedManeuver = m),
        ),
      )),
      if (selectedManeuver != null) _buildInstructions(),
    ],
  );

  Widget _buildInstructions() {
    final primaryStep = selectedManeuver!.steps.firstWhere((s) => s.imagePath != null, orElse: () => selectedManeuver!.steps.first);

    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade300)),
      child: Column(
        children: [
          if (primaryStep.imagePath != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.asset(primaryStep.imagePath!, fit: BoxFit.contain),
              ),
            ),
          Text(selectedManeuver!.steps.map((s) => "• ${s.text}").join("\n\n"), style: const TextStyle(fontSize: 16, height: 1.4)),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity, height: 60,
            child: ElevatedButton(
              onPressed: startSequence, 
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade900, foregroundColor: Colors.white),
              child: const Text("START TRIAL", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

// --- TAB 2: HISTORY ---
class ProgressScreen extends StatelessWidget {
  final List<SessionResult> history;
  const ProgressScreen({super.key, required this.history});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Performance History"), backgroundColor: Colors.white, elevation: 0),
      body: history.isEmpty 
        ? const Center(child: Text("No trials recorded yet.")) 
        : ListView.builder(
            itemCount: history.length,
            itemBuilder: (context, index) {
              final res = history[index];
              return ListTile(
                leading: CircleAvatar(backgroundColor: Colors.blue.shade900, child: Text("${res.score}", style: const TextStyle(color: Colors.white))),
                title: Text(res.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(DateFormat('MMM d, yyyy • HH:mm').format(res.date)),
              );
            },
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
        padding: const EdgeInsets.all(24),
        children: [
          const Text("Test Configuration", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Text("Sensing Duration: $duration seconds"),
          Slider(value: duration.toDouble(), min: 5, max: 20, divisions: 3, onChanged: (v) => onDurationChanged(v.toInt())),
          const Divider(height: 40),
          SwitchListTile(
            title: const Text("Demo Mode"),
            subtitle: const Text("Simulate movement without ESP32 connection"),
            value: forceMock, onChanged: onMockChanged,
          ),
        ],
      ),
    );
  }
}