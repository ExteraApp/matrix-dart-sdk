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

  @override
  bool isRequestingHistory = false;

  @override
  bool isFragmentedTimeline = false;

  final Map<String, Event> _eventCache = {};

  @override
  bool allowNewEvent = true;

  @override
  bool isRequestingFuture = false;

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

    // we want to populate our aggregated events
    for (final e in events) {
      addAggregatedEvent(e);
    }

    // we are using a fragmented timeline
    if (chunk.nextBatch != '') {
      allowNewEvent = false;
      isFragmentedTimeline = true;
    }
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
          event.relationshipEventId != thread.rootEvent.eventId) {
        return;
      }

      if (type != EventUpdateType.timeline && type != EventUpdateType.history) {
        return;
      }

      if (type == EventUpdateType.timeline) {
        onNewEvent?.call();
      }

      final status = event.status;
      final i = _findEvent(
        event_id: event.eventId,
        unsigned_txid: event.transactionId,
      );
      if (i < events.length) {
        // if the old status is larger than the new one, we also want to preserve the old status
        final oldStatus = events[i].status;
        events[i] = event;
        // do we preserve the status? we should allow 0 -> -1 updates and status increases
        if ((latestEventStatus(status, oldStatus) == oldStatus) &&
            !(status.isError && oldStatus.isSending)) {
          events[i].status = oldStatus;
        }
        addAggregatedEvent(events[i]);
        onChange?.call(i);
      } else {
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
      }

      unawaited(thread.setLastEvent(events[events.length - 1]));

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

  /// Request more previous events from the server.
  Future<int> getThreadEvents({
    int historyCount = Room.defaultHistoryCount,
    direction = Direction.b,
    StateFilter? filter,
  }) async {
    // Ensure stateFilter is not null and set lazyLoadMembers to true if not already set
    filter ??= StateFilter(lazyLoadMembers: true);
    filter.lazyLoadMembers ??= true;

    final resp = await thread.client.getRelatingEventsWithRelType(
      thread.room.id,
      thread.rootEvent.eventId,
      RelationshipTypes.thread,
      dir: direction,
      from: direction == Direction.b ? chunk.prevBatch : chunk.nextBatch,
      limit: historyCount,
      recurse: true,
    );

    Logs().w(
      'Loading thread events from server ${resp.chunk.length} ${resp.prevBatch}',
    );

    if (resp.nextBatch == null) {
      Logs().w('We reached the end of the timeline');
    }

    final newNextBatch =
        direction == Direction.b ? resp.prevBatch : resp.nextBatch;
    final newPrevBatch =
        direction == Direction.b ? resp.nextBatch : resp.prevBatch;

    final type = direction == Direction.b
        ? EventUpdateType.history
        : EventUpdateType.timeline;

    // I dont know what this piece of code does
    // if ((resp.state?.length ?? 0) == 0 &&
    //     resp.start != resp.end &&
    //     newPrevBatch != null &&
    //     newNextBatch != null) {
    //   if (type == EventUpdateType.history) {
    //     Logs().w(
    //       '[nav] we can still request history prevBatch: $type $newPrevBatch',
    //     );
    //   } else {
    //     Logs().w(
    //       '[nav] we can still request timeline nextBatch: $type $newNextBatch',
    //     );
    //   }
    // }

    final newEvents =
        resp.chunk.map((e) => Event.fromMatrixEvent(e, thread.room)).toList();

    if (!allowNewEvent) {
      if (resp.prevBatch == resp.nextBatch ||
          (resp.nextBatch == null && direction == Direction.f)) {
        allowNewEvent = true;
      }

      if (allowNewEvent) {
        Logs().d('We now allow sync update into the timeline.');
        newEvents.addAll(
          await thread.client.database
              .getThreadEventList(thread, onlySending: true),
        );
      }
    }

    // Try to decrypt encrypted events but don't update the database.
    if (thread.room.encrypted && thread.client.encryptionEnabled) {
      for (var i = 0; i < newEvents.length; i++) {
        if (newEvents[i].type == EventTypes.Encrypted) {
          newEvents[i] = await thread.client.encryption!.decryptRoomEvent(
            newEvents[i],
          );
        }
      }
    }

    // update chunk anchors
    if (type == EventUpdateType.history) {
      chunk.prevBatch = newPrevBatch ?? '';

      final offset = chunk.events.length;

      chunk.events.addAll(newEvents);

      for (var i = 0; i < newEvents.length; i++) {
        onInsert?.call(i + offset);
      }
    } else {
      chunk.nextBatch = newNextBatch ?? '';
      chunk.events.insertAll(0, newEvents.reversed);

      for (var i = 0; i < newEvents.length; i++) {
        onInsert?.call(i);
      }
    }

    if (onUpdate != null) {
      onUpdate!();
    }
    return resp.chunk.length;
  }

  Future<void> _requestEvents({
    int historyCount = Room.defaultHistoryCount,
    required Direction direction,
    StateFilter? filter,
  }) async {
    onUpdate?.call();

    try {
      // Look up for events in the database first. With fragmented view, we should delete the database cache
      final eventsFromStore = isFragmentedTimeline
          ? null
          : await thread.client.database.getThreadEventList(
              thread,
              start: events.length,
              limit: historyCount,
            );

      if (eventsFromStore != null && eventsFromStore.isNotEmpty) {
        for (final e in eventsFromStore) {
          addAggregatedEvent(e);
        }
        // Fetch all users from database we have got here.
        for (final event in events) {
          if (thread.room.getState(EventTypes.RoomMember, event.senderId) !=
              null) {
            continue;
          }
          final dbUser =
              await thread.client.database.getUser(event.senderId, thread.room);
          if (dbUser != null) thread.room.setState(dbUser);
        }

        if (direction == Direction.b) {
          events.addAll(eventsFromStore);
          final startIndex = events.length - eventsFromStore.length;
          final endIndex = events.length;
          for (var i = startIndex; i < endIndex; i++) {
            onInsert?.call(i);
          }
        } else {
          events.insertAll(0, eventsFromStore);
          final startIndex = eventsFromStore.length;
          final endIndex = 0;
          for (var i = startIndex; i > endIndex; i--) {
            onInsert?.call(i);
          }
        }
      } else {
        Logs().i('No more events found in the store. Request from server...');

        if (isFragmentedTimeline) {
          await getThreadEvents(
            historyCount: historyCount,
            direction: direction,
            filter: filter,
          );
        } else {
          if (thread.prev_batch == null) {
            Logs().i('No more events to request from server...');
          } else {
            await thread.requestHistory(
              historyCount: historyCount,
              direction: direction,
              onHistoryReceived: () {},
              filter: filter,
            );
          }
        }
      }
    } finally {
      isRequestingHistory = false;
      onUpdate?.call();
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
  void cancelSubscriptions() {
    // TODO: implement cancelSubscriptions
  }

  @override
  Future<Event?> getEventById(String id) async {
    for (final event in events) {
      if (event.eventId == id) return event;
    }
    if (_eventCache.containsKey(id)) return _eventCache[id];
    final requestedEvent = await thread.room.getEventById(id);
    if (requestedEvent == null) return null;
    _eventCache[id] = requestedEvent;
    return _eventCache[id];
  }

  @override
  Future<void> requestHistory({
    int historyCount = Room.defaultHistoryCount,
    StateFilter? filter,
  }) async {
    if (isRequestingHistory) return;
    isRequestingHistory = true;
    await _requestEvents(
      direction: Direction.b,
      historyCount: historyCount,
      filter: filter,
    );
    isRequestingHistory = false;
  }

  @override
  Future<void> setReadMarker({String? eventId, bool? public}) {
    return thread.setReadMarker(
      eventId: eventId,
      public: public,
    );
  }

  @override
  Stream<(List<Event>, String?)> startSearch({
    String? searchTerm,
    int requestHistoryCount = 100,
    int maxHistoryRequests = 10,
    String? prevBatch,
    String? sinceEventId,
    int? limit,
    bool Function(Event p1)? searchFunc,
  }) {
    // TODO: implement startSearch
    throw UnimplementedError();
  }

  @override
  bool get canRequestFuture => chunk.nextBatch.isNotEmpty;

  @override
  bool get canRequestHistory => chunk.prevBatch.isNotEmpty;

  @override
  Future<void> requestFuture({
    int historyCount = Room.defaultHistoryCount,
    StateFilter? filter,
  }) async {
    if (isRequestingFuture || !canRequestFuture) return;
    isRequestingFuture = true;

    try {
      await getThreadEvents(
        historyCount: historyCount,
        direction: Direction.f,
        filter: filter,
      );
    } finally {
      isRequestingFuture = false;
    }
  }

  @override
  Future<void> requestKeys({
    bool tryOnlineBackup = true,
    bool onlineKeyBackupOnly = true,
  }) async {
    for (final event in events) {
      if (event.type == EventTypes.Encrypted &&
          event.messageType == MessageTypes.BadEncrypted &&
          event.content['can_request_session'] == true) {
        final sessionId = event.content.tryGet<String>('session_id');
        final senderKey = event.content.tryGet<String>('sender_key');
        if (sessionId != null && senderKey != null) {
          await thread.room.requestSessionKey(sessionId, senderKey);
        }
      }
    }
  }
}
