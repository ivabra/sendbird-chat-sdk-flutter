// Copyright (c) 2023 Sendbird, Inc. All rights reserved.

import 'dart:async';
import 'dart:collection';

import 'package:sendbird_chat_sdk/src/internal/main/logger/sendbird_logger.dart';
import 'package:sendbird_chat_sdk/src/internal/main/utils/async/async_task.dart';

class AsyncQueue<T> {
  bool _isScheduled = false;

  final Queue<Operation> _operationQueue = Queue<Operation>();
  final Map<int, Completer> _completerMap = {};
  Operation? _currentOperation;

  Future<void> enqueue(Operation operation) {
    sbLog.d(StackTrace.current);

    _operationQueue.add(operation);
    final completer = Completer();
    _completerMap[operation.hashCode] = completer;

    if (!_isScheduled) {
      _isScheduled = true;
      Timer(const Duration(seconds: 0), _execute);
    }
    return completer.future;
  }

  bool cancel(int hashCode) {
    sbLog.d(StackTrace.current);

    final completer = _completerMap.remove(hashCode);
    if (completer != null && !completer.isCompleted) {
      if (_currentOperation?.onCancel != null) {
        _currentOperation?.onCancel!();
      }
      completer.complete();
      return true;
    }
    return false;
  }

  Future _execute() async {
    sbLog.d(StackTrace.current);

    while (true) {
      if (_operationQueue.isEmpty) {
        sbLog.d(StackTrace.current);
        _isScheduled = false;
        return;
      }

      var task = _operationQueue.removeFirst();
      _currentOperation = task;

      if (task is AsyncTask<T>) {
        dynamic res;
        try {
          res = await task.func(task.arg);
        } catch (e) {
          sbLog.e(StackTrace.current, 'e: $e');
          _isScheduled = false;
          rethrow;
        } finally {
          _completerMap.remove(task.hashCode)?.complete(res);
        }
      } else if (task is AsyncSimpleTask) {
        try {
          await task.func();
        } catch (e) {
          sbLog.e(StackTrace.current, 'e: $e');
          _isScheduled = false;
          rethrow;
        } finally {
          _completerMap.remove(task.hashCode)?.complete();
        }
      }
    }
  }

  void cleanUp() {
    sbLog.d(StackTrace.current);

    for (final operation in _operationQueue) {
      cancel(operation.hashCode);
    }
    _operationQueue.removeWhere((element) => true);
    _currentOperation = null;
  }
}
