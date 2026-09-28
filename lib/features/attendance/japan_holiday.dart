class JapanHoliday {
  const JapanHoliday._();

  static String? name(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final holidays = _holidaysForYear(day.year);
    return holidays[day];
  }

  static Map<DateTime, String> _holidaysForYear(int year) {
    final base = <DateTime, String>{};

    void add(int month, int day, String name) {
      base[DateTime(year, month, day)] = name;
    }

    DateTime nthMonday(int month, int nth) {
      final first = DateTime(year, month, 1);
      final offset = (DateTime.monday - first.weekday) % 7;
      return DateTime(year, month, 1 + offset + 7 * (nth - 1));
    }

    add(1, 1, '元日');

    if (year >= 2000) {
      base[nthMonday(1, 2)] = '成人の日';
    } else if (year >= 1949) {
      add(1, 15, '成人の日');
    }

    add(2, 11, '建国記念の日');
    if (year >= 2020) add(2, 23, '天皇誕生日');

    final vernalDay = _vernalEquinoxDay(year);
    add(3, vernalDay, '春分の日');

    add(4, 29, year >= 2007 ? '昭和の日' : 'みどりの日');

    add(5, 3, '憲法記念日');
    add(5, 4, 'みどりの日');
    add(5, 5, 'こどもの日');

    if (year >= 2003) {
      base[nthMonday(7, 3)] = '海の日';
    } else if (year >= 1996) {
      add(7, 20, '海の日');
    }

    if (year >= 2016) add(8, 11, '山の日');

    if (year >= 2003) {
      base[nthMonday(9, 3)] = '敬老の日';
    } else if (year >= 1966) {
      add(9, 15, '敬老の日');
    }

    final autumnalDay = _autumnalEquinoxDay(year);
    add(9, autumnalDay, '秋分の日');

    if (year >= 2000) {
      base[nthMonday(10, 2)] = 'スポーツの日';
    } else if (year >= 1966) {
      add(10, 10, '体育の日');
    }

    add(11, 3, '文化の日');
    add(11, 23, '勤労感謝の日');

    // One-off Olympic moves.
    if (year == 2020) {
      base.remove(DateTime(year, 7, 20));
      base.remove(DateTime(year, 8, 11));
      base.remove(DateTime(year, 10, 12));
      add(7, 23, '海の日');
      add(7, 24, 'スポーツの日');
      add(8, 10, '山の日');
    } else if (year == 2021) {
      base.remove(DateTime(year, 7, 19));
      base.remove(DateTime(year, 8, 11));
      base.remove(DateTime(year, 10, 11));
      add(7, 22, '海の日');
      add(7, 23, 'スポーツの日');
      add(8, 8, '山の日');
    }

    // Citizens' Holiday: a weekday sandwiched between two national holidays.
    final sorted = base.keys.toList()..sort();
    for (var i = 0; i < sorted.length - 1; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      final between = a.add(const Duration(days: 1));
      if (b.difference(a).inDays == 2 &&
          between.weekday != DateTime.sunday &&
          !base.containsKey(between)) {
        base[between] = '国民の休日';
      }
    }

    // Substitute holidays. Since 2007, the next non-holiday weekday after
    // a Sunday holiday becomes a substitute holiday.
    final originals = base.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in originals) {
      if (entry.key.weekday != DateTime.sunday) continue;
      var substitute = entry.key.add(const Duration(days: 1));
      while (base.containsKey(substitute)) {
        substitute = substitute.add(const Duration(days: 1));
      }
      base[substitute] = '振替休日';
    }

    return base;
  }

  static int _vernalEquinoxDay(int year) {
    if (year <= 1979) {
      return (20.8357 + 0.242194 * (year - 1980) - ((year - 1983) ~/ 4))
          .floor();
    }
    if (year <= 2099) {
      return (20.8431 + 0.242194 * (year - 1980) - ((year - 1980) ~/ 4))
          .floor();
    }
    return (21.8510 + 0.242194 * (year - 1980) - ((year - 1980) ~/ 4))
        .floor();
  }

  static int _autumnalEquinoxDay(int year) {
    if (year <= 1979) {
      return (23.2588 + 0.242194 * (year - 1980) - ((year - 1983) ~/ 4))
          .floor();
    }
    if (year <= 2099) {
      return (23.2488 + 0.242194 * (year - 1980) - ((year - 1980) ~/ 4))
          .floor();
    }
    return (24.2488 + 0.242194 * (year - 1980) - ((year - 1980) ~/ 4))
        .floor();
  }
}
