{ pkgs }: {
  deps = [
    # Ships the Dart SDK too — do not also add pkgs.dart, the two will fight
    # over PATH and you will get confusing version mismatch errors.
    pkgs.flutter

    pkgs.git
    pkgs.unzip
    pkgs.which
    pkgs.python3   # used only to serve the release build
  ];
}
