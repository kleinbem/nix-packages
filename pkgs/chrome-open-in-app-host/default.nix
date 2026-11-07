# Native messaging host for the Open in App browser extension
# (kleinbem/chrome-open-in-app, host/). Ships the binary plus a ready
# manifest whose `path` points at it; nix-config links that manifest into
# each browser's NativeMessagingHosts dir.
#
# Updated by scripts/update-packages.sh (no upstream tags, so branch head).
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  nix-update-script,
  # Unpacked extension ID that may talk to the host.
  extensionIds ? [ "ngfknlddgkbipaimbaihckmaodkmndoa" ],
}:

buildGoModule (finalAttrs: {
  pname = "chrome-open-in-app-host";
  version = "0-unstable-2026-11-07";

  src = fetchFromGitHub {
    owner = "kleinbem";
    repo = "chrome-open-in-app";
    rev = "16554af66092d534dc8a688de90cc2c676d7a32c";
    hash = "sha256-Ji5IzZBsNd+99E7ofaUEqU7HS4UqgNzbso/3ayIVsQI=";
  };

  sourceRoot = "${finalAttrs.src.name}/host";

  vendorHash = null; # standard library only

  ldflags = [
    "-s"
    "-w"
  ];

  postInstall = ''
    mv $out/bin/host $out/bin/chrome-open-in-app-host
    mkdir -p $out/etc/chromium/native-messaging-hosts
    cat > $out/etc/chromium/native-messaging-hosts/com.kleinbem.open_in_app.json <<JSON
    ${builtins.toJSON {
      name = "com.kleinbem.open_in_app";
      description = "Native Host for Open in App Chrome Extension";
      path = "@out@/bin/chrome-open-in-app-host";
      type = "stdio";
      allowed_origins = map (id: "chrome-extension://${id}/") extensionIds;
    }}
    JSON
    substituteInPlace $out/etc/chromium/native-messaging-hosts/com.kleinbem.open_in_app.json \
      --replace-fail @out@ $out
  '';

  passthru.updateScript = nix-update-script { extraArgs = [ "--version=branch" ]; };

  meta = {
    description = "Native messaging host for the Open in App browser extension";
    homepage = "https://github.com/kleinbem/chrome-open-in-app";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "chrome-open-in-app-host";
  };
})
