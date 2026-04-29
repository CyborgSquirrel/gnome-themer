{
  description = "GNOME color-scheme symlink manager";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.callPackage ./nix/package.nix { };
      });

      overlays.default = final: _prev: {
        gnome-themer = final.callPackage ./nix/package.nix { };
      };

      homeManagerModules.default = import ./nix/module.nix;
    };
}
