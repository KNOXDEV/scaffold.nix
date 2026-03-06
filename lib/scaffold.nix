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

  # Recursively determines all importable nix paths within a directory.
  # Returns a tree-like { filename1: ./filename1.nix, dirname1: {...}, ... } that mirrors the filesystem.
  getImportableTree = dir: let
    entries = readDirSafe dir;
    toImportableTree = name: type: let
      subPath = dir + "/${name}";
      isDirectory = type == "directory";
      isNixFile = type == "regular" && hasSuffix ".nix" name;
      withoutExtension = builtins.substring 0 ((builtins.stringLength name) - 4) name;
      defaultExists = builtins.pathExists (subPath + "/default.nix");
      dirContent = getImportableTree subPath;
    in
      if isNixFile
      then {"${withoutExtension}" = subPath;}
      else if isDirectory && defaultExists
      then {"${name}" = subPath;}
      else if isDirectory && !isEmptySet dirContent
      then {"${name}" = dirContent;}
      else {};
  in
    mergeFold toImportableTree entries;

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
    exportPackages = exports.packages or (context: {});
    exportNixosModules = exports.nixosModules or (context: {});
    exportNixosConfigurations = exports.nixosConfigurations or (context: {});
    exportOverlays = exports.overlays or (context: {});
    exportShells = exports.shells or (context: {});

    # Unlike the others, there IS a default function for exporting checks since its almost always desired.
    # However, if your checks are in a nested structure,
    # you will get errors from `nix` and need to implement your own flattening.
    exportChecks = exports.checks or (context: context.checks);

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
    # TODO: Currently, we oversimplify and do not augment these modules in such a way that they can
    # be used independently from the internal NixOSConfigurations (like we do with overlays).
    internalNixosModules = nixosModuleTree;

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
    allFlakeContext = {
      inputs = inputs;
      modules.nixos = internalNixosModules;
      overlays = internalOverlays;
      systems = internalNixosConfigs;
      packages = packageTree;
      templates = templatesTree;
      lib = internalLibsDefaultFlattened;
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
    defaultUniversalOverlay = final: prev: {
      inputs = inputs;
      lib = prev.lib // {${namespace} = internalLibsDefaultFlattened;};
      ${namespace} = createNestedScopes prev packageTree;
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
      templates = internalTemplates;
    };
  in
    # finally, form the final flake structure
    (eachSystem systems perSystemFlakeOutputs) // topLevelFlakeOutputs;
in
  # these are the "public exports" of this library
  {
    inherit eachSystem mkFlake mergeFold;
  }