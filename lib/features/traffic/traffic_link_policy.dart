enum TrafficDestination { nearestStation, trainTransfer, busStop }

/// A server-validated master snapshot. Missing configuration fails closed.
class TrafficAvailability {
  const TrafficAvailability({
    required this.nearestStation,
    required this.trainTransfer,
    required this.busStop,
  });

  final bool nearestStation;
  final bool trainTransfer;
  final bool busStop;

  static const unavailable = TrafficAvailability(
    nearestStation: false,
    trainTransfer: false,
    busStop: false,
  );

  bool permits(TrafficDestination destination) => switch (destination) {
    TrafficDestination.nearestStation => nearestStation,
    TrafficDestination.trainTransfer => trainTransfer,
    TrafficDestination.busStop => busStop,
  };
}

/// No coordinates, address, account identifier or SKO location access.
Uri trafficDestinationUri(TrafficDestination destination) {
  if (destination == TrafficDestination.trainTransfer) {
    return Uri.https('transit.yahoo.co.jp', '/');
  }
  return Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': destination == TrafficDestination.nearestStation
        ? '最寄り駅'
        : '近くのバス停',
  });
}
