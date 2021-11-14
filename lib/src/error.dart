import 'dart:io';

/// An error class for errors produced by the protoc compiler process.
class ProtocError extends Error {
  ProtocError(this.processResult) : assert(processResult.exitCode != 0);

  final ProcessResult processResult;

  @override
  String toString() {
    return 'The protoc process finished with errors:\n\n${processResult.stderr}';
  }
}
