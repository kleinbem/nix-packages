# Oh My Pi (omp), upstream's prebuilt release binaries, pinned in
# ./versions.json; scripts/update-oh-my-pi.sh bumps them.
#
# No patchelf: the binary is a `bun build --compile` output whose app payload
# sits at a fixed offset from EOF. Changing the file size breaks the lookup and
# omp silently runs as plain bun. So the wrapper runs the untouched binary
# through glibc's dynamic linker instead.
{
  lib,
  stdenv,
  fetchurl,
  glibc,
  makeWrapper,
}:
let
  pname = "oh-my-pi";
  version = "18.14.0";
  inherit (stdenv.hostPlatform) system;

  versions = builtins.fromJSON (builtins.readFile ./versions.json);
  manifest = versions.${version}.${system} or (throw "Unsupported system for oh-my-pi: ${system}");

  dynamicLinker =
    {
      x86_64-linux = "ld-linux-x86-64.so.2";
      aarch64-linux = "ld-linux-aarch64.so.1";
    }
    .${system} or (throw "Unsupported system for oh-my-pi: ${system}");
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    inherit (manifest) url;
    inherit (manifest) hash;
  };

  # Not an archive — the release asset IS the binary.
  dontUnpack = true;
  # Stripping also moves the payload (see the top of the file).
  dontStrip = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/libexec
    # Untouched, byte-for-byte as downloaded — see the top-of-file comment
    # for why this must NOT go through patchelf.
    install -m755 $src $out/libexec/omp-unwrapped

    makeWrapper "${glibc}/lib/${dynamicLinker}" $out/bin/omp \
      --add-flags "--library-path ${glibc}/lib" \
      --add-flags "$out/libexec/omp-unwrapped"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Terminal coding-agent CLI — IDE capabilities (LSP, Python/JS execution, browser, subagents) wired into a single terminal tool";
    homepage = "https://github.com/can1357/oh-my-pi";
    license = licenses.mit;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "omp";
  };
}
