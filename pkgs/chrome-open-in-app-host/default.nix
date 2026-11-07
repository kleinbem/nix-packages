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
  version = "1.5.1-unstable-2026-10-16";

  src = fetchFromGitHub {
    owner = "kleinbem";
    repo = "chrome-open-in-app";
    rev = "b0f37010b2600aa627b2b8200f0d61ee301c2673";
    hash = "sha256-GOCTCvShd1fctF8NSIV0XHSXQQ6NK1+Peisqyc6BZ0E=";
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
