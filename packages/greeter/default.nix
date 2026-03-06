# ── Package: greeter ──────────────────────────────────────────────────────────
#
# HOW PACKAGES ARE DISCOVERED:
#   The scaffolding engine scans `packages/` using `getImportableTree`.
#   It discovers packages in two forms:
#     1. A directory with a `default.nix` (like this one)  -> name = directory name
#     2. A standalone `.nix` file (like ../hello.nix)       -> name = filename without .nix
#
#   Both forms produce a *path* in the package tree. The scaffolding does NOT
#   call `callPackage` on these paths itself. Instead, it creates isolated
#   nested scopes (via `nixpkgs.lib.makeScope`) and calls `callPackage`
#   within those scopes. This means the function signature below works
#   exactly like any standard nixpkgs package.
#
# HOW TO ACCESS THIS PACKAGE:
#   After the scaffolding applies its universal overlay, this package becomes
#   available in all contexts as:
#
#     pkgs.internal.greeter
#
#   Where `internal` is the default namespace (configurable via `namespace`
#   in the mkFlake config). Inside NixOS system configurations and overlays,
#   `pkgs.internal.*` is available automatically.
#
# EXPORTING TO THE FLAKE:
#   Internal packages are NOT automatically exported as flake outputs.
#   To make this package available as `nix build .#greeter`, map it in
#   the `exports.packages` function in your flake.nix:
#
#     exports.packages = { pkgs, ... }: {
#       greeter = pkgs.internal.greeter;
#     };
#
# FUNCTION ARGUMENTS:
#   The arguments below are injected by `callPackage`. You can request any
#   package or function from nixpkgs, plus anything else in the same scope.
#   For example, if you had another package `utils` in packages/, you
#   could add `utils` to the argument list and it would resolve automatically.
#
{
  lib,
  stdenv,
  bash,
}:
stdenv.mkDerivation {
  pname = "greeter";
  version = "0.1.0";

  # For a real package, you would set `src = ./.;` to include sibling files.
  # This example generates source inline for simplicity.
  dontUnpack = true;

  buildPhase = ''
    mkdir -p $out/bin
    cat > $out/bin/greeter <<SCRIPT
    #!${bash}/bin/bash
    echo "Hello from the scaffold template!"
    SCRIPT
    chmod +x $out/bin/greeter
  '';

  meta = with lib; {
    description = "A simple greeter to demonstrate the scaffold package layout";
    license = licenses.mit;
  };
}
