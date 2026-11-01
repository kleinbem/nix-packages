{
  lib,
  stdenvNoCC,
  cups,
  runCommand,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "ricoh-sp220-driver";
  version = "2.0";

  src = ./RICOH-SP-220Nw.ppd;
  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/cups/model/ricoh
    cp $src $out/share/cups/model/ricoh/RICOH-SP-220Nw.ppd
    runHook postInstall
  '';

  passthru.tests = {
    cupstestppd =
      runCommand "ricoh-driver-testppd"
        {
          nativeBuildInputs = [ cups ];
        }
        ''
          cupstestppd -v ${finalAttrs.finalPackage}/share/cups/model/ricoh/RICOH-SP-220Nw.ppd
          touch $out
        '';
  };

  meta = {
    description = "Driverless PWG Raster profile for Ricoh SP 220Nw series";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
})
