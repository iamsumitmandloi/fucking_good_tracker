import 'package:flutter_test/flutter_test.dart';
import 'package:starting_again/domain/derivations/daily_stats.dart';
import 'package:starting_again/domain/event_type.dart';
import 'package:starting_again/domain/quicklog/parser.dart';

ParseResult parse(String s) => parseQuickLog(s, cigPrice: 25, teaPrice: 20);

ParsedEntry one(String s) {
  final r = parse(s);
  expect(r.entries, hasLength(1), reason: 'input "$s"');
  return r.entries.single;
}

void main() {
  group('habits', () {
    test('"1 cig" → 1 cigarette, ₹25 tobacco', () {
      final e = one('1 cig');
      expect(e.type, EventType.cigarette);
      expect(e.qty, 1);
      expect(e.unit, 'cig');
      expect(e.amount, 25);
      expect(e.category, SpendCategory.tobacco);
      expect(e.title, 'Cigarette × 1');
    });

    test('"2 cigs" → qty 2, ₹50', () {
      final e = one('2 cigs');
      expect(e.qty, 2);
      expect(e.amount, 50);
    });

    test('"cig x3" → qty 3', () {
      final e = one('cig x3');
      expect(e.qty, 3);
      expect(e.amount, 75);
    });

    test('"cig 3" → small trailing number is a count', () {
      final e = one('cig 3');
      expect(e.qty, 3);
      expect(e.amount, 75);
    });

    test('"cig 24" → typed price', () {
      final e = one('cig 24');
      expect(e.qty, 1);
      expect(e.amount, 24);
    });

    test('"cig ₹5" → ₹ means price even when small', () {
      final e = one('cig ₹5');
      expect(e.qty, 1);
      expect(e.amount, 5);
    });

    test('"tea" → 1 cup, ₹20', () {
      final e = one('tea');
      expect(e.type, EventType.tea);
      expect(e.qty, 1);
      expect(e.unit, 'cup');
      expect(e.amount, 20);
      expect(e.category, SpendCategory.tea);
    });

    test('"2 chai" → 2 teas, ₹40', () {
      final e = one('2 chai');
      expect(e.type, EventType.tea);
      expect(e.qty, 2);
      expect(e.amount, 40);
    });

    test('"tea 2" → 2 teas, not ₹2', () {
      final e = one('tea 2');
      expect(e.qty, 2);
      expect(e.amount, 40);
    });

    test('"coffee" → no default price', () {
      final e = one('coffee');
      expect(e.type, EventType.coffee);
      expect(e.amount, isNull);
    });

    test('"coffee 60" → ₹60', () => expect(one('coffee 60').amount, 60));
  });

  group('combos', () {
    test('"1 cig + tea 45" → ₹25 + ₹20, one payment', () {
      final r = parse('1 cig + tea 45');
      expect(r.entries.map((e) => e.type), [
        EventType.cigarette,
        EventType.tea,
      ]);
      expect(r.entries.map((e) => e.amount), [25, 20]);
      expect(r.splitTotal, 45);
      expect(r.total, 45);
    });

    test('"2 cig + tea 70" → ₹50 + ₹20', () {
      final r = parse('2 cig + tea 70');
      expect(r.entries.map((e) => e.amount), [50, 20]);
      expect(r.splitTotal, 70);
    });

    test('"cig + tea" → defaults, no split', () {
      final r = parse('cig + tea');
      expect(r.entries.map((e) => e.amount), [25, 20]);
      expect(r.splitTotal, isNull);
      expect(r.total, 45);
    });

    test('comma and "&" also split', () {
      expect(parse('tea, water').entries, hasLength(2));
      expect(parse('tea & cig').entries, hasLength(2));
    });

    test('"+" groups split inside a comma list', () {
      final r = parse('1 cig + tea 45, lunch 130');
      expect(r.entries.map((e) => e.amount), [25, 20, 130]);
      expect(r.splitTotal, isNull); // not one payment overall
      expect(r.total, 175);
    });

    test('a total smaller than the defaults is not split', () {
      final r = parse('2 cig + tea 30');
      expect(r.splitTotal, isNull);
      expect(r.entries.map((e) => e.amount), [50, 30]);
    });
  });

  group('water', () {
    test('"water" → 250 ml', () {
      final e = one('water');
      expect(e.type, EventType.waterMl);
      expect(e.qty, 250);
      expect(e.unit, 'ml');
    });

    test('"water 500 ml" → 500', () => expect(one('water 500 ml').qty, 500));
    test('"water 1.5L" → 1500', () => expect(one('water 1.5L').qty, 1500));
    test('"water 2" → 2 L', () => expect(one('water 2').qty, 2000));
    test('"2 glasses water" → 500', () {
      expect(one('2 glasses water').qty, 500);
    });
  });

  group('meals and spend', () {
    test('"lunch 130" → meal, ₹130', () {
      final e = one('lunch 130');
      expect(e.type, EventType.meal);
      expect(e.label, 'Lunch');
      expect(e.amount, 130);
      expect(e.note, 'lunch');
      expect(e.category, SpendCategory.other);
    });

    test('"canteen lunch 130" → meal in canteen', () {
      final e = one('canteen lunch 130');
      expect(e.type, EventType.meal);
      expect(e.label, 'Canteen lunch');
      expect(e.category, SpendCategory.canteen);
    });

    test('"breakfast poha 40" → meal with label', () {
      final e = one('breakfast poha 40');
      expect(e.label, 'Breakfast poha');
      expect(e.amount, 40);
    });

    test('"dinner zomato 250" → delivery', () {
      final e = one('dinner zomato 250');
      expect(e.type, EventType.meal);
      expect(e.category, SpendCategory.delivery);
    });

    test('"dinner" alone → meal without money', () {
      final e = one('dinner');
      expect(e.type, EventType.meal);
      expect(e.amount, isNull);
      expect(e.category, isNull);
    });

    test('"snack 30" → snack', () {
      final e = one('snack 30');
      expect(e.type, EventType.snack);
      expect(e.amount, 30);
    });

    test('"pani puri 30" → street-food snack', () {
      final e = one('pani puri 30');
      expect(e.type, EventType.snack);
      expect(e.label, 'Pani puri');
      expect(e.category, SpendCategory.streetFood);
    });

    test('"zomato 320" → delivery spend', () {
      final e = one('zomato 320');
      expect(e.type, EventType.spend);
      expect(e.category, SpendCategory.delivery);
      expect(e.amount, 320);
    });

    test('"electricity bill 1450" → bills', () {
      expect(one('electricity bill 1450').category, SpendCategory.bills);
    });

    test('"450" → plain spend', () {
      final e = one('450');
      expect(e.type, EventType.spend);
      expect(e.amount, 450);
      expect(e.category, SpendCategory.other);
    });

    test('"₹99" → spend 99', () => expect(one('₹99').amount, 99));

    test('"zomato 12.50" → amount, not a time', () {
      final e = one('zomato 12.50');
      expect(e.amount, 12.5);
      expect(e.time, isNull);
    });

    test('"lazypay swiggy 280" → source lazypay', () {
      final e = one('lazypay swiggy 280');
      expect(e.source, 'lazypay');
      expect(e.category, SpendCategory.delivery);
      expect(e.amount, 280);
    });
  });

  group('body and sleep', () {
    test('"weight 87.9" → kg', () {
      final e = one('weight 87.9');
      expect(e.type, EventType.weight);
      expect(e.qty, 87.9);
      expect(e.unit, 'kg');
    });

    test('"87.9 kg" → weight', () => expect(one('87.9 kg').qty, 87.9));

    test('"slept 22:30" → sleep at 22:30', () {
      final e = one('slept 22:30');
      expect(e.type, EventType.sleep);
      expect(e.time, '22:30');
    });

    test('"slept 11:30 pm" → 23:30', () {
      expect(one('slept 11:30 pm').time, '23:30');
    });

    test('"slept 23" → bare hour', () => expect(one('slept 23').time, '23:00'));

    test('"woke 6:10" → wake', () {
      final e = one('woke 6:10');
      expect(e.type, EventType.wake);
      expect(e.time, '06:10');
    });

    test('"woke 6am" → 06:00', () => expect(one('woke 6am').time, '06:00'));
    test('"woke 6" → 06:00', () => expect(one('woke 6').type, EventType.wake));

    test('"protein 25g" → breakfast protein', () {
      final e = one('protein 25g');
      expect(e.type, EventType.meal);
      expect(e.unit, 'g');
      expect(e.qty, 25);
      expect(e.label, proteinLabel);
    });

    test('"8,000 steps" → 8000', () => expect(one('8,000 steps').qty, 8000));

    test('"walk 30 min" → exercise', () {
      final e = one('walk 30 min');
      expect(e.type, EventType.exercise);
      expect(e.label, 'Walk');
      expect(e.qty, 30);
    });

    test('"energy 7" → energy', () {
      final e = one('energy 7');
      expect(e.type, EventType.energy);
      expect(e.qty, 7);
    });

    test('"supp vitamin d" → supplement', () {
      final e = one('supp vitamin d');
      expect(e.type, EventType.supplement);
      expect(e.label, 'Vitamin d');
    });
  });

  group('bus', () {
    test('"boarded 9:20" → bus_board', () {
      final e = one('boarded 9:20');
      expect(e.type, EventType.busBoard);
      expect(e.time, '09:20');
    });

    test('"bus" → board now', () {
      final e = one('bus');
      expect(e.type, EventType.busBoard);
      expect(e.time, isNull);
    });

    test('"office reached 10:40" → bus_arrive', () {
      final e = one('office reached 10:40');
      expect(e.type, EventType.busArrive);
      expect(e.time, '10:40');
    });

    test('"reached home 19:28" → bus_arrive', () {
      final e = one('reached home 19:28');
      expect(e.type, EventType.busArrive);
      expect(e.time, '19:28');
    });
  });

  group('times and approx', () {
    test('"tea at 16:30" → tea with time', () {
      final e = one('tea at 16:30');
      expect(e.type, EventType.tea);
      expect(e.time, '16:30');
    });

    test('"tea 16:30" → bare trailing time', () {
      final e = one('tea 16:30');
      expect(e.type, EventType.tea);
      expect(e.time, '16:30');
    });

    test('"cig at 4pm" → 16:00', () => expect(one('cig at 4pm').time, '16:00'));

    test('"~2 cigs" → approx', () {
      final e = one('~2 cigs');
      expect(e.approx, isTrue);
      expect(e.qty, 2);
    });

    test('"around 7:30 woke" style approx on wake', () {
      final e = one('woke around 7:30');
      expect(e.type, EventType.wake);
      expect(e.approx, isTrue);
      expect(e.time, '07:30');
    });
  });

  group('fallbacks', () {
    test('"After lunch" → note', () {
      final e = one('After lunch');
      expect(e.type, EventType.note);
      expect(e.note, 'After lunch');
      expect(e.title, 'Note: "After lunch"');
    });

    test('"~12:30 (AM/PM unconfirmed)" → approx note', () {
      final e = one('~12:30 (AM/PM unconfirmed)');
      expect(e.type, EventType.note);
      expect(e.approx, isTrue);
      expect(e.note, '~12:30 (AM/PM unconfirmed)');
    });

    test('gibberish → note, never throws', () {
      expect(one('asdf qwer').type, EventType.note);
      expect(one(':::').type, EventType.note);
      expect(one('weight 999').type, EventType.note);
    });

    test('empty input → nothing', () {
      expect(parse('').entries, isEmpty);
      expect(parse('  +  , ').entries, isEmpty);
    });
  });

  group('categoryFor', () {
    test('keywords', () {
      expect(categoryFor('Swiggy order'), SpendCategory.delivery);
      expect(categoryFor('auto to office'), SpendCategory.transport);
      expect(categoryFor('haircut'), SpendCategory.grooming);
      expect(categoryFor('random thing'), SpendCategory.other);
    });
  });
}
