import 'package:matrix/matrix.dart';

class Thread {
  final Room room;
  final Event rootEvent;
  Event? lastEvent;
  final Client client;

  Thread({
    required this.room,
    required this.rootEvent,
    required this.client,
    this.lastEvent,
  });

  factory Thread.fromJson(Map<String, dynamic> json, Client client) {
    final room = client.getRoomById(json['room_id']);
    if (room == null) throw Error();
    Event? lastEvent;
    if (json['unsigned']?['m.relations']?['m.thread']?['latest_event'] !=
        null) {
      lastEvent = Event.fromMatrixEvent(
        MatrixEvent.fromJson(
          json['unsigned']?['m.relations']?['m.thread']?['latest_event'],
        ),
        room,
      );
    }
    final thread = Thread(
      room: room,
      client: client,
      rootEvent: Event.fromMatrixEvent(
        MatrixEvent.fromJson(json),
        room,
      ),
      lastEvent: lastEvent,
    );
    return thread;
  }

  Future<Event?>? _refreshingLastEvent;

  Future<Event?> _refreshLastEvent({
    timeout = const Duration(seconds: 30),
  }) async {
    if (room.membership != Membership.join) return null;

    final result = await client
        .getRelatingEventsWithRelType(
          room.id,
          rootEvent.eventId,
          'm.thread',
        )
        .timeout(timeout);
    final matrixEvent = result.chunk.firstOrNull;
    if (matrixEvent == null) {
      if (lastEvent?.type == EventTypes.refreshingLastEvent) {
        lastEvent = null;
      }
      Logs().d(
        'No last event found for thread ${rootEvent.eventId} in ${rootEvent.roomId}',
      );
      return null;
    }
    var event = Event.fromMatrixEvent(
      matrixEvent,
      room,
      status: EventStatus.synced,
    );
    if (event.type == EventTypes.Encrypted) {
      final encryption = client.encryption;
      if (encryption != null) {
        event = await encryption.decryptRoomEvent(event);
      }
    }
    lastEvent = event;

    return event;
  }

  /// When was the last event received.
  DateTime get latestEventReceivedTime {
    final lastEventTime = lastEvent?.originServerTs;
    if (lastEventTime != null) return lastEventTime;

    if (room.membership == Membership.invite) return DateTime.now();

    return rootEvent.originServerTs;
  }

  bool get hasNewMessages {
    // TODO: Implement this
    return false;
  }

  Future<String?> sendTextEvent(
    String message, {
    String? txid,
    Event? inReplyTo,
    String? editEventId,
    bool parseMarkdown = true,
    bool parseCommands = true,
    String msgtype = MessageTypes.Text,
    StringBuffer? commandStdout,
    bool addMentions = true,

    /// Displays an event in the timeline with the transaction ID as the event
    /// ID and a status of SENDING, SENT or ERROR until it gets replaced by
    /// the sync event. Using this can display a different sort order of events
    /// as the sync event does replace but not relocate the pending event.
    bool displayPendingEvent = true,
  }) {
    return room.sendTextEvent(
      message,
      txid: txid,
      inReplyTo: inReplyTo,
      editEventId: editEventId,
      parseCommands: parseCommands,
      parseMarkdown: parseMarkdown,
      msgtype: msgtype,
      commandStdout: commandStdout,
      addMentions: addMentions,
      displayPendingEvent: displayPendingEvent,
      threadLastEventId: lastEvent?.eventId,
      threadRootEventId: rootEvent.eventId,
    );
  }

  Future<String?> sendLocation(String body, String geoUri, {String? txid}) {
    final event = <String, dynamic>{
      'msgtype': 'm.location',
      'body': body,
      'geo_uri': geoUri,
    };
    return room.sendEvent(
      event,
      txid: txid,
      threadLastEventId: lastEvent?.eventId,
      threadRootEventId: rootEvent.eventId,
    );
  }

  Future<String?> sendFileEvent(
    MatrixFile file, {
    String? txid,
    Event? inReplyTo,
    String? editEventId,
    int? shrinkImageMaxDimension,
    MatrixImageFile? thumbnail,
    Map<String, dynamic>? extraContent,

    /// Displays an event in the timeline with the transaction ID as the event
    /// ID and a status of SENDING, SENT or ERROR until it gets replaced by
    /// the sync event. Using this can display a different sort order of events
    /// as the sync event does replace but not relocate the pending event.
    bool displayPendingEvent = true,
  }) async {
    return await room.sendFileEvent(
      file,
      txid: txid,
      inReplyTo: inReplyTo,
      editEventId: editEventId,
      shrinkImageMaxDimension: shrinkImageMaxDimension,
      thumbnail: thumbnail,
      extraContent: extraContent,
      displayPendingEvent: displayPendingEvent,
      threadLastEventId: lastEvent?.eventId,
      threadRootEventId: rootEvent.eventId,
    );
  }
}
