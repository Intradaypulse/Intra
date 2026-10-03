import 'package:document_scan/document_scan.dart';

/// Require both elapsed time and fresh stable detections. Skipped frames never
/// trigger capture; reset re-arms the gate after cancellation or a new page.
class ScanCaptureGate {
  ScanCaptureGate({this.hold = const Duration(milliseconds: 1400)});
  final Duration hold;
  final _analyzer = AutoCaptureAnalyzer(
    requiredSteadyFrames: 12, minArea: .15, maxJitter: .025,
  );
  Duration? _since;
  Duration? _lastDetection;
  bool _latched = false;
  DocumentCorners? _last;
  AutoCaptureStatus status = AutoCaptureStatus.searching;

  bool add(DetectionEvent event, Duration now) {
    if (event is DetectionSkipped) return false;
    if (event is! DetectionSuccess) {
      reset();
      return false;
    }
    if (_lastDetection != null && now - _lastDetection! > const Duration(milliseconds: 700)) reset();
    _lastDetection = now;
    final previous = _last;
    final corners = event.corners;
    if (previous != null) {
      final a = [previous.topLeft, previous.topRight, previous.bottomRight, previous.bottomLeft];
      final b = [corners.topLeft, corners.topRight, corners.bottomRight, corners.bottomLeft];
      if (List.generate(4, (i) => (a[i].x - b[i].x).abs() > .025 ||
          (a[i].y - b[i].y).abs() > .025).any((moved) => moved)) reset();
    }
    _last = corners;
    final state = _analyzer.addEvent(event);
    status = state.status == AutoCaptureStatus.ready ? AutoCaptureStatus.detecting : state.status;
    if (state.steadyFrames < 2) _since = now;
    if (!_latched && state.steadyFrames >= 12 &&
        _since != null && now - _since! >= hold) {
      _latched = true;
      status = AutoCaptureStatus.ready;
      return true;
    }
    return false;
  }

  void reset() {
    _analyzer.reset();
    _since = null;
    _lastDetection = null;
    _last = null;
    _latched = false;
    status = AutoCaptureStatus.searching;
  }
}
