import 'dart:io';

import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as path;
import 'package:protoc_builder/src/utility.dart';

import 'protoc_plugin_download.dart';

class ProtocFromPubspec extends ProtocFetcher {
  final Package pluginPackage;
  final Package protobufPackage;

  ProtocFromPubspec({
    required this.pluginPackage,
    required this.protobufPackage,
  });

  @override
  Future<void> fetchInto(Directory target) async {
    await Future.wait([
      copyDirectory(
          Directory.fromUri(pluginPackage.root),
          Directory(path.join(
              target.path, 'protobuf.dart-protoc_plugin', 'protoc_plugin'))),
      copyDirectory(
          Directory.fromUri(protobufPackage.root),
          Directory(path.join(
              target.path, 'protobuf.dart-protoc_plugin', 'protobuf'))),
    ]);
  }

  @override
  Directory versionDirectory() {
    var root = path.split(Directory.fromUri(pluginPackage.root).path);
    var last = root.removeLast();

    return Directory(path.join(
      pluginDirectory.path,
      root.last,
      last,
    ));
  }
}

Future<File?> protocPluginPubspecCommand(bool precompileProtocPlugin) async {
  var packageConfig = await findPackageConfig(Directory.current);
  if (packageConfig != null) {
    Package? pluginPackage;
    Package? protobufPackage;

    for (var package in packageConfig.packages) {
      if (package.name == 'protoc_plugin') {
        pluginPackage = package;
      } else if (package.name == 'protobuf') {
        protobufPackage = package;
      }
      if (pluginPackage != null && protobufPackage != null) {
        return await fetchProtocPlugin(
          ProtocFromPubspec(
            pluginPackage: pluginPackage,
            protobufPackage: protobufPackage,
          ),
          precompileProtocPlugin,
        );
      }
    }
    return null;
  } else {
    return null;
  }
}
