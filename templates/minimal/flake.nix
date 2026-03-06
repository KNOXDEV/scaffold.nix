# ── Template: minimal ─────────────────────────────────────────────────────────
#
# HOW TEMPLATES ARE DISCOVERED:
#   The scaffolding scans `templates/` for subdirectories. Each
#   subdirectory becomes a template in the flake's `templates` output.
#
#     templates/minimal/  ->  flake.templates.minimal
#
#   The scaffolding looks for a `flake.nix` in each template directory
#   and reads its `description` attribute (if present) for the template
#   metadata. The `path` is set to the template's directory automatically.
#
# HOW TEMPLATES ARE EXPORTED:
#   Unlike packages and modules, templates are exported automatically.
#   They appear in the flake's `templates` output without needing an
#   explicit `exports` mapping.
#
# USAGE:
#   Consumers of your flake can initialize a new project from this template:
#
#     nix flake init -t your-flake#minimal
#
{
  description = "A minimal Nix flake template that uses scaffold.nix";

  inputs = {
    # pinned to stable for now
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    # The scaffold as a library. Follows YOUR nixpkgs.
    scaffold.url = "github:KNOXDEV/scaffold.nix";
    scaffold.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs:
    # This is a minimal example of how you would use the scaffold as a library.
    # This is the minimum number of configuration you need to provide.
    inputs.scaffold.lib.mkFlake {
      inherit inputs;
      src = ./.;

      # To actually export anything, you will want to configure exporter functions.
      exports = {
      };
    };
}
