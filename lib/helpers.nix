# ── Library: helpers.nix ──────────────────────────────────────────────────────
#
# NON-DEFAULT LIBRARY FILES:
#   Any `.nix` file in `lib/` other than `default.nix` is placed under
#   its filename in the library namespace:
#
#     lib/helpers.nix  ->  lib.helpers.concatWithSep
#                              lib.helpers.optionalList
#
#   Like default.nix, this file can be either a plain attrset or a function.
#   If it's a function, it receives `allFlakeContext` (with `lib` containing
#   all sibling libraries). This means you can reference functions from
#   default.nix or other library files.
#
# PLAIN ATTRSET FORM (shown here):
#   If your library doesn't need access to flake context, inputs, or other
#   libraries, you can export a plain attrset. The scaffolding detects this
#   automatically (by checking if the imported value is a function) and
#   uses it as-is without calling it.
#
{
  # Concatenate a list of strings with a separator.
  concatWithSep = sep: list:
    builtins.concatStringsSep sep list;

  # Return the list if the condition is true, otherwise empty list.
  # Useful for conditionally adding to `buildInputs` and similar.
  optionalList = cond: list:
    if cond then list else [];
}
