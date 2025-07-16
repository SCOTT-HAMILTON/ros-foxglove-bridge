{
  inputs = {
    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/master";
    nixpkgs.follows = "nix-ros-overlay/nixpkgs";  # IMPORTANT!!!
  };
  outputs = { self, nix-ros-overlay, nixpkgs }:
    nix-ros-overlay.inputs.flake-utils.lib.eachDefaultSystem (system:
      let
        # The overlay logic from your first snippet
        applyDistroOverlay = rosOverlay: rosPackages:
          rosPackages
          // builtins.mapAttrs (
            rosDistro: rosPkgs: if rosPkgs ? overrideScope then rosPkgs.overrideScope rosOverlay else rosPkgs
            ) rosPackages;
        rosOverlay = final: prev: {
          foxglove-bridge = final.callPackage ./package.nix { };
        };

        rosDistroOverlays = final: prev: {
          # Apply the overlay to the ROS packages from nix-ros-overlay
          rosPackages = applyDistroOverlay (rosOverlay) prev.rosPackages;
        };

        pkgs = import nixpkgs {
          inherit system;
          overlays = [ nix-ros-overlay.overlays.default rosDistroOverlays ];
        };
      in {
        packages.default = pkgs.rosPackages.noetic.callPackage ./package.nix { };
        devShells.default = pkgs.mkShell {
          name = "Foxbridge shell";
          packages = [
            # ... other non-ROS packages
            (with pkgs.rosPackages.noetic; buildEnv {
              paths = [
                ros-core
                roslaunch
                foxglove-bridge
              ];
            })
          ];
        };
      });
  nixConfig = {
    extra-substituters = [ "https://ros.cachix.org" ];
    extra-trusted-public-keys = [ "ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo=" ];
  };
}
