import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

/// A non-intrusive [Directory] that can be used to extract Protobuf related
/// files for later.
final Directory temporaryDirectory =
    Directory(path.join('.dart_tool', 'build', 'protoc_builder'));

/// Downloads a ZIP archive from a specified [Uri] into memory, unpacks the
/// archive, and then stores all files contained within in the [target]
/// [Directory]. Directories are created recursively if necessary.
/// The [test] parameter acts as a filter that can optionally be supplied to
/// limit the amount of files extracted from the archive.
Future<void> unzipUri(Uri uri, Directory target,
    [bool Function(ArchiveFile file)? test]) async {
  final archive = ZipDecoder().decodeBytes(await http.readBytes(uri));
  for (final file in archive) {
    final filename = file.name;
    if (file.isFile && (test == null || test(file))) {
      final fileHandle = File(path.join(target.path, filename));
      await fileHandle.create(recursive: true);
      await fileHandle.writeAsBytes(file.content as List<int>);
    }
  }
}

/// If necessary for the current [Platform], runs the `chmod` command to add the
/// executable flag to a given [file].
Future<void> addRunnableFlag(File file) async {
  if (!Platform.isWindows) {
    await ProcessExtensions.runSafely('chmod', ['+x', file.absolute.path]);
  }
}

/// An error describing the failure of a [Process].
class ProcessError extends Error {
  ProcessError(this.executable, this.arguments, this.result);

  final String executable;
  final List<String> arguments;
  final ProcessResult result;

  @override
  String toString() {
    return '''
A process finished with exit code ${result.exitCode}:

Call:
"$executable", ${json.encode(arguments)}

Standard error output:
${result.stderr}
    ''';
  }
}

extension ProcessExtensions on Process {
  /// Runs [Process#run] but throws a [ProcessError] if the [Process] exits with
  /// a non-zero status code.
  static Future<ProcessResult> runSafely(
      String executable, List<String> arguments,
      {String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment = true,
      bool runInShell = false,
      Encoding? stdoutEncoding = systemEncoding,
      Encoding? stderrEncoding = systemEncoding}) async {
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell,
      stdoutEncoding: stdoutEncoding,
      stderrEncoding: stderrEncoding,
    );
    if (result.exitCode != 0) throw ProcessError(executable, arguments, result);
    return result;
  }
}
