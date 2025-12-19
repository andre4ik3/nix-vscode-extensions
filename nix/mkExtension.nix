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

  extensionsNixpkgs = pkgs.vscode-extensions;

  extensionsProblematic =
    # Problem:
    # Some arguments of the function that produces a derivation
    # are provided in the `let .. in` expression before the call to that function

    # TODO make a PR to nixpkgs to simplify overriding for these extensions
    [
      "anweber.vscode-httpyac"
      "chenglou92.rescript-vscode"
      # Wait for https://github.com/NixOS/nixpkgs/pull/383013 to be merged
      "vadimcn.vscode-lldb"
      "rust-lang.rust-analyzer"
    ];

  extensionsBuildVscodeExtension =
    # In Nixpkgs, these packages are constructed
    # using the `buildVscodeExtension` function.
    [
      "kilocode.kilo-code"
      "eamodio.gitlens"
      "vscode-icons-team.vscode-icons"
    ];

  mkExtensionNixpkgs = builtins.mapAttrs (
    publisher:
    builtins.mapAttrs (
      name: extension:
      let
        extensionId = "${publisher}.${name}";
        override = extension.override or (abort "The extension '${publisher}.${name}' doesn't have an 'override' attribute.");
      in
      if builtins.elem extensionId extensionsRemoved then
        _: { vscodeExtPublisher = publisher; }
      else
        { mktplcRef, vsix }@extensionConfig:
        let
          args = if builtins.elem extensionId extensionsBuildVscodeExtension then
            { inherit vsix; }
          else
            extensionConfig;
        in
        if builtins.elem extensionId extensionsProblematic then
          buildVscodeMarketplaceExtension extensionConfig
        else
          override (builtins.intersectAttrs (override.__functionArgs) args)
    )
  ) extensionsNixpkgs;

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
  mkExtensionNixpkgs
  mkExtensionLocal
  { __functor = chooseMkExtension; }
]
