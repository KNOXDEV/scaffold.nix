# ── Check: example ────────────────────────────────────────────────────────────
#
# HOW CHECKS ARE DISCOVERED:
#   The scaffolding scans `checks/` with `getImportableTree`.
#   Each `.nix` file or directory/default.nix becomes a check.
#   Subdirectories create nested namespaces:
#
#     checks/example.nix              -> checks.example
#     checks/integration/api.nix      -> checks.integration.api
#
# HOW CHECKS RECEIVE CONTEXT:
#   Check files can be plain derivations or functions. If a function,
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
# HOW CHECKS ARE EXPORTED:
#   Unlike packages, checks are exported by default (all checks are
#   included in the flake's `checks` output). You can override this
#   with a custom `exports.checks` function if you need to flatten
#   nested structures or filter.
#
# RUNNING CHECKS:
#   `nix flake check` runs all checks for the current system.
#   Individual checks: `nix build .#checks.<system>.example`
#
{pkgs, ...}:
pkgs.stdenv.mkDerivation {
  name = "example-check";

  dontUnpack = true;

  # A check derivation must produce $out. The build phase is where you
  # run your tests or validations. A non-zero exit code = check failure.
  buildPhase = ''
    echo "Running example check..."
    # Place your test commands here, e.g.:
    #   ${pkgs.internal.greeter}/bin/greeter | grep -q "Hello"
    touch $out
  '';
}
