{ pkgs, lib, ... }:

pkgs.stdenv.mkDerivation {
  pname = "ricoh-official-driver";
  version = "1.01";

  src = ./ricoh-driver.rpm;

  nativeBuildInputs = [
    pkgs.rpmextract
    pkgs.makeWrapper
  ];

  unpackPhase = "rpmextract $src";

  # Leave the prebuilt blob byte-for-byte as shipped.
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    # Create the standard structure
    mkdir -p $out/lib/cups/filter
    mkdir -p $out/share/cups/model/ricoh

    # Copy everything from the extracted RPM usr folder
    # Note: RPMs usually put filters in usr/lib/cups/filter
    if [ -d "usr/lib/cups/filter" ]; then
      cp -r usr/lib/cups/filter/* $out/lib/cups/filter/
    fi

    # Find and move PPD files to where NixOS looks for them
    find . -name "*.ppd" -exec cp {} $out/share/cups/model/ricoh/ \;

    # Ensure filters are executable
    chmod +x $out/lib/cups/filter/*

    runHook postInstall
  '';

  # The blob is not patchelf'd: patchelf's rewrite of this old binary makes
  # the glibc loader segfault before main. Run it through ld.so instead.
  postFixup = ''
    mv $out/lib/cups/filter/rastertolilo2 $out/lib/cups/filter/.rastertolilo2-unpatched
    makeWrapper ${pkgs.stdenv.cc.bintools.dynamicLinker} $out/lib/cups/filter/rastertolilo2 \
      --add-flags "--argv0 \"\$0\" --library-path ${
        lib.makeLibraryPath [
          pkgs.cups.lib
          pkgs.stdenv.cc.cc.lib
        ]
      } $out/lib/cups/filter/.rastertolilo2-unpatched" \
      --prefix PATH : "${
        lib.makeBinPath [
          pkgs.ghostscript
          pkgs.coreutils
          pkgs.gnused
        ]
      }"
  '';

  meta = {
    description = "Ricoh SP 220Nw Official Driver";
    license = lib.licenses.unfree;
    platforms = lib.platforms.linux;
  };
}
