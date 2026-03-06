# ── Package: hello (standalone .nix file) ─────────────────────────────────────
#
# This file demonstrates the *standalone .nix file* form of package definition.
# The scaffolding treats any `.nix` file directly inside `packages/` as a
# package whose name is the filename without the `.nix` extension.
#
#   nix/packages/hello.nix  ->  pkgs.internal.hello
#
# Use this form for small, self-contained packages that don't need extra
# source files. For packages with source code, assets, or patches alongside
# the nix expression, use the directory-with/default.nix form instead
# (see ./greeter/default.nix).
#
{
  stdenv,
  lib,
}:
stdenv.mkDerivation {
  pname = "hello";
  version = "0.1.0";

  dontUnpack = true;

  buildPhase = ''
    mkdir -p $out/bin
    echo '#!/bin/sh' > $out/bin/hello
    echo 'echo "Hello, world!"' >> $out/bin/hello
    chmod +x $out/bin/hello
  '';

  meta = with lib; {
    description = "Minimal hello-world example as a standalone .nix package";
    license = licenses.mit;
  };
}
