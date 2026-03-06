# ── Overlay: example ──────────────────────────────────────────────────────────
#
# HOW OVERLAYS ARE DISCOVERED:
#   The scaffolding scans `overlays/` with `getImportableTree`.
#   Each `.nix` file or directory-with/default.nix becomes an overlay.
#
# TWO FORMS OF OVERLAYS:
#
#   1. Plain overlay (no outer arguments):
#        final: prev: { ... }
#      Used as-is. This is the standard nixpkgs overlay form.
#
#   2. Overlay with flake context (shown here):
#        { packages, inputs, ... }: final: prev: { ... }
#      The scaffolding detects that the outer function has named arguments
#      and automatically calls it with `allFlakeContext`, which contains:
#        {
#          inputs    - all flake inputs
#          modules   - { nixos = <module tree>; }
#          overlays  - all processed overlays
#          systems   - all NixOS configurations
#          packages  - the raw package tree (paths, not derivations)
#          templates - discovered template directories
#          lib       - all libraries
#        }
#      This lets your overlay reference internal packages or inputs.
#
# IMPORTANT: `overlays/default.nix` IS SPECIAL
#   If you create `nix/overlays/default.nix`, it REPLACES the built-in
#   universal overlay entirely. The universal overlay is what provides:
#     - pkgs.internal.*  (all your packages in nested scopes)
#     - pkgs.lib.internal.*  (all your libraries)
#     - pkgs.inputs  (all flake inputs)
#   Overriding it is NOT recommended unless you know what you're doing.
#   Name your custom overlays anything else (like this file: `example.nix`).
#
# HOW TO EXPORT OVERLAYS:
#   Overlays are not exported automatically (unlike libraries). To make
#   them available as flake outputs, map them in `exports.overlays`:
#
#     exports.overlays = { overlays, ... }: {
#       example = overlays.example;
#     };
#
# NOTE ON THE UNIVERSAL OVERLAY:
#   The scaffolding always applies a "universal overlay" to any nixpkgs
#   instance it creates (for per-system outputs and NixOS configurations).
#   This overlay makes `pkgs.internal.*` and `pkgs.lib.internal.*` available.
#   Your custom overlays here are discovered and stored, but are NOT
#   automatically applied -- you choose where to use them (e.g. in modules
#   or exported as flake outputs for downstream consumers).
#
{packages, ...}: final: prev: {
  # This overlay demonstrates using the `packages` tree from allFlakeContent.
  # `packages` contains the raw paths from getImportableTree, so to actually
  # build them we use callPackage.
  #
  # Example: make `pkgs.my-greeter` available as a top-level package:
  my-greeter = final.callPackage packages.greeter {};
}
