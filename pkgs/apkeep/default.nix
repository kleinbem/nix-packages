{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  openssl,
}:

let
  pname = "apkeep";
  version = "1.1.0";

  sources = {
    x86_64-linux = {
      url = "https://github.com/EFForg/apkeep/releases/download/${version}/apkeep-x86_64-unknown-linux-gnu";
      hash = "sha256-ut162fp9LzKr4B6vM7f/CGNhqVu8AAozv0S2MNS/IUA=";
    };
  };

  source = sources.${stdenv.hostPlatform.system} or (throw "Unsupported system for apkeep: ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    inherit (source) url hash;
  };

  dontUnpack = true;

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  buildInputs = [
    openssl
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    install -m755 $src $out/bin/apkeep

    runHook postInstall
  '';

  meta = with lib; {
    description = "Command-line tool for downloading APK files from Google Play, F-Droid, and APKPure";
    homepage = "https://github.com/EFForg/apkeep";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "apkeep";
  };
}
