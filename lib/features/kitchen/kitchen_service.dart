// lib/features/kitchen/kitchen_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/order_provider.dart';
import '../../core/models/order.dart';

// Re-exposes order slices relevant to the kitchen display
final kitchenPendingProvider = Provider<List<Order>>((ref) {
  return ref.watch(orderProvider).where((o) => o.status == 'pending').toList();
});

final kitchenPreparingProvider = Provider<List<Order>>((ref) {
  return ref.watch(orderProvider).where((o) => o.status == 'preparing').toList();
});

final kitchenReadyProvider = Provider<List<Order>>((ref) {
  return ref.watch(orderProvider).where((o) => o.status == 'ready').toList();
});

// Helper — bump an order through its lifecycle
extension KitchenActions on OrderNotifier {
  void acceptOrder(String orderId) => updateStatus(orderId, 'preparing');
  void markReady(String orderId) => updateStatus(orderId, 'ready');
  void completeOrder(String orderId) => removeOrder(orderId);
}