{
  description = "nixnotes — the personal knowledge surface, declared: what you wrote, what somebody else wrote and you kept, and what it takes to be able to find any of it again";

  # The host/client modules still take `pkgs`/`config`/`lib` entirely from their consumer. The
  # cluster module is constructed by nixk3s' consumer factory, so nixk3s is its one deliberate
  # construction-time input; nixpkgs and nixidy remain check inputs and do not enter that module.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The renderer the cluster module defines into. A real input rather than a name in a comment:
    # without it there is no module system to evaluate the cluster side against, and `nix flake
    # check` would pass by checking nothing.
    nixidy = {
      url = "github:arnarg/nixidy";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # THE APP GRAMMAR THIS REPOSITORY CONSUMES, and now also the source of the consumer factory that
    # constructs the exported cluster module. Checks still compose the resulting module through the
    # real grammar and renderer rather than accepting a module that merely mentions `nixk3s.apps`.
    nixk3s = {
      url = "github:julian-corbet/nixk3s-corbet-ch";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixidy.follows = "nixidy";
    };
  };

  outputs = { self, nixpkgs, nixidy, nixk3s }:
    let
      lib = nixpkgs.lib;
      forAllSystems = lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
      pkgsFor = system: nixpkgs.legacyPackages.${system};
      clusterModule = import ./modules/cluster.nix {
        inherit (nixk3s.lib) mkConsumerModule;
      };
    in
    {
      # The cluster plane, all three sides of it. Composed into a nixidy environment ALONGSIDE the
      # app grammar, which declares the options this module defines into -- see modules/cluster.nix's
      # own header.
      nixidyModules.nixnotes = clusterModule;
      nixidyModules.default = clusterModule;

      # The host plane, for the commands a person works on their own corpus with. Here the system is
      # nix, so the backend installs; on Arch there is nothing to install FROM, so the policy module
      # IS that backend and publishes package-name lists for the host's own reconciler.
      nixosModules.nixnotes = ./modules/nixos.nix;
      nixosModules.default = ./modules/nixos.nix;

      systemManagerModules.nixnotes = ./modules/clients.nix;
      systemManagerModules.default = ./modules/clients.nix;

      # Policy alone, for a consumer that wants the computed lists and will wire them itself, plus
      # the raw catalogues for inspection without re-reading the files.
      lib.clientsPolicy = ./modules/clients.nix;
      lib.cluster = clusterModule;
      lib.engines = import ./lib/engines.nix { };
      lib.clients = import ./lib/clients.nix { };

      # `nix flake check` evaluates none of the module outputs on its own, so a green check on this
      # repository without these three files would cover nothing but flake syntax.
      checks = forAllSystems (system:
        let
          pkgs = pkgsFor system;

          # The cluster module, rendered through the real grammar and the real renderer, from the
          # placeholder values in examples/. Building the environment package forces the whole
          # manifest tree.
          env = nixidy.lib.mkEnv {
            inherit pkgs;
            modules = [
              nixk3s.nixidyModules.apps
              nixk3s.nixidyModules.addressing
              self.nixidyModules.nixnotes
              ./examples/all/values.nix
            ];
          };

          # The historical translator happened to render Recreate for the checked corpus because
          # every fixture used a node path. The catalogue's stronger fact is `singleWriter`; this
          # claim-backed variant proves the factory now carries that fact into the grammar too.
          claimEnv = nixidy.lib.mkEnv {
            inherit pkgs;
            modules = [
              nixk3s.nixidyModules.apps
              nixk3s.nixidyModules.addressing
              self.nixidyModules.nixnotes
              ./examples/all/values.nix
              {
                nixnotes.notebooks.example-wiki.state.space.hostPath = lib.mkForce null;
                nixnotes.notebooks.example-wiki.state.space.claim = "example-wiki-space";
              }
            ];
          };
        in
        {
          # 1. The host catalogue and its policy module, evaluated for real against
          # `lib.evalModules`: what a selection resolves to on every plane a backend reads, the
          # tripwire that fires the moment a package is assigned -- and the CLUSTER catalogue's own
          # integrity, including the property the notebook option's enum is built from.
          clients-eval = import ./checks/clients-eval.nix { inherit pkgs; };

          # 2. The cluster module's own resolution and every guard it makes, in BOTH directions: an
          # empty surface renders nothing at all, a declared one resolves, and each refusal gets a
          # declaration that must be refused -- including the ones that are unknown options rather
          # than guards, which is the whole claim of the design.
          cluster-eval = import ./checks/cluster-eval.nix {
            inherit pkgs lib nixidy;
            appsModule = nixk3s.nixidyModules.apps;
            addressingModule = nixk3s.nixidyModules.addressing;
            clusterModule = self.nixidyModules.nixnotes;
          };

          # 3. The manifests this surface actually PRODUCED, parsed and asserted field by field. A
          # module that type-checks can still mount a corpus where the software does not write, put
          # a rolling update in front of a single writer, or name one side's Secret from the other
          # -- none of that is an eval error and all of it matters.
          cluster-render = import ./checks/cluster-render.nix { inherit pkgs lib env; };

          # 4. The intentional safety correction in the factory migration: single-writer is a
          # catalogue fact, not an accident of choosing hostPath in the main render fixture.
          cluster-single-writer-render = import ./checks/cluster-single-writer-render.nix {
            inherit pkgs claimEnv;
          };
        });

      formatter = forAllSystems (system: (pkgsFor system).nixpkgs-fmt);
    };
}
