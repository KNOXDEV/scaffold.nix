# Scaffold.nix

Nix flake scaffold that provides immediate productivity with using NixOS, without additional abstractions.

## Getting Started

### Creating a new Nix flake

Within the directory your Nix flake will live in:

```bash
nix flake init -t github:KNOXDEV/scaffold.nix
git add .
# show all the currently available outputs:
nix flake show
```

This copies the entire scaffold into your project, giving you a working flake with example packages, modules, overlays, shells, checks, and a NixOS system configuration. It is not just a framework for getting started, its a resource for learning.
Every file is commented with documentation explaining how it is discovered, processed, and exported. 
Edit the examples or replace them with your own.

### Using scaffold.nix in an existing flake

If you already have a flake and want to use scaffold.nix as a library, add it as an input and call `mkFlake`:

```nix
# templates/minimal/flake.nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    scaffold.url = "github:KNOXDEV/scaffold.nix";
    scaffold.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs:
    inputs.scaffold.lib.mkFlake {
      inherit inputs;
      src = ./.;
      exports = {
        # map your internal packages, shells, modules, etc. to flake outputs here
      };
    };
}
```

You can also initialize the minimal template (the `flake.nix` above) directly:

```bash
nix flake init -t github:KNOXDEV/scaffold.nix#minimal
```

## Deploying a NixOS server

First, have a server running Linux, preferably [NixOS](https://nixos.org/) that you have SSH access to.
That can be a VPS, dedicated server, or Raspberry Pi.

If its already NixOS, copy the closure to the remote and rebuild:

```bash
# build the system configuration locally
nix build .#nixosConfigurations.example-host.config.system.build.toplevel
# copy it to the remote machine's Nix store
nix copy --to ssh://root@your-server ./result
# activate it on the remote
ssh root@your-server "nix-env -p /nix/var/nix/profiles/system --set $(readlink -f ./result) && /nix/var/nix/profiles/system/bin/switch-to-configuration switch"
```

If the server is running Linux but not NixOS yet, use can [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
to make the conversion.

## Testing your NixOS configuration locally

If your running NixOS on your host system already, you can use `build-vm` to spin up a local virtual machine running your image:

```bash
nixos-rebuild build-vm --flake .#example-host && ./result/bin/run-example-host-vm
```

## Customizing the NixOS configuration

NixOS has thousands of built-in options for configuring services, networking, users, and more. 
You enable features declaratively in your system configuration files under `systems/`.

For example, to run a [Vaultwarden](https://github.com/dani-garcia/vaultwarden) password manager on your server, add this to your host configuration:

```nix
{
  services.vaultwarden = {
    enable = true;
    config = {
      ROCKET_PORT = 8222;
      ROCKET_ADDRESS = "0.0.0.0";
    };
  };
}
```

The recommended way to discover what options are available is to use Ctrl+F in the [NixOS manual](https://nixos.org/manual/nixos/stable/), or use the [NixOS options search](https://search.nixos.org/options).

## Whats in this repo

The scaffold uses **convention-over-configuration**: where you place a file determines what it is. The core engine in `lib/scaffold.nix` scans the directory tree and automatically discovers all Nix expressions, wiring them together into a complete flake.

### Directory structure

```
.
├── flake.nix          # Entry point -- calls mkFlake with your configuration
├── packages/          # Package definitions (callPackage style)
│   ├── hello.nix      # Simple file-based package -> pkgs.internal.hello
│   └── greeter/       # Directory-based package   -> pkgs.internal.greeter
│       └── default.nix
├── modules/
│   └── nixos/         # NixOS modules
│       └── example.nix
├── overlays/          # Nixpkgs overlays
│   └── example.nix
├── systems/           # NixOS system configurations, grouped by architecture
│   └── x86_64-linux/
│       └── example-host/
│           └── default.nix
├── shells/            # Development shells
│   └── dev.nix
├── checks/            # Flake checks (tests, lints)
│   └── example.nix
├── lib/               # Shared library functions
│   ├── default.nix    # Exports merged into the root lib namespace
│   ├── helpers.nix    # Utility functions (available as lib.helpers.*)
│   └── scaffold.nix   # The core scaffold (mkFlake and auto-discovery logic)
└── templates/         # Flake templates for downstream consumers
    └── minimal/
        └── flake.nix
```

### How it hooks together

`flake.nix` calls `mkFlake`, which does the following:

1. **Discovery** -- scans each directory (`packages/`, `modules/nixos/`, `overlays/`, etc.) for `.nix` files and directories containing `default.nix`. Subdirectory nesting creates nested namespaces.
2. **Processing** -- imports and evaluates libraries and overlays, builds a universal overlay that makes all internal packages available under `pkgs.internal.*`, and assembles NixOS system configurations.
3. **Export** -- your `exports` block in `flake.nix` controls exactly which internal items become public flake outputs. Only what you explicitly map gets exported (with the exception of `checks`, `templates`, and `lib`, which are exported by default).

### Flake primitives

Each directory corresponds to a Nix flake primitive:

**Packages** (`packages/`) -- Standard `callPackage`-compatible Nix expressions. Drop a `.nix` file or a `directory/default.nix` and it becomes available as `pkgs.internal.<name>`. Nested directories create nested scopes (e.g., `packages/tools/lint.nix` becomes `pkgs.internal.tools.lint`). Export them in your `exports.packages` function to make them available via `nix build`.

**NixOS Modules** (`modules/nixos/`) -- Standard NixOS modules following the `options`/`config` pattern. They receive the usual NixOS arguments (`config`, `lib`, `pkgs`) plus all flake context via `specialArgs`, meaning you can access `inputs`, `modules`, `overlays`, etc. directly. Import them in your system configurations via the `modules.nixos` tree.

**Overlays** (`overlays/`) -- Nixpkgs overlays in the standard `final: prev: { ... }` form. If your overlay needs flake context (like access to internal package paths), write it as a function that accepts the context and returns the overlay. A universal overlay (`overlays.default`) is generated automatically -- it provides `pkgs.internal.*`, `pkgs.lib.internal.*`, and `pkgs.inputs`. Avoid naming your own overlay `default.nix` as it would replace this.

**System Configurations** (`systems/<arch>/<hostname>/`) -- Full NixOS configurations. The architecture is inferred from the parent directory name. Each host gets the universal overlay applied and receives all flake context through `specialArgs`, so you can import internal modules and reference `pkgs.internal.*` packages directly.

**Development Shells** (`shells/`) -- Development environments created with `mkShell`. They receive per-system context including `pkgs` with the universal overlay applied. Export them via `exports.shells` to use with `nix develop`.

**Checks** (`checks/`) -- Derivations that run as part of `nix flake check`. They receive per-system context. All checks are exported by default.

**Libraries** (`lib/`) -- Shared Nix functions available throughout the flake. `lib/default.nix` is special: its exports are merged into the root `lib` namespace. Other files are nested under their filename (e.g., `lib/helpers.nix` becomes `lib.helpers.*`). Libraries are always exported at the top level.

**Templates** (`templates/`) -- Each subdirectory with a `flake.nix` becomes a template. Templates are exported by default. Consumers can initialize from them with `nix flake init -t your-flake#template-name`.

### The exports block

The `exports` attrset in your `flake.nix` is the single point of control for what becomes a public flake output. Each key is a function that receives context and returns the outputs to expose:

```nix
exports = {
  # Per-system exports (receive pkgs, system, checks, shells, etc.)
  packages = { pkgs, ... }: { default = pkgs.internal.greeter; };
  shells   = { shells, ... }: { dev = shells.dev; };

  # Top-level exports (receive modules, overlays, systems, templates, etc.)
  nixosConfigurations = { systems, ... }: { my-host = systems.my-host; };
  nixosModules        = { modules, ... }: { example = modules.nixos.example; };
  overlays            = { overlays, ... }: { example = overlays.example; };
};
```