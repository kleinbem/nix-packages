{ pkgs, ... }:

pkgs.stdenv.mkDerivation {
  pname = "ricoh-official-driver";
  version = "1.01";

  # This points to the file named 'ricoh-driver.rpm' in the same folder
  src = ./ricoh-driver.rpm;

  nativeBuildInputs = [
    pkgs.rpmextract
    pkgs.autoPatchelfHook
  ];

  # These are the libraries the binary driver usually needs
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

  unpackPhase = ''
    rpmextract $src
  '';

  installPhase = ''
    mkdir -p $out

    # 1. Copy the standard unix structure from the RPM
    cp -r usr/* $out/

    # 2. Fix PPD location for NixOS CUPS
    mkdir -p $out/share/cups/model/ricoh
    find $out -name "*.ppd" -exec cp {} $out/share/cups/model/ricoh/ \;

    # 3. Fix Filter Permissions (MUST be executable)
    find $out/lib/cups/filter -type f -exec chmod +x {} \;
  '';

  meta = {
    description = "Ricoh SP C250DN Official Driver (Repackaged RPM)";
    homepage = "https://www.ricoh-europe.com/";
    license = pkgs.lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
