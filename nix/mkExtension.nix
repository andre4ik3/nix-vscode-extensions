# The result of this function is an attrset where
# each `${publisher}.${name}` maps to a function `{ mktplcRef, vsix } -> (Derivation | { publisher })`
# Each Derivation is produced via the overridable `buildVscodeMarketplaceExtension` function (defined below).
# The `{ publisher }` attrset is provided for compatibility with `groupBy`.

# Custom fixes are loaded via `mkExtensionLocal`.

{
  pkgs,
  system,
}:
let
  inherit (pkgs) lib;

  makeOverridable =
    f: args:
    lib.customisation.makeOverridable f (
      if builtins.isFunction args then
        let
          x = args (f x);
        in
        x
      else
        args
    );

  buildVscodeMarketplaceExtension = makeOverridable pkgs.vscode-utils.buildVscodeMarketplaceExtension;

  buildVscodeExtension = makeOverridable pkgs.vscode-utils.buildVscodeExtension;

  # We don't modify callPackage because extensions
  # may use its original version
  pkgs' = pkgs // {
    vscode-utils = pkgs.vscode-utils // {
      inherit buildVscodeMarketplaceExtension buildVscodeExtension;
    };
  };

  applyMkExtension = builtins.mapAttrs (
    publisher: builtins.mapAttrs (name: f: { mktplcRef, vsix }@extensionConfig: f extensionConfig)
  );

  mkExtensionLocal = applyMkExtension (import ../extensions { pkgs = pkgs'; });

  extensionsRemoved = (import ./removed.nix).${system} or [ ];
  chooseMkExtension =
    self:
    {
      mktplcRef,
      vsix,
      engineVersion,
      platform,
      isRelease,
    }@extensionConfig:
    let
      mkExtension =
        (self.${mktplcRef.publisher} or { }).${mktplcRef.name} or (
          if builtins.elem "${mktplcRef.publisher}.${mktplcRef.name}" extensionsRemoved then
            # In `./nix/overlay.nix`, there is a check whether the result is a derivation.
            _: { vscodeExtPublisher = mktplcRef.publisher; }
          else
            buildVscodeMarketplaceExtension
        );

      extension = (mkExtension { inherit mktplcRef vsix; }) // {
        passthru = extensionConfig;
      };
    in
    extension;
in
builtins.foldl' lib.attrsets.recursiveUpdate { } [
  mkExtensionLocal
  { __functor = chooseMkExtension; }
]
