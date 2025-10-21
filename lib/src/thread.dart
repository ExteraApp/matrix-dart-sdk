import 'package:matrix/matrix.dart';

class Thread {
  final Room room;
  final MatrixEvent rootEvent;
  final MatrixEvent? lastEvent;

  Thread({
    required this.room,
    required this.rootEvent,
    this.lastEvent,
  });

  factory Thread.fromJson(Map<String, dynamic> json, Client client) {
    final room = client.getRoomById(json['room_id']);
    if (room == null) throw Error();
    MatrixEvent? lastEvent;
    if (json['unsigned']?['m.relations']?['m.thread']?['latest_event'] != null) {
      lastEvent = MatrixEvent.fromJson(json['unsigned']?['m.relations']?['m.thread']?['latest_event']);
    }
    final thread = Thread(
        room: room,
        rootEvent: MatrixEvent.fromJson(json),
        lastEvent: lastEvent,
    );
    return thread;
  }
}
