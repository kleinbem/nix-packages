{ buildGoModule, lib }:

buildGoModule {
  pname = "workspace-guardian";
  version = "0.1.0";
  src = ./.;
  vendorHash = null; # stdlib only

  meta = {
    description = "ATLAS workspace guardian — polls ai-logs.sh for journal errors and restarts failed container@ units";
    license = lib.licenses.mit;
    mainProgram = "workspace-guardian";
    platforms = lib.platforms.linux;
  };
}
