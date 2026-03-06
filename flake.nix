{
  description = "Nix Flake scaffold that provides immediate productivity with self-hosting with Nix.";

  inputs = {
    # pinned to stable for now
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
  };

  outputs = inputs: let
    lib = import ./lib/scaffold.nix;
  in
    lib.mkFlake {
      inherit inputs;

      # The systems that your project's packages and devshells support running on.
      systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];

      # The root directory that is crawled for Nix expressions.
      # The scaffolding looks for these subdirectories:
      #   ./packages/   - Package definitions (callPackage style)
      #   ./overlays/   - Nixpkgs overlays
      #   ./modules/    - NixOS (and other) modules
      #   ./systems/    - Full NixOS system configurations
      #   ./lib/        - Shared library functions
      #   ./checks/     - Additional Flake checks
      #   ./shells/     - Development shells (per-system)
      #   ./templates/  - Nix flake templates
      src = ./.;

      # Optional: override the default namespace for internal packages.
      # Packages will be available under `pkgs.<namespace>.*`.
      # Default is "internal", so packages appear as `pkgs.internal.*`.
      # namespace = "internal";

      # Anything from your flake you want to export as a flake output
      # must be explicitly mapped here.
      exports = {
        # Per-system output. The function receives:
        #   pkgs      - nixpkgs extended with the namespace overlay
        #   system    - the current system string
        #   inputs    - all flake inputs
        #   modules   - { nixos = <module tree>; }
        #   overlays  - all processed overlays
        #   systems   - all NixOS configurations
        #   packages  - the raw package tree (paths, not derivations)
        #   checks    - all custom checks
        #   shells    - all custom devShells
        #   lib       - all custom libraries
        packages = {pkgs, ...}: {
          # Map internal packages to flake outputs.
          # After this, `nix build .#greeter` and `nix build .#hello` will work.
          default = pkgs.internal.greeter;
          greeter = pkgs.internal.greeter;
          hello = pkgs.internal.hello;
        };

        # Top-level output (not per-system).
        overlays = {overlays, ...}: {
          example = overlays.example;
        };

        # Top-level output. Map internal NixOS configurations to flake outputs.
        nixosConfigurations = {systems, ...}: {
          example-host = systems.example-host;
        };

        # Top-level output. Export modules for downstream consumers.
        # nixosModules = { modules, ... }: {
        #   example = modules.nixos.example;
        # };

        # Per-system output. Checks are exported by default (all of them),
        # so this is only needed if you want to filter or flatten.
        # checks = { checks, ... }: {
        #   example = checks.example;
        # };

        # Per-system output. Shells must be explicitly exported.
        # After this, `nix develop .#dev` will work.
        shells = {shells, ...}: {
          dev = shells.dev;
        };
      };
    };
}
