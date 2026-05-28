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
#   Each module is wrapped by the scaffold so that, regardless of who imports
#   it, two things are true:
#
#     1. The universal overlay is applied to `pkgs`, so `pkgs.internal.*`,
#        `pkgs.lib.internal.*`, and `pkgs.inputs` all resolve.
#     2. Flake context is injected as module arguments (with `mkDefault`
#        priority, so a downstream consumer's own specialArgs take precedence).
#
#   This means your module function can destructure any of:
#
#     { config, lib, pkgs, ... }          # Standard NixOS module args
#     { inputs, modules, overlays,        # Injected by the scaffold wrapper
#       systems, packages, ... }
#
#   The wrapping applies identically whether this module is consumed by one of
#   the flake's own systems/ configurations OR imported by a downstream flake
#   through the `nixosModules` output, so it is safe to reference
#   `pkgs.internal.*` in option defaults below.
#
# HOW TO USE MODULES IN SYSTEM CONFIGURATIONS:
#   In your system config (e.g., systems/x86_64-linux/example-host/default.nix),
#   import modules from the module tree passed as a module argument:
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
