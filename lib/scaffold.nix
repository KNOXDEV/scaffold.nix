# Note: this is the heart of the scaffold and should not be deleted.
# You are however free to read or even modify its behavior.
let
  # common-use fold where you accumulate an attrset, merging as you go.
  mergeFold = f: attrset: let
    names = builtins.attrNames attrset;
    toMerged = accum: curr: accum // (f curr attrset.${curr});
  in
    builtins.foldl' toMerged {} names;

  # Returns true if the provided attrset is empty.
  isEmptySet = attrset: builtins.attrNames attrset == [];

  # instead of throwing an error, this version of readDir returns an empty set on missing path
  # (subject to TOCTOU bugs)
  readDirSafe = path:
    if builtins.pathExists path
    then builtins.readDir path
    else {};

  # Returns true if the provided str ends with the provided suffix, false otherwise.
  hasSuffix = suffix: str: let
    suffixLen = builtins.stringLength suffix;
    strLen = builtins.stringLength str;
    ending = builtins.substring (strLen - suffixLen) (-1) str;
  in
    if suffixLen > strLen
    then false
    else ending == suffix;

  # Same as builtins.mapAttrs, except nested attrsets are travered recursively.
  # The returned attrset has the same tree structure that was passed in, only the leaves are mapped.
  mapAttrsRecursive = f: attrset: let
    recurse = name: value:
      if builtins.isAttrs value
      then mapAttrsRecursive f value
      else f name value;
  in
    builtins.mapAttrs recurse attrset;

  # Returns an attrset of subdirectory names -> the full path they point to.
  getSubDirectories = dir: let
    entries = readDirSafe dir;
    toDirectories = name: type:
      if type == "directory"
      then {${name} = dir + "/${name}";}
      else {};
  in
    mergeFold toDirectories entries;

  # Recursively scans `dir` for regular files ending in `suffix`.
  # Returns a tree { fileName-without-suffix = path; dirName = { ... }; ... }
  # mirroring the filesystem. `suffix` must start with `.` (e.g. ".nix",
  # ".age") so the stripped key is a clean attribute name.
  #
  # Does NOT collapse `dir/default<suffix>` to the directory path -- the
  # collapse silently drops sibling files (e.g. `./secrets/foo/default.age`
  # alongside `./secrets/foo/other.age` would lose `other.age`). The internal
  # `.nix` alias adds the collapse separately because `import ./dir`
  # auto-resolves `default.nix`.
  #
  # Returns {} when `dir` is missing. Bounded recursion depth guards against
  # filesystem symlink cycles.
  scanDir = suffix: dir:
    if builtins.substring 0 1 suffix != "."
    then throw "scaffold.scanDir: suffix must start with '.', got: ${suffix}"
    else scanDirAtDepth 64 suffix dir;

  scanDirAtDepth = depth: suffix: dir:
    if depth <= 0
    then throw "scaffold.scanDir: directory recursion limit exceeded at ${toString dir} -- check for a symlink cycle."
    else let
      entries = readDirSafe dir;
      suffixLen = builtins.stringLength suffix;
      toEntry = name: type: let
        subPath = dir + "/${name}";
        isMatchingFile = type == "regular" && hasSuffix suffix name;
        isDirectory = type == "directory";
        withoutSuffix = builtins.substring 0 ((builtins.stringLength name) - suffixLen) name;
        dirContent = scanDirAtDepth (depth - 1) suffix subPath;
      in
        # Silently skip files literally named `.<suffix>` -- their stripped
        # key would be the empty string, which can't be addressed downstream.
        if isMatchingFile && withoutSuffix != ""
        then {${withoutSuffix} = subPath;}
        else if isDirectory && !isEmptySet dirContent
        then {${name} = dirContent;}
        else {};
    in
      mergeFold toEntry entries;

  # Collapse `{ default = <path>; ... }` to just `<path>`, mirroring how
  # `import ./dir` auto-resolves `dir/default.nix`. Internal only; applied
  # by `getImportableTree`. The collapse intentionally drops siblings next
  # to a `default.nix` -- this matches the long-standing nix convention
  # that `default.nix` is THE entry point for a directory.
  collapseDefaults = tree:
    builtins.mapAttrs (_: value:
      if builtins.isAttrs value
      then let
        recursed = collapseDefaults value;
      in
        if recursed ? default && !builtins.isAttrs recursed.default
        then recursed.default
        else recursed
      else value)
    tree;

  # Scanning for `.nix` files is the scaffold's bread and butter, so we
  # keep a named alias for internal use. Applies the `default.nix` collapse.
  getImportableTree = dir: collapseDefaults (scanDir ".nix" dir);

  # Borrowed from flake-utils.
  # A common case is to build the same structure for each system.
  # Instead of building the hierarchy manually or per prefix, iterate over each system and then re-build the hierarchy.
  eachSystem = systems: func: let
    toTopLevelSet = mergedSet: system: let
      systemSet = func system;
      toMergedSet = accum: key: accum // {${key} = (accum.${key} or {}) // {${system} = systemSet.${key};};};
    in
      builtins.foldl' toMergedSet mergedSet (builtins.attrNames systemSet);
  in
    builtins.foldl' toTopLevelSet {} systems;

  # The usage of this is heavily inspired by snowfall-lib, which is no longer under development
  # There are some key differences
  mkFlake = {
    inputs,
    src,
    ...
  } @ config: let
    # use provided systems, or fall back to default
    systems = config.systems or ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    namespace = config.namespace or "internal";
    nixpkgs = config.nixpkgs or inputs.nixpkgs;

    exports = config.exports or {};
    # Optional hook to extend the context object that gets threaded through libs,
    # overlays, modules, systems, and exports. Receives the full context and
    # returns an attrset whose contents are exposed under `context.extra.*`.
    # Use this when you have a project-specific convention the scaffold doesn't
    # know about (e.g., agenix `.age` files in ./secrets, home-manager configs
    # in ./homes) and you don't want to fork.
    #
    # The output is namespaced under `extra` rather than merged at the top
    # level so that the scaffold's context has a statically-known keyset.
    # This means downstream consumers can destructure their args naturally
    # (`{src, inputs, extra, ...}: ...`) without triggering an infinite
    # recursion during the destructure-existence check.
    #
    # The recursion rule: don't reference any field whose evaluation closes
    # the loop back to `extraContext` from inside it. The obvious one is
    # `ctx.extra`. But the same hazard applies to anything that evaluates a
    # wrapped NixOS module -- `ctx.systems`, or `ctx.modules.nixos` if you
    # try to instantiate a module from it -- because every wrapped module
    # imports the context module that itself forces `extra`. In practice,
    # safe inputs to `extraContext` are `src`, `inputs`, `lib`, `packages`
    # (paths only), `templates`, `overlays`.
    extraContext = config.extraContext or (_: {});

    exportPackages = exports.packages or (context: {});
    exportNixosModules = exports.nixosModules or (context: {});
    exportNixosConfigurations = exports.nixosConfigurations or (context: {});
    exportOverlays = exports.overlays or (context: {});
    exportShells = exports.shells or (context: {});

    # Unlike the others, there IS a default function for exporting checks
    # since its almost always desired. However, if your checks are in a nested structure,
    # you will get errors from `nix` and need to implement your own flattening.
    exportChecks = exports.checks or (context: context.checks);
    # Similar default export for templates. It doesn't supporting a hierarchical directory
    # structure but you may want to override its behavior anyways.
    exportTemplates = exports.templates or (context: context.templates);

    # Gather internal libraries
    libTree = getImportableTree (src + /lib);
    processLib = name: importPath: let
      importedLib = import importPath;
    in
      if builtins.isFunction importedLib
      then
        # libraries that expect arguments will get access to all other flake context (and libraries) recursively
        importedLib allFlakeContext
      else importedLib;
    internalLibs = mapAttrsRecursive processLib libTree;

    # default will get merged into the root attrset, so make sure your exported names dont conflict
    # TODO: error on conflicts?
    internalLibsDefaultFlattened = (internalLibs.default or {}) // internalLibs;

    # note: checks are platform specific so they are actually processed in the perSystem scope below.
    # (with the extended nixpkgs, etc)
    checksTree = getImportableTree (src + /checks);
    processChecksWithContext = context: name: importPath: let
      importedCheck = import importPath;
    in
      if builtins.isFunction importedCheck
      then
        # checks that expect arguments will get access to all other flake content
        importedCheck context
      else importedCheck;

    # note: shells are also platform specific and processed in the perSystem scope below.
    shellsTree = getImportableTree (src + /shells);
    processShellsWithContext = context: name: importPath: let
      importedShell = import importPath;
    in
      if builtins.isFunction importedShell
      then importedShell context
      else importedShell;

    # Gather templates and infer top level descriptions
    templatesTree = getSubDirectories (src + /templates);
    processTemplates = name: path: let
      flakeFile = path + /flake.nix;
      flake = import flakeFile;
      defaultDescription = "${name} template";
      description =
        if builtins.pathExists flakeFile
        then flake.description or defaultDescription
        else defaultDescription;
    in {${name} = {inherit path description;};};
    internalTemplates = mergeFold processTemplates templatesTree;

    # Gather packages recursively. Note that this is a tree of package paths that have not had callPackage called on them yet.
    # You can either pick a specific callPackage to use, use the universalOverlay, or create your own overlays to use.
    packageTree = getImportableTree (src + /packages);

    # Gather all overlays, detecting if they want special arguments and
    # passing them if necessary.
    overlaysTree = getImportableTree (src + /overlays);
    processOverlays = name: importPath: let
      importedOverlay = import importPath;
    in
      if isEmptySet (builtins.functionArgs importedOverlay)
      then importedOverlay
      else importedOverlay allFlakeContext;

    # you CAN override the universal overlay by creating an "overlays/default.nix" but this is not recommended.
    internalOverlays = {default = defaultUniversalOverlay;} // mapAttrsRecursive processOverlays overlaysTree;

    # Gather all NixOS Modules recursively. We don't have to import them manually
    # because the NixOS module system will do that for us.
    nixosModuleTree = getImportableTree (src + /modules/nixos);

    # A single module that applies the universal overlay and exposes the
    # flake context as module args. Every wrapped module imports this same
    # value; the explicit `key` tells the NixOS module system to deduplicate
    # it when N>1 wrapped modules are imported into the same configuration.
    #
    # Without the dedup, each wrapper would write `_module.args.<name>`
    # independently. `_module.args` is `lazyAttrsOf raw`; `raw` rejects
    # multiple definitions of the same key, so importing two wrapped modules
    # (e.g. `imports = with modules.nixos; [example hardware.gpu]`) would
    # fail with "_module.args.inputs is defined multiple times".
    #
    # specialArgs (when used by callers of nixosSystem) still wins over the
    # _module.args set here, because nixpkgs resolves module function args
    # as `specialArgs.${name} or config._module.args.${name}`.
    scaffoldContextModule = {
      _file = "${toString src}/lib/scaffold.nix";
      key = "scaffold:context:${toString src}";
      config = {
        nixpkgs.overlays = [internalOverlays.default];
        _module.args = builtins.removeAttrs allFlakeContext ["lib"];
      };
    };

    # Wrap each module path so it behaves identically whether it is consumed
    # inside our own nixosConfigurations or imported from an external flake
    # via the nixosModules output -- the universal overlay is applied,
    # `pkgs.${namespace}.*` resolves, and flake context is available as args.
    processNixosModules = _: modulePath: {
      _file = toString modulePath;
      imports = [
        scaffoldContextModule
        modulePath
      ];
    };
    internalNixosModules = mapAttrsRecursive processNixosModules nixosModuleTree;

    # parse systems folder and generate NixOS configs while providing custom modules
    systemsTree = getSubDirectories (src + /systems);
    processSystems = system: path: let
      configTree = getImportableTree path;
      processConfigs = name: osConfigModule:
        nixpkgs.lib.nixosSystem {
          system = system;
          modules = [universalNixosModule osConfigModule];
          # we include everything except lib, as we dont want to override the default lib.
          # you can still reference `pkgs.lib.internal`
          specialArgs = builtins.removeAttrs allFlakeContext ["lib"];
        };
    in
      builtins.mapAttrs processConfigs configTree;
    internalNixosConfigs = mergeFold processSystems systemsTree;

    # This gets passed to basically everything as additional context.
    # You can very easily recurse infinitely if you reference something you shouldn't.
    # Note that the scaffold's keys are statically known here; user extensions
    # live under `extra` (a single key whose value is the lazy user attrset).
    # See the `extraContext` doc comment above for why.
    allFlakeContext = {
      inputs = inputs;
      src = src;
      modules.nixos = internalNixosModules;
      overlays = internalOverlays;
      systems = internalNixosConfigs;
      packages = packageTree;
      templates = internalTemplates;
      lib = internalLibsDefaultFlattened;
      extra = extraContext allFlakeContext;
    };

    # Recursively generates new nested package scopes for each subtree.
    createNestedScopes = super: tree: let
      scope = self: let
        processTree = name: value:
          if builtins.isAttrs value
          then createNestedScopes self value
          else self.callPackage value {};
      in
        builtins.mapAttrs processTree tree;
    in
      nixpkgs.lib.makeScope super.newScope scope;

    # By default, we apply a universal overlay that tucks all internal packages under
    # a series of isolated nested scopes, named after the `namespace` config.
    # We also make sure to include our internal libs, and inputs.
    defaultUniversalOverlay = final: prev: let
      existingNamespace = prev.${namespace} or {};
      existingLibNamespace = prev.lib.${namespace} or {};
      newLib = {${namespace} = internalLibsDefaultFlattened // existingLibNamespace;};
    in {
      inputs = inputs;
      lib = prev.lib // newLib;
      # Merge with any existing namespace scope so multiple scaffold flakes can
      # coexist in the same pkgs (e.g. a downstream flake importing a module
      # from an upstream scaffold flake using the same namespace).
      #
      # Merge order: our packages on the left, the existing scope on the
      # right -- so downstream wins per-package-name. This is the safer
      # default: if a downstream scaffold has already populated
      # `pkgs.${namespace}.greeter`, an upstream wrapped module that closes
      # over `pkgs.${namespace}.greeter` will see downstream's. The scope
      # machinery (`callPackage`, `newScope`, `overrideScope'`) on the right
      # also wins, which preserves downstream's ability to override.
      #
      # If `prev.${namespace}` exists but isn't an attrset we throw rather
      # than silently dropping it -- it's almost certainly a namespace
      # config conflict the user wants to know about.
      ${namespace} =
        if !builtins.isAttrs existingNamespace
        then throw "scaffold: pkgs.${namespace} is already set to a non-attrset value; choose a different `namespace` in mkFlake to avoid the conflict."
        else createNestedScopes prev packageTree // existingNamespace;
    };

    # we apply the universal overlay to nixosConfigurations via this universal module.
    universalNixosModule = {...}: {
      nixpkgs.overlays = [internalOverlays.default];
    };

    # flake outputs that depend on the systems being supported
    perSystemFlakeOutputs = system: let
      extendedNixpkgs = nixpkgs.legacyPackages.${system}.extend internalOverlays.default;
      perSystemContext = {
        pkgs = extendedNixpkgs;
        system = system;
        checks = allChecks;
        shells = allShells;
      };
      allFlakeContextPlusSystem = allFlakeContext // perSystemContext;
      processChecks = processChecksWithContext allFlakeContextPlusSystem;
      allChecks = mapAttrsRecursive processChecks checksTree;
      processShells = processShellsWithContext allFlakeContextPlusSystem;
      allShells = mapAttrsRecursive processShells shellsTree;
    in {
      # the caller determines what gets exported
      packages = exportPackages allFlakeContextPlusSystem;
      checks = exportChecks allFlakeContextPlusSystem;
      devShells = exportShells allFlakeContextPlusSystem;
    };

    # In general, the user has to explicitly export anything internal to the flake.
    # This is mainly because flakes expect to be flat at the top-level,
    # while your filesystem hierarchy is not. Also, explicit is better.
    topLevelFlakeOutputs = {
      # TODO: when we export these, we need to intercept pkgs/lib and make sure the universalOverlay is available
      nixosModules = exportNixosModules allFlakeContext;
      nixosConfigurations = exportNixosConfigurations allFlakeContext;
      overlays = exportOverlays allFlakeContext;

      # libs and templates are all exported by default
      lib = internalLibsDefaultFlattened;
      templates = exportTemplates allFlakeContext;
    };
  in
    # finally, form the final flake structure
    (eachSystem systems perSystemFlakeOutputs) // topLevelFlakeOutputs;
in
  # these are the "public exports" of this library
  {
    inherit eachSystem mkFlake mergeFold scanDir;
  }
