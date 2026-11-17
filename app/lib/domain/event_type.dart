/// Mirrors `EVENT_TYPES` in backend/Code.gs. The backend skips unknown types.
enum EventType {
  sleep('sleep'),
  wake('wake'),
  weight('weight'),
  cigarette('cigarette'),
  tea('tea'),
  coffee('coffee'),
  waterMl('water_ml'),
  meal('meal'),
  snack('snack'),
  supplement('supplement'),
  busBoard('bus_board'),
  busArrive('bus_arrive'),
  exercise('exercise'),
  steps('steps'),
  work('work'),
  study('study'),
  spend('spend'),
  energy('energy'),
  mood('mood'),
  note('note'),
  voidEvent('void');

  const EventType(this.wire);

  final String wire;

  static final _byWire = {for (final t in values) t.wire: t};

  static EventType? fromWire(String? s) =>
      s == null ? null : _byWire[s.trim().toLowerCase()];
}

/// Mirrors `SPEND_CATEGORIES` in backend/Code.gs.
abstract final class SpendCategory {
  static const canteen = 'canteen';
  static const streetFood = 'street_food';
  static const delivery = 'delivery';
  static const tobacco = 'tobacco';
  static const tea = 'tea';
  static const groceries = 'groceries';
  static const transport = 'transport';
  static const grooming = 'grooming';
  static const bills = 'bills';
  static const oneOff = 'one_off';
  static const other = 'other';

  static const all = [
    canteen,
    streetFood,
    delivery,
    tobacco,
    tea,
    groceries,
    transport,
    grooming,
    bills,
    oneOff,
    other,
  ];

  /// Excluded from daily burn.
  static const nonBurn = {bills, oneOff};
}

/// Study rating notes.
abstract final class Rating {
  static const blank = 'blank';
  static const shaky = 'shaky';
  static const nailed = 'nailed';
  static const session = 'session';
  static const all = {blank, shaky, nailed};
}
