# Packages and NixOS modules that are ours in nixpkgs but so far only exist on
# a pull request (nixpkgs-prs.json). They are built from the PR's own files,
# pinned to one commit, against the nixpkgs they are called with: the fleet
# runs exactly what the PR contains, never a copy.
#
# An entry is pinned with the pin-nixpkgs-pr workflow and removed by the
# nixpkgs-prs-merged workflow once the fleet's nixpkgs has the packages in the
# same or a newer version.
{ lib }:
let
  registry = lib.importJSON ../nixpkgs-prs.json;

  tree =
    entry:
    builtins.fetchTree {
      type = "github";
      inherit (entry)
        owner
        repo
        rev
        narHash
        ;
    };

  byName = src: name: "${src}/pkgs/by-name/${lib.substring 0 2 name}/${name}/package.nix";

  allAttrs = lib.concatMap (entry: entry.attrs) (lib.attrValues registry);
in
assert lib.assertMsg (lib.allUnique allAttrs) "nixpkgs-prs.json: an attribute is in two entries";
{
  inherit registry;

  # Every entry's attributes. Each entry gets its own scope, so packages of
  # the same PR find each other (mesh-llm wants skippy-native-runtime) before
  # falling back to nixpkgs. An entry's `scope` names packages of the PR that
  # its attributes need but that aren't exported, such as berd's darwin-only
  # block-catch, which has its own PR.
  packages =
    pkgs:
    lib.concatMapAttrs (
      _: entry:
      let
        src = tree entry;
        scope = lib.makeScope pkgs.newScope (
          self:
          lib.genAttrs (entry.attrs ++ entry.scope or [ ]) (name: self.callPackage (byName src name) { })
        );
      in
      lib.getAttrs entry.attrs scope
    ) registry;

  # Every entry's NixOS modules, without their meta.doc: the NixOS manual,
  # which every host builds, only accepts chapters whose identifiers are in
  # nixpkgs' own redirects.json, so an out-of-tree chapter fails the build.
  # The manual gets it with the nixpkgs PR; the options are documented either
  # way. The module system passes only the arguments a module names, so the
  # wrapper takes over the module's own argument names.
  nixosModules = lib.concatMapAttrs (
    _: entry:
    lib.mapAttrs (
      _: path:
      let
        module = import "${tree entry}/${path}";
      in
      lib.setFunctionArgs (
        args:
        let
          evaluated = module args;
        in
        evaluated // { meta = builtins.removeAttrs (evaluated.meta or { }) [ "doc" ]; }
      ) (lib.functionArgs module)
    ) (entry.modules or { })
  ) registry;
}
