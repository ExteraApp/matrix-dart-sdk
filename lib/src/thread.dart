import 'package:matrix/matrix.dart';

class Thread {
  final Room room;
  final Event rootEvent;
  final Event? lastEvent;

  Thread({
    required this.room,
    required this.rootEvent,
    this.lastEvent,
  });

  factory Thread.fromJson(Map<String, dynamic> json, Client client) {
    final room = client.getRoomById(json['room_id']);
    if (room == null) throw Error();
    Event? lastEvent;
    if (json['unsigned']?['m.relations']?['m.thread']?['latest_event'] != null) {
      lastEvent = MatrixEvent.fromJson(json['unsigned']?['m.relations']?['m.thread']?['latest_event']) as Event;
    }
    final thread = Thread(
        room: room,
        rootEvent: MatrixEvent.fromJson(json) as Event,
        lastEvent: lastEvent,
    );
    return thread;
  }
}
