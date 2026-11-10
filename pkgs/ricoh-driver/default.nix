{
  lib,
  stdenvNoCC,
  cups,
  runCommand,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "ricoh-sp220-driver";
  version = "2.2";

  src = ./.;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/cups/model/ricoh $out/lib/cups/backend
    cp RICOH-SP-220Nw.ppd $out/share/cups/model/ricoh/RICOH-SP-220Nw.ppd
    substitute ricoh-sp220.sh $out/lib/cups/backend/ricoh-sp220 \
      --subst-var-by cups ${cups}
    chmod 0755 $out/lib/cups/backend/ricoh-sp220
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
    backend = runCommand "ricoh-driver-testbackend" { } ''
      backend="${finalAttrs.finalPackage}/lib/cups/backend/ricoh-sp220"
      if grep -E -q '@[a-zA-Z_]+@' "$backend"; then
        echo "Unsubstituted placeholders found in $backend" >&2
        exit 1
      fi
      "$backend" | grep -q "network ricoh-sp220"
      touch $out
    '';
  };

  meta = {
    description = "Driverless PWG Raster profile and sanitizing IPP backend for Ricoh SP 220Nw series";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
    maintainers = with lib.maintainers; [ ];
  };
})
