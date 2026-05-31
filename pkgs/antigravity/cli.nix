# Google Antigravity CLI (`agy`). See ./package.nix header for provenance.
# Hashes are pinned in ./versions.json (sha512, hex-encoded with a "sha512-"
# prefix that we strip below).
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  installShellFiles,
}:
let
  pname = "google-antigravity-cli";
  inherit (stdenv.hostPlatform) system;

  versions = builtins.fromJSON (builtins.readFile ./versions.json);
  manifest =
    versions."Antigravity CLI".${system} or (throw "Unsupported system for Antigravity CLI: ${system}");

  # versions.json stores only the CLI url + hash, so derive the version from
  # the URL path (e.g. .../antigravity-cli/1.0.3-6260531212976128/...).
  version =
    let
      match = builtins.match ".*/([0-9]+\\.[0-9]+\\.[0-9]+-[0-9]+)/.*" manifest.url;
    in
    if match != null then builtins.elemAt match 0 else "unknown";
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    inherit (manifest) url;
    sha512 = builtins.substring 7 128 manifest.hash; # Remove 'sha512-' prefix from our JSON
  };

  nativeBuildInputs =
    lib.optionals stdenv.hostPlatform.isLinux [
      autoPatchelfHook
    ]
    ++ [
      installShellFiles
    ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    # Rename to agy to avoid naming conflict and match installer behavior
    cp antigravity $out/bin/agy

    runHook postInstall
  '';

  meta = with lib; {
    description = "Google Antigravity CLI - Describe what you need, and Antigravity handles the rest";
    homepage = "https://antigravity.google";
    license = licenses.unfree;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    mainProgram = "agy";
  };
}
