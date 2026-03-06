# ── NixOS Module: example ─────────────────────────────────────────────────────
#
# HOW NIXOS MODULES ARE DISCOVERED:
#   The scaffolding scans `modules/nixos/` with `getImportableTree`.
#   Each `.nix` file or directory-with/default.nix becomes a module in the
#   module tree. Subdirectories create nested namespaces:
#
#     modules/nixos/example.nix            -> modules.nixos.example
#     modules/nixos/hardware/gpu.nix       -> modules.nixos.hardware.gpu
#     modules/nixos/my-service/default.nix -> modules.nixos.my-service
#
# HOW MODULES RECEIVE CONTEXT:
#   NixOS modules in the scaffold receive `allFlakeContext` via `specialArgs`.
#   This means your module function can destructure any of:
#
#     { config, lib, pkgs, ... }          # Standard NixOS module args
#     { inputs, modules, overlays,        # From allFlakeContent (specialArgs)
#       systems, packages, ... }
#
#   Additionally, because the universal overlay is applied to all NixOS
#   configurations, `pkgs.internal.*` is available for referencing your
#   internal packages directly.
#
# HOW TO USE MODULES IN SYSTEM CONFIGURATIONS:
#   In your system config (e.g., systems/x86_64-linux/example-host/default.nix),
#   import modules from the module tree passed via specialArgs:
#
#     { modules, ... }: {
#       imports = with modules.nixos; [
#         example
#         # hardware.gpu
#       ];
#       # ... rest of config
#     }
#
# HOW TO EXPORT MODULES:
#   To make modules available to downstream flake consumers, map them in
#   `exports.nixosModules`:
#
#     exports.nixosModules = { modules, ... }: {
#       example = modules.nixos.example;
#     };
#
# MODULE STRUCTURE:
#   This follows the standard NixOS module pattern. You can use `options`
#   to declare configurable settings and `config` to define behavior.
#
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.scaffold-example;
in {
  # Declare options that users of this module can set.
  options.services.scaffold-example = {
    enable = lib.mkEnableOption "the scaffold example service";

    greeting = lib.mkOption {
      type = lib.types.str;
      default = "Hello from the scaffold!";
      description = "The greeting message to display.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      # Reference the internal greeter package via the universal overlay.
      default = pkgs.internal.greeter;
      description = "The greeter package to use.";
    };
  };

  # Define what happens when this module is enabled.
  config = lib.mkIf cfg.enable {
    # Install the package system-wide.
    environment.systemPackages = [cfg.package];

    # Create a simple systemd service as a demonstration.
    systemd.services.scaffold-example = {
      description = "Scaffold Example Service";
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${cfg.package}/bin/greeter";
      };
    };
  };
}
