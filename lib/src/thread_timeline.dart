import 'dart:async';

import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:matrix/src/thread.dart';

// ThreadTimeline: hey RoomTimeline can i copy your homework?
// RoomTimeline: sure just don't make it too obvious
// ThreadTimeline:

class ThreadTimeline extends Timeline {
  final Thread thread;

  @override
  List<Event> get events => chunk.events;

  TimelineChunk chunk;

  StreamSubscription<Event>? timelineSub;
  StreamSubscription<Event>? historySub;
  StreamSubscription<SyncUpdate>? roomSub;
  StreamSubscription<String>? sessionIdReceivedSub;
  StreamSubscription<String>? cancelSendEventSub;

  ThreadTimeline({
    required this.thread,
    required this.chunk,
    super.onUpdate,
    super.onChange,
    super.onInsert,
    super.onRemove,
    super.onNewEvent,
  }) {
    final room = thread.room;
    timelineSub = room.client.onTimelineEvent.stream.listen(
      (event) => _handleEventUpdate(event, EventUpdateType.timeline),
    );
    historySub = room.client.onHistoryEvent.stream.listen(
      (event) => _handleEventUpdate(event, EventUpdateType.history),
    );
  }

  void _handleEventUpdate(
    Event event,
    EventUpdateType type, {
    bool update = true,
  }) {
    try {
      if (event.roomId != thread.room.id) return;
      // Ignore events outside of this thread
      if (event.relationshipType != RelationshipTypes.thread ||
          event.relationshipEventId != thread.rootEvent.eventId) return;

      if (type != EventUpdateType.timeline && type != EventUpdateType.history) {
        return;
      }

      if (type == EventUpdateType.timeline) {
        onNewEvent?.call();
      }

      if (type == EventUpdateType.history &&
          events.indexWhere((e) => e.eventId == event.eventId) != -1) {
        return;
      }
      var index = events.length;
      if (type == EventUpdateType.history) {
        events.add(event);
      } else {
        index = events.firstIndexWhereNotError;
        events.insert(index, event);
      }
      onInsert?.call(index);

      addAggregatedEvent(event);

      // Handle redaction events
      if (event.type == EventTypes.Redaction) {
        final index = _findEvent(event_id: event.redacts);
        if (index < events.length) {
          removeAggregatedEvent(events[index]);

          // Is the redacted event a reaction? Then update the event this
          // belongs to:
          if (onChange != null) {
            final relationshipEventId = events[index].relationshipEventId;
            if (relationshipEventId != null) {
              onChange?.call(_findEvent(event_id: relationshipEventId));
              return;
            }
          }

          events[index].setRedactionEvent(event);
          onChange?.call(index);
        }
      }

      if (update) {
        onUpdate?.call();
      }
    } catch (e, s) {
      Logs().w('Handle event update failed', e, s);
    }
  }

  /// Add an event to the aggregation tree
  void addAggregatedEvent(Event event) {
    final relationshipType = event.relationshipType;
    final relationshipEventId = event.relationshipEventId;
    if (relationshipType == null || relationshipEventId == null) {
      return;
    }
    final e = (aggregatedEvents[relationshipEventId] ??=
        <String, Set<Event>>{})[relationshipType] ??= <Event>{};
    _removeEventFromSet(e, event);
    e.add(event);
    if (onChange != null) {
      final index = _findEvent(event_id: relationshipEventId);
      onChange?.call(index);
    }
  }

  /// Remove an event from aggregation
  void removeAggregatedEvent(Event event) {
    aggregatedEvents.remove(event.eventId);
    if (event.transactionId != null) {
      aggregatedEvents.remove(event.transactionId);
    }
    for (final types in aggregatedEvents.values) {
      for (final e in types.values) {
        _removeEventFromSet(e, event);
      }
    }
  }

  /// Remove event from set based on event or transaction ID
  void _removeEventFromSet(Set<Event> eventSet, Event event) {
    eventSet.removeWhere(
      (e) =>
          e.matchesEventOrTransactionId(event.eventId) ||
          event.unsigned != null &&
              e.matchesEventOrTransactionId(event.transactionId),
    );
  }

  /// Find event index by event ID or transaction ID
  int _findEvent({String? event_id, String? unsigned_txid}) {
    final searchNeedle = <String>{};
    if (event_id != null) searchNeedle.add(event_id);
    if (unsigned_txid != null) searchNeedle.add(unsigned_txid);

    int i;
    for (i = 0; i < events.length; i++) {
      final searchHaystack = <String>{events[i].eventId};
      final txnid = events[i].transactionId;
      if (txnid != null) searchHaystack.add(txnid);
      if (searchNeedle.intersection(searchHaystack).isNotEmpty) break;
    }
    return i;
  }

  @override
  // TODO: implement canRequestFuture
  bool get canRequestFuture => throw UnimplementedError();

  @override
  // TODO: implement canRequestHistory
  bool get canRequestHistory => throw UnimplementedError();

  @override
  void cancelSubscriptions() {
    // TODO: implement cancelSubscriptions
  }

  @override
  Future<Event?> getEventById(String id) {
    // TODO: implement getEventById
    throw UnimplementedError();
  }

  @override
  Future<void> requestFuture(
      {int historyCount = Room.defaultHistoryCount, StateFilter? filter}) {
    // TODO: implement requestFuture
    throw UnimplementedError();
  }

  @override
  Future<void> requestHistory(
      {int historyCount = Room.defaultHistoryCount, StateFilter? filter}) {
    // TODO: implement requestHistory
    throw UnimplementedError();
  }

  @override
  void requestKeys(
      {bool tryOnlineBackup = true, bool onlineKeyBackupOnly = true}) {
    // TODO: implement requestKeys
  }

  @override
  Future<void> setReadMarker({String? eventId, bool? public}) {
    // TODO: implement setReadMarker
    throw UnimplementedError();
  }

  @override
  Stream<(List<Event>, String?)> startSearch(
      {String? searchTerm,
      int requestHistoryCount = 100,
      int maxHistoryRequests = 10,
      String? prevBatch,
      String? sinceEventId,
      int? limit,
      bool Function(Event p1)? searchFunc}) {
    // TODO: implement startSearch
    throw UnimplementedError();
  }
}
