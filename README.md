A Dart [build](https://pub.dev/packages/build) package to compile [Protocol Buffer](https://developers.google.com/protocol-buffers)
files to Dart source code using [build_runner](https://github.com/protocolbuffers/protobuf) (i.e.
the Dart build pipline) without needing to manually install the [protoc](https://github.com/protocolbuffers/protobuf)
compiler or the Dart Protobuf plugin [protoc_plugin](https://github.com/protocolbuffers/protobuf).

The `protoc_builder` package downloads the necessary Protobuf dependencies for your platform to a
temporary local directory, thereby streamlining the development process.

## Installation
Add the necessary dependencies to your `pubspec.yaml` file:
```yaml
dev_dependencies:
  build_runner: <latest>
  protoc_builder: <latest>
```

## Configuration
You must add your `.proto` files to a `build.yaml` file next to the `pubspec.yaml`:
```yaml
targets:
  $default:
    sources:
      - $package$
      - lib/$lib$
      - proto/** # Your .proto directory
```
This will use the default configuration for the `protoc_builder`.

You may also configure custom options:
```yaml
targets:
  $default:
    sources:
      - $package$
      - lib/$lib$
      - proto/**
    builders:
      protoc_builder:
        options:
          # The version of the Protobuf compiler to use.
          # (Default: "3.19.1", make sure to use quotation marks)
          protobuf_version: "3.19.1"
          # The version of the Dart protoc_plugin package to use.
          # (Default: "20.0.1", make sure to use quotation marks)
          protoc_plugin_version: "20.0.1"
          # Directory which is treated as the root of all Protobuf files.
          # (Default: "proto/")
          root_dir: "proto/"
          # Include paths given to the Protobuf compiler during compilation.
          # (Default: ["proto/"])
          proto_paths:
            - "proto/"
          # The root directory for generated Dart output files.
          # (Default: "lib/src/proto")
          out_dir: "lib/src/generated"
          # Enable the gRPC flag for the Dart protoc plugin to generate `.pbgrpc.dart` files.
          # (Default: false)
          grpc: true
          # Use the "protoc" command that's available on the PATH instead of downloading one
          # (Default: false)
          use_installed_protoc: false
```

## Running
Once everything is set up, you may simply run the `build_runner` package:
```bash
pub run build_runner build
```
The `build_runner` sometimes caches results longer than it should, so in some cases, it may be necessary to delete the `.dart_tool/build` directory.