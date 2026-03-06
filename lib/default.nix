# DEFAULT LIBRARY FILES:
#   `lib/default.nix` is special in that, unlike the non-default libraries,
#   all exports are placed into the flattened library namespace.
#
#     lib/scaffold.nix  ->  lib.scaffold.mkFlake
#     lib/default.nix   ->  lib.mkFlake
#
#   This library is a function, and as such it receives `allFlakeContext`
#   (with `lib` containing all sibling libraries). This means you can reference functions from
#   scaffold.nix or other library files.
{lib, ...}: {
  inherit (lib.scaffold) mkFlake;
}
