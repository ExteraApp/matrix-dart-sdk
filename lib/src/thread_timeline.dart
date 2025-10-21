import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:matrix/src/thread.dart';

class ThreadTimeline extends Timeline {
  final Thread thread;
  
  @override
  List<Event> get events => chunk.events;

  TimelineChunk chunk;

  ThreadTimeline({
    required this.thread,
    required this.chunk
  }) {
    
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
  Future<void> requestFuture({int historyCount = Room.defaultHistoryCount, StateFilter? filter}) {
    // TODO: implement requestFuture
    throw UnimplementedError();
  }

  @override
  Future<void> requestHistory({int historyCount = Room.defaultHistoryCount, StateFilter? filter}) {
    // TODO: implement requestHistory
    throw UnimplementedError();
  }

  @override
  void requestKeys({bool tryOnlineBackup = true, bool onlineKeyBackupOnly = true}) {
    // TODO: implement requestKeys
  }

  @override
  Future<void> setReadMarker({String? eventId, bool? public}) {
    // TODO: implement setReadMarker
    throw UnimplementedError();
  }

  @override
  Stream<(List<Event>, String?)> startSearch({String? searchTerm, int requestHistoryCount = 100, int maxHistoryRequests = 10, String? prevBatch, String? sinceEventId, int? limit, bool Function(Event p1)? searchFunc}) {
    // TODO: implement startSearch
    throw UnimplementedError();
  }

}