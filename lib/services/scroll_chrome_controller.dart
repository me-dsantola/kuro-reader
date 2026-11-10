import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

/// Intent/distance hysteresis avoids flickering chrome and ignores jumpTo.
class ScrollChromeController extends ChangeNotifier {
  bool _visible = true;
  bool _userScrolling = false;
  double _travel = 0;
  int _direction = 0;
  bool get visible => _visible;

  void show() {
    _travel = 0;
    _direction = 0;
    if (!_visible) {
      _visible = true;
      notifyListeners();
    }
  }

  void setVisible(bool visible) {
    _travel = 0;
    _direction = 0;
    if (_visible != visible) {
      _visible = visible;
      notifyListeners();
    }
  }

  bool onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification) {
      _userScrolling = notification.dragDetails != null;
      _travel = 0;
      _direction = 0;
    } else if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle) {
      _userScrolling = true;
    } else if (notification is ScrollEndNotification) {
      _userScrolling = false;
      _travel = 0;
    } else if (notification is ScrollUpdateNotification && _userScrolling) {
      final metrics = notification.metrics;
      if (metrics.pixels <= 8 ||
          metrics.extentAfter < 24 ||
          metrics.maxScrollExtent <= 0) {
        show();
        return false;
      }
      final delta = notification.scrollDelta ?? 0;
      if (delta == 0) return false;
      final direction = delta > 0 ? 1 : -1;
      if (direction != _direction) {
        _travel = 0;
        _direction = direction;
      }
      _travel += delta.abs();
      if (_travel >= (direction > 0 ? 32 : 20)) {
        final next = direction < 0;
        _travel = 0;
        if (next != _visible) {
          _visible = next;
          notifyListeners();
        }
      }
    }
    return false;
  }
}
