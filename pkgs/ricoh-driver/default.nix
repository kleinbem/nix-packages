{ pkgs, ... }:

pkgs.stdenv.mkDerivation {
  pname = "ricoh-official-driver";
  version = "1.01";

  src = ./ricoh-driver.rpm;

  nativeBuildInputs = [
    pkgs.rpmextract
    pkgs.autoPatchelfHook
    pkgs.makeWrapper
  ];

  buildInputs = [
    pkgs.cups
    pkgs.ghostscript
    pkgs.stdenv.cc.cc.lib
    pkgs.zlib
    pkgs.dbus
    pkgs.avahi
    pkgs.libidn2
    pkgs.libunistring
    pkgs.libtasn1
    pkgs.nettle
    pkgs.gmp
    pkgs.p11-kit
    pkgs.libffi
    pkgs.libcap
    pkgs.libusb1
  ];

  unpackPhase = "rpmextract $src";

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

  # This is the secret sauce: it wraps the filters so they can 
  # find 'gs' (Ghostscript) and 'cat' even in the restricted CUPS env.
  postFixup = ''
    for filter in $out/lib/cups/filter/*; do
      wrapProgram "$filter" --prefix PATH : "${pkgs.lib.makeBinPath [ pkgs.ghostscript pkgs.coreutils pkgs.gnused ]}"
    done
  '';

  meta = {
    description = "Ricoh SP 220Nw Official Driver";
    license = pkgs.lib.licenses.unfree;
    platforms = pkgs.lib.platforms.linux;
  };
}