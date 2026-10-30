# What the Berd behaviour test needs, all from one nixpkgs checkout: the package
# under test, llama-server and a small pinned model.
{ nixpkgs }:

let
  pkgs = import nixpkgs { };
in
{
  inherit (pkgs) berd;
  tools = pkgs.buildEnv {
    name = "berd-behaviour-tools";
    paths =
      with pkgs;
      [
        llama-cpp
        jq
        sqlite
        curl
      ]
      ++ lib.optionals stdenv.hostPlatform.isLinux [
        xvfb-run
        # EGL for WebKit where the host has no /run/opengl-driver (GitHub's Ubuntu runners)
        mesa
        libglvnd
      ];
  };
  model = pkgs.fetchurl {
    url = "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/9217f5db79a29953eb74d5343926648285ec7e67/qwen2.5-0.5b-instruct-q4_k_m.gguf";
    hash = "sha256-dKTajJ/bzRW9H20B1iFBDTHG/ACYb162h4JOe5PXqds=";
  };
}
