{
  description = "Zig dev env.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";

    # Used for shell.nix
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  } @ inputs: let
    overlays = [
      (final: prev: {
        zigpkgs = inputs.zig.packages.${prev.system};
      })
    ];

    # Our supported systems are the same supported systems as the Zig binaries
    systems = builtins.attrNames inputs.zig.packages;
    name = "mapsy"; # Project name that will be used in Zig
  in {
    # You can add NixOS modules if needed in the future
    nixosModules = {
      default = { ... }: {
        # Empty for now, but you can add imports here
      };
    };
  } // flake-utils.lib.eachSystem systems (
    system: let
      pkgs = import nixpkgs {
        inherit system overlays;
      };
      
      lib = pkgs.lib;

      # Define a minimal shell for when the module doesn't exist yet
      minimalShell = pkgs.mkShell {
        name = "${name}-dev-shell";
        nativeBuildInputs = with pkgs; [
          zigpkgs.master
        ];
        
        shellHook = ''
          echo "Welcome to the ${name} development environment!"
          
          # Create a simple .envrc file to set the project name
          if [ ! -f .envrc ]; then
            echo "export PROJECT_NAME=${name}" > .envrc
            echo "Created .envrc with PROJECT_NAME=${name}"
          fi
          
          # Create project structure
          mkdir -p src nix
          
          # Create a simple build.zig if it doesn't exist
          if [ ! -f build.zig ]; then
            cat > build.zig << EOF
            const std = @import("std");
            
            pub fn build(b: *std.Build) void {
                // Standard target options
                const target = b.standardTargetOptions(.{});
                const optimize = b.standardOptimizeOption(.{});
            
                // Create executable with the project name
                const exe = b.addExecutable(.{
                    .name = "${name}",
                    .root_source_file = b.path("src/main.zig"),
                    .target = target,
                    .optimize = optimize,
                });
            
                // Install the executable
                b.installArtifact(exe);
            
                // Create a "run" step
                const run_cmd = b.addRunArtifact(exe);
                run_cmd.step.dependOn(b.getInstallStep());
                if (b.args) |args| {
                    run_cmd.addArgs(args);
                }
            
                // Create a "run" step alias
                const run_step = b.step("run", "Run mapsy");
                run_step.dependOn(&run_cmd.step);
            }
            EOF
            echo "Created build.zig with project name: ${name}"
          fi
          
          # Create devShell.nix template if it doesn't exist
          if [ ! -f nix/devShell.nix ]; then
            mkdir -p nix
            cat > nix/devShell.nix << EOF
            { pkgs, name, lib, system }:
            
            {
              devShell = pkgs.mkShell {
                name = "\${name}-dev-shell";
                nativeBuildInputs = with pkgs; [
                  zigpkgs.master
                ];
                
                shellHook = '''
                  echo "Welcome to the \${name} development environment!"
                ''';
              };
            }
            EOF
            echo "Created nix/devShell.nix template"
          fi
        '';
      };
      
      # Try to import the devShell module, fall back to minimal shell if it fails
      devShell = 
        if builtins.pathExists ./nix/devShell.nix 
        then (import ./nix/devShell.nix { inherit pkgs name lib system; }).devShell
        else minimalShell;
        
    in {
      # Make pkgs available
      legacyPackages = pkgs;

      # Create a package that can be built
      packages.default = pkgs.stdenv.mkDerivation {
        inherit name;
        src = ./.;
        
        nativeBuildInputs = [ pkgs.zigpkgs.master ];
        
        # Create a local Zig cache directory to avoid permission issues
        ZIG_GLOBAL_CACHE_DIR = "./zig-cache";
        
        # Update the build.zig to use our project name if needed
        preBuild = ''
          # Make sure src directory exists
          mkdir -p src
          
          # Create local Zig cache directory
          mkdir -p ./zig-cache
          
          # Copy main.zig to src directory if it exists at the root
          if [ -f main.zig ]; then
            cp main.zig src/
          fi
          
          # Create src/main.zig if it doesn't exist at all
          if [ ! -f src/main.zig ]; then
            cat > src/main.zig << EOF
            const std = @import("std");
            const math = std.math;
            const print = std.debug.print;

            // Calculate EV from F-stop, ISO, and shutter speed
            fn ev(n: f64, i: f64, s: f64) f64 {
                return math.log2(100.0 * ((n * n) / (i * s)));
            }

            // Calculate F-stop from EV, ISO, and shutter speed
            fn stop(e: f64, i: f64, s: f64) f64 {
                return math.sqrt((math.pow(f64, 2.0, e) * (i * s)) / 100.0);
            }

            // Calculate ISO from EV, F-stop, and shutter speed
            fn iso(n: f64, e: f64, s: f64) f64 {
                return 100.0 * (n * n) / (math.pow(f64, 2.0, e)) / s;
            }

            // Calculate shutter speed from EV, F-stop, and ISO
            fn shutter(n: f64, i: f64, e: f64) f64 {
                return (100.0 * (n * n)) / (math.pow(f64, 2.0, e)) / i;
            }

            pub fn main() !void {
                const stdout = std.io.getStdOut().writer();

                const fstop_val = 6.531972647421807;
                const iso_val = 100.0;
                const shutter_val = 1.0 / 48.0;
                const ev_val = 11.0;

                // Calculate and print EV
                const ev_result = ev(fstop_val, iso_val, shutter_val);
                try stdout.print("EV: {d:.6}\\n", .{ev_result});

                // Calculate and print F-stop
                const stop_result = stop(ev_val, iso_val, shutter_val);
                try stdout.print("F-stop: {d:.6}\\n", .{stop_result});

                // Calculate and print ISO
                const iso_result = iso(fstop_val, ev_val, shutter_val);
                try stdout.print("ISO: {d:.6}\\n", .{iso_result});

                // Calculate and print shutter speed
                const shutter_result = shutter(fstop_val, iso_val, ev_val);
                try stdout.print("Shutter speed: 1/{d:.6}\\n", .{1.0 / shutter_result});
            }
            EOF
            echo "Created default src/main.zig implementation"
          fi
          
          # Create build.zig if it doesn't exist
          if [ ! -f build.zig ]; then
            cat > build.zig << EOF
            const std = @import("std");
            
            pub fn build(b: *std.Build) void {
                // Standard target options
                const target = b.standardTargetOptions(.{});
                const optimize = b.standardOptimizeOption(.{});
            
                // Create executable
                const exe = b.addExecutable(.{
                    .name = "${name}",
                    .root_source_file = b.path("src/main.zig"),
                    .target = target,
                    .optimize = optimize,
                });
            
                // Install the executable
                b.installArtifact(exe);
            
                // Create a "run" step
                const run_cmd = b.addRunArtifact(exe);
                run_cmd.step.dependOn(b.getInstallStep());
                if (b.args) |args| {
                    run_cmd.addArgs(args);
                }
            
                // Create a "run" step alias
                const run_step = b.step("run", "Run mapsy");
                run_step.dependOn(&run_cmd.step);
            }
            EOF
          fi
        '';
        
        buildPhase = ''
          # Use the local cache directory for Zig
          zig build --global-cache-dir ./zig-cache
        '';
        
        installPhase = ''
          mkdir -p $out/bin
          if [ -f zig-out/bin/${name} ]; then
            cp zig-out/bin/${name} $out/bin/
          else
            echo "ERROR: Build output not found at zig-out/bin/${name}"
            echo "Current directory contents:"
            ls -la
            echo "zig-out directory contents (if it exists):"
            ls -la zig-out || echo "zig-out directory does not exist"
            exit 1
          fi
        '';
      };
      
      inherit devShell;

      # Add an app so it can be run with 'nix run'
      apps.default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/${name}";
      };
    });

  nixConfig = {
    extra-experimental-features = ["nix-command flakes" "ca-derivations"];
    allow-import-from-derivation = "true";
    extra-substituters = [
      "https://nix-community.cachix.org"

    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="

    ];
  };
}
