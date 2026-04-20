// lib/core/services/event_bus.dart
import 'dart:async';

// Lightweight in-process event bus for decoupled module communication.
// Example: kitchen listens for 'order.placed' without importing cart directly.

class AppEvent {
  final String type;
  final Map<String, dynamic> payload;

  const AppEvent(this.type, [this.payload = const {}]);
}

class EventBus {
  EventBus._();
  static final EventBus instance = EventBus._();

  final _controller = StreamController<AppEvent>.broadcast();

  Stream<AppEvent> get stream => _controller.stream;

  void emit(String type, [Map<String, dynamic> payload = const {}]) {
    _controller.add(AppEvent(type, payload));
  }

  Stream<AppEvent> on(String type) =>
      _controller.stream.where((e) => e.type == type);

  void dispose() => _controller.close();
}

// Common event type constants — avoids magic strings
class AppEvents {
  AppEvents._();
  static const orderPlaced = 'order.placed';
  static const orderStatusChanged = 'order.status_changed';
  static const tableSeleced = 'table.selected';
  static const cartCleared = 'cart.cleared';
}