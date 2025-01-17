{
  description = "nixpkgs-kata-containers";

  inputs = {
    nixpkgs = { url = "github:nixos/nixpkgs/nixos-unstable"; };
  };

  outputs = inputs:
    let
      nameValuePair = name: value: { inherit name value; };
      genAttrs = names: f: builtins.listToAttrs (map (n: nameValuePair n (f n)) names);
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = genAttrs supportedSystems;
      filterPkg_ = system: (pkg: builtins.elem "${system}" (pkg.meta.platforms or [ "x86_64-linux" "aarch64-linux" ]));
      # TODO: we probably want to skip broken?
      filterPkgs = pkgs: pkgSet: (pkgs.lib.filterAttrs (filterPkg_ pkgs.system) pkgSet.${pkgs.system});
      filterHosts = pkgs: cfgs: (pkgs.lib.filterAttrs (n: v: pkgs.system == v.config.nixpkgs.system) cfgs);
      filterPkgs_ = pkgs: pkgSet: (builtins.filter (filterPkg_ pkgs.system) (builtins.attrValues pkgSet.${pkgs.system}));
      filterHosts_ = pkgs: cfgs: (builtins.filter (c: pkgs.system == c.config.nixpkgs.system) (builtins.attrValues cfgs));
      pkgsFor = pkgs: system: overlays:
        import pkgs {
          inherit system overlays;
          config.allowUnfree = true;
        };
      pkgs_ = genAttrs (builtins.attrNames inputs) (inp: genAttrs supportedSystems (sys: pkgsFor inputs."${inp}" sys []));
      fullPkgs_ = genAttrs supportedSystems (sys:
        pkgsFor inputs.nixpkgs sys [ inputs.self.overlay ]);
      mkSystem = pkgs: system: hostname:
        pkgs.lib.nixosSystem {
          system = system;
          modules = [(./. + "/hosts/${hostname}/configuration.nix")];
          specialArgs = { inherit inputs; };
        };

      hydralib = import ./lib/hydralib.nix;
    in rec {
      x = builtins.trace inputs.self.sourceInfo inputs.nixpkgs.sourceInfo;
      devShell = forAllSystems (system:
        pkgs_.nixpkgs.${system}.mkShell {
          name = "nixcfg-devshell";
          nativeBuildInputs = (with pkgs_.nixpkgs.${system}; [
            nixUnstable
          ]);
        }
      );

      packages = forAllSystems (system: fullPkgs_.${system}.kataPackages);
      pkgs = forAllSystems (system: fullPkgs_.${system});

      overlay = final: prev:
        let p = rec {
          kata-agent = prev.callPackage ./pkgs/kata-agent {};
          kata-kernel = prev.callPackage ./pkgs/kata-kernel {};
          kata-upstream-images = prev.callPackage ./pkgs/kata-upstream-images {};
          kata-images = prev.callPackage ./pkgs/kata-images {
            rootfsImage = prev.callPacakge ./pkgs/kata-images/make-ext4-fs.nix {};
          };
          kata-runtime = prev.callPackage ./pkgs/kata-runtime {};
        }; in p // { kataPackages = p; };

      nixosModules = {
        kata-containers = import ./modules/kata.nix;
      };
    };
}
