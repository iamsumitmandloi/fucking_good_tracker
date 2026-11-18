import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

import '../../core/clock.dart';
import '../../core/formatters.dart';
import 'metrics.dart';
import 'nights.dart';

/// Confidence 1–5 (brief §7.2): 1 dot when the smaller group has < 5 days,
/// 2 when < 10, 3 for direct counts or ≥ 10 days. 4–5 need ≥ 21 days with a
/// consistent direction (4 from 21 days, 5 from 42).
int confidence(
  int smallerGroupDays, {
  bool direct = false,
  bool consistent = false,
}) {
  if (consistent && smallerGroupDays >= 42) return 5;
  if (consistent && smallerGroupDays >= 21) return 4;
  if (direct) return 3;
  if (smallerGroupDays < 5) return 1;
  if (smallerGroupDays < 10) return 2;
  return 3;
}

class InsightCard extends Equatable {
  const InsightCard(this.title, this.body, this.confidence);
  final String title;
  final String body;
  final int confidence;
  @override
  List<Object?> get props => [title, body, confidence];
}

/// A bold first sentence and a muted second one.
class Takeaway extends Equatable {
  const Takeaway(this.lead, this.rest);
  final String lead;
  final String rest;
  @override
  List<Object?> get props => [lead, rest];
}

String _n(double? v) => trimNum(v);

String _weekday(String date) => DateFormat('EEEE').format(parseDate(date)!);
String _dow(String date) => DateFormat('EEE').format(parseDate(date)!);

String joinAnd(List<String> xs) => switch (xs.length) {
  0 => '',
  1 => xs.first,
  _ => '${xs.sublist(0, xs.length - 1).join(', ')} and ${xs.last}',
};

/// Plain words for an hour of the day.
String hourPhrase(int h) {
  if (h < 5) return 'after midnight';
  if (h < 10) return 'in the morning';
  if (h < 13) return 'late in the morning';
  if (h < 16) return 'after lunch';
  if (h < 18) return 'at evening tea';
  if (h < 21) return 'in the evening';
  return 'late at night';
}

/// The two busiest hours (most cigarettes, earlier hour on a tie), in
/// clock order. Empty when nothing is timed.
List<int> peakHours(Map<int, double> hours) {
  final ranked = hours.entries.toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return [for (final e in ranked.take(2)) e.key]..sort();
}

String peakPhrase(List<int> peaks) {
  final ps = <String>[];
  for (final h in peaks) {
    final p = hourPhrase(h);
    if (!ps.contains(p)) ps.add(p);
  }
  return joinAnd(ps);
}

/// "Peaks at 14:00 and 16:00" + ", after lunch and at evening tea."
Takeaway? peakSentence(WeekMetrics m) {
  final peaks = peakHours(m.hours);
  if (peaks.isEmpty) return null;
  return Takeaway(
    'Peaks at ${joinAnd([for (final h in peaks) '${h.toString().padLeft(2, '0')}:00'])}',
    ', ${peakPhrase(peaks)}.',
  );
}

/// The two written takeaways under the Week ribbons.
List<Takeaway> weekTakeaways(WeekMetrics m) {
  final out = <Takeaway>[];
  final timed = m.timedTotal;
  final peaks = peakHours(m.hours);
  if (timed >= 3 && peaks.isNotEmpty) {
    final inPeaks = peaks.fold<double>(0, (a, h) => a + (m.hours[h] ?? 0));
    final mins = [
      for (final x in m.smokeMinutes)
        if (peaks.contains(x ~/ 60)) x,
    ]..sort();
    final range = mins.isEmpty
        ? ''
        : (mins.first == mins.last
              ? ' at ${hhmmOf(mins.first)}'
              : ' at ${hhmmOf(mins.first)}–${hhmmOf(mins.last)}');
    out.add(
      Takeaway(
        'Smoking clusters ${peakPhrase(peaks)}.',
        'On the days with times, ${_n(inPeaks)} of ${_n(timed)} cigarettes sit$range.',
      ),
    );
  }
  final total = m.cigTotal;
  if (total != null && total > 0) {
    if (timed < total) {
      final none = [
        for (var i = 0; i < m.days.length; i++)
          if ((m.cigs[i] ?? 0) > 0 && (m.cigsTimed[i] ?? 0) == 0)
            _dow(m.days[i]),
      ];
      out.add(
        Takeaway(
          timed == 0
              ? 'None of the ${_n(total)} cigarettes has a time.'
              : 'Only ${_n(timed)} of ${_n(total)} cigarettes have a time.',
          '${none.isEmpty ? '' : '${joinAnd(none)} ${none.length == 1 ? 'has' : 'have'} none, so ${none.length == 1 ? 'its row looks' : 'their rows look'} empty. '}'
          'Ask the logging agent for a time on every entry.',
        ),
      );
    } else {
      out.add(
        const Takeaway(
          'Every cigarette has a time.',
          'The ribbons show the whole day.',
        ),
      );
    }
  }
  return out;
}

/// Pattern cards for the Insights tab.
List<InsightCard> insightCards(WeekMetrics m) {
  final cards = <InsightCard>[];
  final timed = m.timedTotal;

  if (timed > 0) {
    final together = m.paired * 3 >= timed;
    cards.add(
      InsightCard(
        together
            ? 'Tea and cigarettes go together'
            : 'Most cigarettes come without a tea',
        '${_n(m.paired)} of ${_n(timed)} timed cigarettes were logged at the same minute as a tea. A direct count, not a guess.',
        confidence(0, direct: true),
      ),
    );
  }

  final office = m.office;
  final off = m.off;
  var officeCard = false;
  if (office.avg != null && off.avg != null) {
    final conf = confidence(office.days < off.days ? office.days : off.days);
    final diff = office.avg! - off.avg!;
    officeCard = true;
    cards.add(
      InsightCard(
        diff.abs() < 0.05
            ? 'Same on office and off days'
            : (diff > 0
                  ? 'More cigarettes on office days'
                  : 'Fewer cigarettes on office days'),
        '${_n(office.avg)} a day across ${office.days} office ${office.days == 1 ? 'day' : 'days'} vs ${_n(off.avg)} across ${off.days} off ${off.days == 1 ? 'day' : 'days'}.'
        '${conf == 1 ? ' Too few days to trust yet.' : ''}',
        conf,
      ),
    );
  }

  // Cigarettes on the day after a 7h+ night (the night's wake date).
  final longCigs = <double>[];
  final shortCigs = <double>[];
  final longOffice = <bool>[];
  for (var i = 0; i < m.days.length; i++) {
    final s = m.sleep[i];
    final c = m.cigs[i];
    if (s == null || c == null) continue;
    if (s >= 7) {
      longCigs.add(c);
      longOffice.add(m.legs[i].isNotEmpty);
    } else {
      shortCigs.add(c);
    }
  }
  if (longCigs.isNotEmpty && shortCigs.isNotEmpty) {
    final la = longCigs.reduce((a, b) => a + b) / longCigs.length;
    final sa = shortCigs.reduce((a, b) => a + b) / shortCigs.length;
    final conf = confidence(
      longCigs.length < shortCigs.length ? longCigs.length : shortCigs.length,
    );
    final overlap = officeCard && longOffice.every((o) => o);
    final nLong = longCigs.length;
    cards.add(
      InsightCard(
        la <= sa ? 'Fewer after a 7h+ night' : 'More after a 7h+ night',
        '${_n(la)} the next day after $nLong longer ${nLong == 1 ? 'night' : 'nights'} vs ${_n(sa)} after ${shortCigs.length} shorter ${shortCigs.length == 1 ? 'one' : 'ones'}.'
        '${overlap ? ' ${nLong == 1 ? 'The long night was' : (nLong == 2 ? 'Both long nights were' : 'All $nLong long nights were')} before office days, so it overlaps the card above.' : (conf == 1 ? ' Too few days to trust yet.' : '')}',
        conf,
      ),
    );
  }

  final odd = outlierNight(m);
  if (odd != null) {
    final i = m.days.indexOf(odd.wakeDate);
    final parts = <String>[
      'Asleep ${hhmmOf(odd.bedMin!)}${odd.wakeMin == null ? '' : ' to ${hhmmOf(odd.wakeMin!)}'}',
      if (i >= 0 && m.steps[i] != null)
        '${rupees(m.steps[i]).substring(1)} steps',
      if (i >= 0 && m.dayToDay[i] != null) '${rupees(m.dayToDay[i])} spent',
    ];
    final day = parseDate(odd.wakeDate)!.day;
    cards.add(
      InsightCard(
        '${_weekday(odd.wakeDate)} $day stands out',
        '${parts.join(', ')}. One day, so it is a note, not a pattern.',
        1,
      ),
    );
  }
  return cards;
}

/// The night whose bedtime is furthest from the mean, if it is more than
/// 1.5 SD away (needs at least 5 timed nights).
Night? outlierNight(WeekMetrics m) {
  final b = m.bedtime;
  if (b == null || b.count < 5 || b.sdMin == 0) return null;
  Night? best;
  var bestDev = 0.0;
  for (final n in m.nights) {
    final s = n.bedScaled;
    if (s == null) continue;
    final dev = (s - b.meanScaled).abs();
    if (dev > bestDev) {
      bestDev = dev;
      best = n;
    }
  }
  return bestDev > 1.5 * b.sdMin ? best : null;
}

/// "Saturday night" for a night that ends on Sunday morning.
String nightName(Night n) => '${_weekday(addDays(n.wakeDate, -1))} night';

/// The Sleep card sentence: range, usual bedtime, outlier.
Takeaway? sleepSentence(WeekMetrics m) {
  final b = m.bedtime;
  if (b == null) return null;
  final usual = ((b.meanScaled / 15).round() * 15) % 1440;
  final odd = outlierNight(m);
  return Takeaway(
    b.count == 1
        ? 'Bedtime ${hhmmOf(b.earliest.bedMin!)}.'
        : 'Bedtime ranged ${hhmmOf(b.earliest.bedMin!)} → ${hhmmOf(b.latest.bedMin!)}.',
    ' Usual is about ${hhmmOf(usual)}.'
    '${odd == null ? '' : ' ${nightName(odd)} was the outlier.'}',
  );
}
