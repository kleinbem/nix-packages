# This file describes your repository contents.
# It should return a set of nix derivations
# and optionally the special attributes `lib`, `modules` and `overlays`.
# It should NOT import <nixpkgs>. Instead, you should take pkgs as an argument.
# Having pkgs default to <nixpkgs> is fine though, and it lets you use short
# commands such as:
#     nix-build -A mypackage

{
  pkgs ? import (builtins.getFlake "nixpkgs") { system = "x86_64-linux"; },
}:

{

  example-package = pkgs.callPackage ./pkgs/example-package { };
  langfuse = pkgs.callPackage ./pkgs/langfuse { };
  ricoh-driver = pkgs.callPackage ./pkgs/ricoh-driver/default.nix { };

  # Google Antigravity 2.0 — vendored from the audited jacopone derivation,
  # binaries pinned to Google's official CDNs in pkgs/antigravity/versions.json.
  # NOTE: namespaced under `google-antigravity*` to avoid clobbering nixpkgs'
  # own `antigravity` attr (which derives `antigravity-fhs = antigravity.fhs`).
  google-antigravity = pkgs.callPackage ./pkgs/antigravity/package.nix {
    appType = "Antigravity 2.0";
  };
  google-antigravity-ide = pkgs.callPackage ./pkgs/antigravity/package.nix {
    appType = "Antigravity IDE";
  };
  # no-FHS variant: autoPatchelf instead of bubblewrap, so `sudo` works in the
  # integrated terminal (FHS sandbox sets no-new-privileges and breaks it).
  google-antigravity-ide-no-fhs = pkgs.callPackage ./pkgs/antigravity/package.nix {
    appType = "Antigravity IDE";
    useFHS = false;
  };
  google-antigravity-cli = pkgs.callPackage ./pkgs/antigravity/cli.nix { };
  # some-qt5-package = pkgs.libsForQt5.callPackage ./pkgs/some-qt5-package { };
  # ...
}
