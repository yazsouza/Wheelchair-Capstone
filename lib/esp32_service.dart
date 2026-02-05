import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

class ManeuverStep {
  final String text;
  final String? imagePath; // Path to your local asset image
  ManeuverStep({required this.text, this.imagePath});
}

class Maneuver {
  final String name;
  final List<ManeuverStep> steps; // Grouped steps from the guide
  final bool isPivot;

  Maneuver({required this.name, required this.steps, this.isPivot = false});
}

class SessionResult {
  final String name;
  final int score;
  final DateTime date;
  SessionResult(this.name, this.score, this.date);
}

class WheelData {
  final double rpmR, rpmL, speedMS, rpmDiff;
  final String motion;
  final bool isSimulated;

  const WheelData({
    required this.rpmR, required this.rpmL, required this.speedMS,
    required this.rpmDiff, required this.motion, this.isSimulated = false,
  });

  static double _toDouble(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0;

  factory WheelData.fromJson(Map<String, dynamic> j) {
    return WheelData(
      rpmR: _toDouble(j['rpmR']),
      rpmL: _toDouble(j['rpmL']),
      speedMS: _toDouble(j['speed_m_s']),
      rpmDiff: _toDouble(j['rpm_diff']),
      motion: (j['motion'] ?? 'Stopped').toString(),
    );
  }

  factory WheelData.mock({bool moving = false}) {
    final r = Random();
    double base = moving ? 20.0 : 0.0;
    double l = base + (moving ? r.nextDouble() * 4 : 0);
    double rr = base + (moving ? r.nextDouble() * 4 : 0);
    return WheelData(
      rpmL: l, rpmR: rr, speedMS: (l + rr) * 0.015,
      rpmDiff: (l - rr).abs(), motion: moving ? "Moving" : "Stopped",
      isSimulated: true,
    );
  }
}

class Esp32Service {
  final String baseUrl;
  Esp32Service({this.baseUrl = 'http://192.168.4.1'});

  final StreamController<WheelData> _controller = StreamController<WheelData>.broadcast();
  Stream<WheelData> get stream => _controller.stream;
  Timer? _timer;
  int _failCount = 0;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _poll());
  }

  Future<void> _poll() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/data')).timeout(const Duration(milliseconds: 800));
      if (res.statusCode == 200) {
        _failCount = 0;
        _controller.add(WheelData.fromJson(jsonDecode(res.body)));
      } else { _handleFailure(); }
    } catch (_) { _handleFailure(); }
  }

  void _handleFailure() {
    _failCount++;
    if (_failCount >= 3) _controller.add(WheelData.mock(moving: true));
  }

  void dispose() { _timer?.cancel(); _controller.close(); }
}