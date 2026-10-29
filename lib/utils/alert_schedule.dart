// The alert day follows Philippine time, regardless of the phone's time zone.
DateTime philippineDayStart(DateTime instant) {
  final philippine = instant.toUtc().add(const Duration(hours: 8));
  return DateTime.utc(philippine.year, philippine.month, philippine.day)
      .subtract(const Duration(hours: 8));
}

DateTime nextAlertMidnight(DateTime instant) =>
    philippineDayStart(instant).add(const Duration(days: 1));
