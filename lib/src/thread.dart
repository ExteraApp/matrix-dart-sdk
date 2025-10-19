import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:html_unescape/html_unescape.dart';

import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:matrix/src/utils/file_send_request_credentials.dart';
import 'package:matrix/src/utils/markdown.dart';
import 'package:matrix/src/utils/marked_unread.dart';
import 'package:matrix/src/utils/space_child.dart';

class Thread {
  final Room room;
  final String threadRootId;

  Thread({
    required Room this.room,
    required String this.threadRootId
  }) {

  }
}