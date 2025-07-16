{ pkgs, name, lib, system }:

{
  devShell = pkgs.mkShell {
    name = "${name}-dev-shell";
    
    nativeBuildInputs = with pkgs; [
      zigpkgs.master
      
      # Development tools
      coreutils
      gnumake
      
      # Code formatting and analysis
      nodePackages.prettier
      
      # Useful utilities
      ripgrep
      fd
      jq
    ];
    
    # Environment variables
    ZIG_PROJECT_NAME = name;
    
    shellHook = ''
      echo "🚀 Welcome to the ${name} development environment!"
      echo "ℹ️  Available commands:"
      echo "   zig build       - Build the project"
      echo "   zig build run   - Build and run the project"
      echo "   zig build test  - Run tests"
      
      # Create required directories
      mkdir -p src
      
      # Create main.zig if it doesn't exist
      if [ ! -f src/main.zig ]; then
        if [ -f main.zig ]; then
          cp main.zig src/
          echo "ℹ️  Copied main.zig to src/main.zig"
        fi
      fi
      
      # Set PS1 with project info
      export PS1="\[\033[1;32m\][${name}:\w]\[\033[0m\] $ "
      
      # Create .envrc for direnv users if it doesn't exist
      if [ ! -f .envrc ]; then
        cat > .envrc << EOF
export ZIG_PROJECT_NAME="${name}"
export PATH="\$PWD/zig-out/bin:\$PATH"
EOF
        echo "ℹ️  Created .envrc file"
        echo "   Run 'direnv allow' if you have direnv installed"
      fi
    '';
  };
}