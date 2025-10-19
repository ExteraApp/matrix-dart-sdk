/*
 *   Famedly Matrix SDK
 *   Copyright (C) 2019, 2020, 2021 Famedly GmbH
 *
 *   This program is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU Affero General Public License as
 *   published by the Free Software Foundation, either version 3 of the
 *   License, or (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *   GNU Affero General Public License for more details.
 *
 *   You should have received a copy of the GNU Affero General Public License
 *   along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';

/// Abstract base class for all timeline implementations.
/// Provides common functionality for event management, aggregation, and search.
abstract class Timeline {
  /// The list of events in this timeline
  List<Event> get events;

  /// Map of event ID to map of type to set of aggregated events
  final Map<String, Map<String, Set<Event>>> aggregatedEvents = {};

  /// Called when the timeline is updated
  final void Function()? onUpdate;
  
  /// Called when an event at specific index changes
  final void Function(int index)? onChange;
  
  /// Called when an event is inserted at specific index
  final void Function(int index)? onInsert;
  
  /// Called when an event is removed from specific index
  final void Function(int index)? onRemove;
  
  /// Called when a new event is added to the timeline
  final void Function()? onNewEvent;

  bool get canRequestHistory;
  bool get canRequestFuture;

  Timeline({
    this.onUpdate,
    this.onChange,
    this.onInsert,
    this.onRemove,
    this.onNewEvent,
  });

  /// Searches for the event in this timeline. If not found, requests from server.
  Future<Event?> getEventById(String id);

  /// Request more previous events
  Future<void> requestHistory({
    int historyCount = Room.defaultHistoryCount,
    StateFilter? filter,
  });

  /// Request more future events
  Future<void> requestFuture({
    int historyCount = Room.defaultHistoryCount,
    StateFilter? filter,
  });

  /// Set the read marker to an event in this timeline
  Future<void> setReadMarker({String? eventId, bool? public});

  /// Request keys for undecryptable events
  void requestKeys({
    bool tryOnlineBackup = true,
    bool onlineKeyBackupOnly = true,
  });

  /// Search events in this timeline
  Stream<(List<Event>, String?)> startSearch({
    String? searchTerm,
    int requestHistoryCount = 100,
    int maxHistoryRequests = 10,
    String? prevBatch,
    @Deprecated('Use [prevBatch] instead.') String? sinceEventId,
    int? limit,
    bool Function(Event)? searchFunc,
  });

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

  /// Remove event from set based on event or transaction ID
  void _removeEventFromSet(Set<Event> eventSet, Event event) {
    eventSet.removeWhere(
      (e) =>
          e.matchesEventOrTransactionId(event.eventId) ||
          event.unsigned != null &&
              e.matchesEventOrTransactionId(event.transactionId),
    );
  }

  /// Handle event updates (to be implemented by subclasses)
  void _handleEventUpdate(Event event, EventUpdateType type, {bool update = true});

  /// Cancel all subscriptions
  void cancelSubscriptions();

  @Deprecated('Use [startSearch] instead.')
  Stream<List<Event>> searchEvent({
    String? searchTerm,
    int requestHistoryCount = 100,
    int maxHistoryRequests = 10,
    String? sinceEventId,
    int? limit,
    bool Function(Event)? searchFunc,
  }) =>
      startSearch(
        searchTerm: searchTerm,
        requestHistoryCount: requestHistoryCount,
        maxHistoryRequests: maxHistoryRequests,
        sinceEventId: sinceEventId,
        limit: limit,
        searchFunc: searchFunc,
      ).map((result) => result.$1);
}