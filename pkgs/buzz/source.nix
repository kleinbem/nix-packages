{ fetchFromGitHub }:
let
  info = builtins.fromJSON (builtins.readFile ./source.json);
in
{
  inherit (info) version cargoHash;
  src = fetchFromGitHub {
    owner = "block";
    repo = "buzz";
    inherit (info) rev hash;
  };
}
