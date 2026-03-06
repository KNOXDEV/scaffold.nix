# ── Shell: dev ────────────────────────────────────────────────────────────────
#
# HOW SHELLS ARE DISCOVERED:
#   The scaffolding scans `shells/` with `getImportableTree`.
#   Each `.nix` file or directory-with/default.nix becomes a shell.
#
#     shells/dev.nix      -> shells.dev
#     shells/ci/default.nix -> shells.ci
#
# HOW SHELLS RECEIVE CONTEXT:
#   Shell files can be plain derivations or functions. If a function,
#   it receives the full per-system context:
#
#     {
#       pkgs       - nixpkgs extended with the universal overlay
#       system     - the current system string
#       inputs     - all flake inputs
#       overlays   - all processed overlays
#       packages   - the raw package tree (paths, not derivations)
#       lib        - all libraries
#     }
#
# HOW SHELLS ARE EXPORTED:
#   Shells are NOT exported by default (similar to packages). To make them
#   available as `nix develop .#dev`, map them in `exports.shells`:
#
#     exports.shells = { shells, ... }: {
#       dev = shells.dev;
#     };
#
# USAGE:
#   After exporting, enter the shell with:
#
#     nix develop .#dev
#
#   You can also configure an `.envrc` for automatic shell activation
#   with direnv:
#
#     use flake .#dev
#
{pkgs, ...}:
pkgs.mkShell {
  # Internal packages are available via the universal overlay.
  packages = [
    pkgs.internal.greeter
    pkgs.internal.hello
  ];

  # Environment variables for development.
  env = {
    # GREETING = "Hello, developer!";
  };
}
