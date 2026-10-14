import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluxpoint/core/models/cart_item.dart';
import 'package:fluxpoint/core/models/order.dart';
import 'package:fluxpoint/core/models/product.dart';
import 'package:fluxpoint/core/services/kitchen_alert_service.dart';
import 'package:fluxpoint/core/services/kitchen_sound_settings.dart';

class FakeAlertService extends KitchenAlertService {
  int plays = 0;
  KitchenSoundSettings? last;
  @override
  Future<String?> play(KitchenSoundSettings s, {bool preview = false}) async {
    plays++;
    last = s;
    return null;
  }

  @override
  void dispose() {}
}

CartItem item(
  String name, {
  bool kitchen = true,
  int round = 1,
  String status = 'pending',
}) => CartItem(
  product: Product(
    id: 'p-$name',
    businessId: 'b',
    name: name,
    price: 10,
    sendToKitchen: kitchen,
  ),
  quantity: 1,
  round: round,
  kitchenStatus: status,
);

Order order(String id, List<CartItem> items, {DateTime? created}) => Order(
  id: id,
  businessId: 'b',
  orderNumber: 1,
  tableId: null,
  orderType: OrderType.walkIn,
  customerName: null,
  status: OrderStatus.pending,
  createdAt: created ?? DateTime.now(),
  subtotal: 0,
  totalAmount: 0,
  items: items,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAlertService fake;
  late ProviderContainer c;
  late KitchenAlertEngine engine;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fake = FakeAlertService();
    c = ProviderContainer(
      overrides: [kitchenAlertServiceProvider.overrideWithValue(fake)],
    );
    engine = c.read(kitchenAlertEngineProvider)..baselineWindow = Duration.zero;
  });
  tearDown(() => c.dispose());

  Future<void> snap(List<Order> o, {bool auto = true, bool allowed = true}) =>
      engine.handleSnapshot(
        o,
        source: 'test',
        autoEnabled: auto,
        allowed: allowed,
      );

  test('selecting a sound, volume, repeat persists across restart', () async {
    final n = c.read(kitchenSoundSettingsProvider.notifier);
    await n.ensureLoaded();
    await n.setSound('loud_alarm');
    await n.setVolume(0.4);
    await n.setRepeat(2);
    final c2 = ProviderContainer();
    await c2.read(kitchenSoundSettingsProvider.notifier).ensureLoaded();
    final s = c2.read(kitchenSoundSettingsProvider);
    expect(s.soundId, 'loud_alarm');
    expect(s.volume, closeTo(0.4, 0.001));
    expect(s.repeat, 2);
    c2.dispose();
  });

  test('restore defaults resets sound prefs', () async {
    final n = c.read(kitchenSoundSettingsProvider.notifier);
    await n.ensureLoaded();
    await n.setSound('digital_beep');
    await n.setEnabled(true);
    await n.restoreDefaults();
    final s = c.read(kitchenSoundSettingsProvider);
    expect(s.soundId, kDefaultSoundId);
    expect(s.enabledOverride, isNull);
    expect(s.volume, 1.0);
  });

  test(
    'eligible order plays once; duplicate snapshot does not replay',
    () async {
      final o = order('o1', [item('Burger')]);
      await snap([o]);
      await snap([o]);
      await snap([o]);
      expect(fake.plays, 1);
    },
  );

  test('non-kitchen only: silent; mixed: plays once', () async {
    await snap([
      order('a', [item('Soda', kitchen: false)]),
    ]);
    expect(fake.plays, 0);
    await snap([
      order('b', [item('Soda', kitchen: false), item('Burger')]),
    ]);
    expect(fake.plays, 1);
  });

  test('disabled by user or auto-off (single device): silent', () async {
    await snap([
      order('a', [item('Burger')]),
    ], auto: false);
    expect(fake.plays, 0);
    final n = c.read(kitchenSoundSettingsProvider.notifier);
    await n.setEnabled(false);
    await snap([
      order('b', [item('Burger')]),
    ]);
    expect(fake.plays, 0);
    await n.setEnabled(true); // explicit enable on single device
    await snap([
      order('c', [item('Burger')]),
    ], auto: false);
    expect(fake.plays, 1);
  });

  test(
    'allowed:false (cashier device in two-device setup) never plays',
    () async {
      await c.read(kitchenSoundSettingsProvider.notifier).setEnabled(true);
      await snap([
        order('a', [item('Burger')]),
      ], allowed: false);
      expect(fake.plays, 0);
    },
  );

  test('old order at startup is silent', () async {
    engine.baselineWindow = const Duration(seconds: 15);
    engine.resetSession();
    await snap([
      order('old', [
        item('Burger'),
      ], created: DateTime.now().subtract(const Duration(hours: 1))),
    ]);
    expect(fake.plays, 0);
  });

  test('new round alerts; status change does not', () async {
    await snap([
      order('o', [item('Burger')]),
    ]);
    expect(fake.plays, 1);
    await snap([
      order('o', [item('Burger'), item('Fries', round: 2)]),
    ]);
    expect(fake.plays, 2);
    await snap([
      order('o', [
        item('Burger', status: 'preparing'),
        item('Fries', round: 2, status: 'preparing'),
      ]),
    ]);
    expect(fake.plays, 2);
  });

  test('audio file header validation', () {
    final wav = [...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WAVE'.codeUnits];
    expect(KitchenAlertService.validateHeader(wav, 'wav'), isNull);
    expect(
      KitchenAlertService.validateHeader('hello world!'.codeUnits, 'wav'),
      isNotNull,
    );
    expect(
      KitchenAlertService.validateHeader([0xFF, 0xFB, 0x90, 0x00], 'mp3'),
      isNull,
    );
    expect(
      KitchenAlertService.validateHeader('OggS....'.codeUnits, 'ogg'),
      isNull,
    );
    expect(
      KitchenAlertService.validateHeader('MZ..'.codeUnits, 'exe'),
      isNotNull,
    );
  });
}
