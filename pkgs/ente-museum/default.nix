# ente's self-hosted server ("museum"), packaged from source instead of
# consuming ghcr.io/ente-io/server — that image went to a bare 403 Forbidden
# (even listing tags), confirmed live 2026-09-24, and ente's own compose.yaml
# no longer references a prebuilt image at all (`build: context: .`). Source
# build sidesteps depending on any registry's continued goodwill entirely.
#
# Pinned to a commit SHA (not a tag): ente's GitHub tags track their client
# app releases, not the server specifically — a commit SHA is the
# unambiguous "this exact server source" reference. Bump by picking a new
# commit off https://github.com/ente-io/ente/commits/main (server/ changes
# infrequently) and re-running the build once with `hash`/`vendorHash` set to
# `lib.fakeHash` to get the real values from the mismatch error.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "ente-museum";
  version = "unstable-2026-09-23";

  src = fetchFromGitHub {
    owner = "ente-io";
    repo = "ente";
    rev = "76fa80d48fb60a45e64c91a5732eaf3052a6854e";
    hash = "sha256-b6b0EYu/6pl4GPRqMNPYPQUUHGCKX9ymkGl522YcBhs=";
  };

  # go.mod lives at server/go.mod, not the repo root — this is a monorepo
  # (mobile/web/desktop/server all together).
  modRoot = "server";
  vendorHash = "sha256-iiytPsRsu0iBqDwSr5NavRfWOd/7ZLd5KBpLDuTkbz0=";

  subPackages = [ "cmd/museum" ];

  # Matches upstream's own Dockerfile build (CGO_ENABLED=0, -trimpath).
  env.CGO_ENABLED = 0;

  postInstall = ''
    # museum resolves configurations/migrations/mail-templates/web-templates
    # via hardcoded RELATIVE paths from its own working directory (see
    # server/pkg/utils/config/config.go and cmd/museum/main.go — not
    # configurable via flags or env). Bundle them alongside the binary and
    # let the systemd unit set WorkingDirectory here, rather than patching
    # upstream's path handling.
    mkdir -p $out/share/ente-museum
    cp -r $src/server/configurations $out/share/ente-museum/configurations
    cp -r $src/server/migrations $out/share/ente-museum/migrations
    cp -r $src/server/mail-templates $out/share/ente-museum/mail-templates
    cp -r $src/server/web-templates $out/share/ente-museum/web-templates
    ln -s $out/bin/museum $out/share/ente-museum/museum
  '';

  meta = with lib; {
    description = "Server for ente, an end-to-end encrypted photo/2FA vault (self-hosted 'museum')";
    homepage = "https://github.com/ente-io/ente/tree/main/server";
    license = licenses.agpl3Only;
    platforms = platforms.linux;
    mainProgram = "museum";
  };
}
