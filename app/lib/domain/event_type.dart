/// Mirrors `EVENT_TYPES` in backend/Code.gs, plus read-only types seen in the live sheet.
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

  /// Present in the live sheet (e.g. movie outing); read-only, never posted by the app.
  activity('activity'),
  voidEvent('void');

  const EventType(this.wire);

  final String wire;

  static final _byWire = {for (final t in values) t.wire: t};

  static EventType? fromWire(String? s) =>
      s == null ? null : _byWire[s.trim().toLowerCase()];
}

/// Spend categories used across the live sheet and `Code.gs`.
abstract final class SpendCategory {
  static const foodOut = 'food_out';
  static const foodDelivery = 'food_delivery';
  static const quickCommerce = 'quick_commerce';
  static const drinks = 'drinks';
  static const canteen = 'canteen';
  static const streetFood = 'street_food';
  static const delivery = 'delivery';
  static const tobacco = 'tobacco';
  static const smoking = 'smoking';
  static const tea = 'tea';
  static const groceries = 'groceries';
  static const transport = 'transport';
  static const grooming = 'grooming';
  static const personalCare = 'personal_care';
  static const entertainment = 'entertainment';
  static const health = 'health';
  static const bills = 'bills';
  static const oneOff = 'one_off';
  static const other = 'other';

  static const all = [
    foodOut,
    foodDelivery,
    quickCommerce,
    drinks,
    tobacco,
    tea,
    groceries,
    transport,
    personalCare,
    entertainment,
    health,
    bills,
    oneOff,
    other,
    // Legacy / Code.gs names
    canteen,
    streetFood,
    delivery,
    grooming,
    smoking,
  ];

  /// Excluded from daily burn.
  static const nonBurn = {bills, oneOff};

  /// Delivery / quick-commerce bucket for the Money split bar.
  static const deliveryLike = {delivery, foodDelivery, quickCommerce};
}

/// Study rating notes.
abstract final class Rating {
  static const blank = 'blank';
  static const shaky = 'shaky';
  static const nailed = 'nailed';
  static const session = 'session';
  static const all = {blank, shaky, nailed};
}
