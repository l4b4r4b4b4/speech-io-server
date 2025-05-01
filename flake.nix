{
  description = "Development environment for speech-io-server";

  # Flake inputs
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  # Flake outputs
  outputs = {
    self,
    nixpkgs,
  }: let
    # Systems supported
    allSystems = [
      "x86_64-linux" # 64-bit Intel/AMD Linux
      "aarch64-linux" # 64-bit ARM Linux
      "x86_64-darwin" # 64-bit Intel macOS
      "aarch64-darwin" # 64-bit ARM macOS
    ];

    # Helper to provide system-specific attributes
    forAllSystems = f:
      nixpkgs.lib.genAttrs allSystems (system:
        f {
          pkgs = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
              # Disable tests for problematic packages
              permittedInsecurePackages = [
                "python3.11-jupyter-server-2.15.0"
              ];
              packageOverrides = pkgs: {
                python311Packages = pkgs.python311Packages.override {
                  overrides = python-self: python-super: {
                    # Disable tests for jupyter packages
                    jupyter-server = python-super.jupyter-server.overridePythonAttrs (old: {
                      doCheck = false;
                      doInstallCheck = false;
                    });
                    jupyterlab = python-super.jupyterlab.overridePythonAttrs (old: {
                      doCheck = false;
                      doInstallCheck = false;
                    });
                    jupyter = python-super.jupyter.overridePythonAttrs (old: {
                      doCheck = false;
                      doInstallCheck = false;
                    });
                  };
                };
              };
            };
          };
        });
  in {
    # Development environment output
    devShells = forAllSystems ({pkgs}: let
      # Define CUDA paths - directly matching versions with what PyTorch expects
      cudatoolkit = pkgs.cudaPackages.cudatoolkit;
      cudnn = pkgs.cudaPackages.cudnn;

      pythonPkgs = with pkgs.python311Packages; [
        pip
        virtualenv
        ipykernel
      ];

      # Create FHS environment - this is the key part from your working example
      uaiFhsEnv = pkgs.buildFHSEnv {
        name = "uai-fhs-env";
        targetPkgs = pkgs': (with pkgs';
          [
            # Core system tools
            neofetch
            lolcat
            python311
            git
            git-lfs
            deno
            nvtopPackages.full
            btop
            zed
            xdg-utils
            # CUDA
            cudatoolkit
            cudnn

            # Development tools
            gh
            gnumake
            curl
            openssl

            # System libraries
            gcc
            glibc
            glibc.dev
            stdenv.cc.cc.lib
            zlib
            zlib.dev

            # Multimedia libraries
            ffmpeg-full
            libsndfile
            # Additional audio processing dependencies
            alsa-lib
            portaudio
            pulseaudioFull
          ]
          ++ pythonPkgs);

        profile = ''
          echo "Operating System environment."
          neofetch | lolcat
          # Export BUN_VERSION for Docker builds
          export BUN_VERSION=$(bun --version)
          echo "Using Bun version: $BUN_VERSION"

          # Set up library paths and environment variables for CUDA
          export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath [
            cudatoolkit
            cudnn
            pkgs.stdenv.cc.cc.lib
          ]}:$LD_LIBRARY_PATH

          export CUDA_HOME="${cudatoolkit}"
          export CUDA_PATH="${cudatoolkit}"
          export PATH="${cudatoolkit}/bin:$PATH"
          export CPATH="${cudatoolkit}/include:$CPATH"
          export LIBRARY_PATH="${cudatoolkit}/lib64:$LIBRARY_PATH"
          export NVCC="${cudatoolkit}/bin/nvcc"
          export EXTRA_LDFLAGS="-L${cudatoolkit}/lib64 -L${cudnn}/lib"
          export EXTRA_CFLAGS="-I${cudatoolkit}/include"

          # Python/virtualenv setup
          export PYTHONPATH=""
          export VIRTUAL_ENV_DISABLE_PROMPT=1

          echo "=== Sovereign AI Development Environment ==="
          echo ""
          echo "Available commands:"
          echo "  setup_environment     - Set up Python venv and install dependencies"
          echo ""
        '';

        # This is the script that runs when you start the FHS environment
        runScript = ''
          # Initialize requirements.txt files
          PLATFORM_ROOT=$(pwd)

          # Setup Python function
          setup_environment() {
            # Create and activate virtual environment if it doesn't exist
            if [ ! -d ".venv" ]; then
              echo "Creating new virtual environment..."
              ${pkgs.python311Packages.virtualenv}/bin/virtualenv .venv
            fi

            # Ensure we're in the virtual environment
            source .venv/bin/activate

            # Upgrade pip and install requirements if needed
            if [ ! -f ".venv/.requirements-installed" ]; then
              echo "Installing Python packages..."
              python -m pip install --upgrade pip

              # Install from requirements-base.txt
              python -m pip install -r app/requirements.txt

              # Setup Jupyter kernel
              python -m ipykernel install --user --name=speech-io-server --display-name "Python (Speech IO Server)"

              # Mark requirements as installed
              touch .venv/.requirements-installed
            fi

            # Install deno jupyter
            deno jupyter --install
            echo "Python environment setup complete!"
          }

          # Create diagnostics script if it doesn't exist
          if [ ! -d "$PLATFORM_ROOT/scripts" ]; then
            mkdir -p "$PLATFORM_ROOT/scripts"
          fi

          if [ ! -f "$PLATFORM_ROOT/scripts/cuda_diagnostics.py" ]; then
            cat > "$PLATFORM_ROOT/scripts/cuda_diagnostics.py" << 'EOF'
          import sys
          import subprocess
          import platform

          def print_header(title):
              print("\n" + "=" * 40)
              print(f" {title}")
              print("=" * 40)

          def main():
              print_header("SYSTEM INFORMATION")
              print(f"Python version: {sys.version}")
              print(f"Platform: {platform.platform()}")
              print(f"Processor: {platform.processor()}")

              try:
                  # Check for CUDA with PyTorch
                  print_header("PYTORCH CUDA CHECK")
                  try:
                      import torch
                      print(f"PyTorch version: {torch.__version__}")
                      print(f"CUDA available: {torch.cuda.is_available()}")
                      if torch.cuda.is_available():
                          print(f"CUDA version: {torch.version.cuda}")
                          print(f"CUDA device count: {torch.cuda.device_count()}")
                          for i in range(torch.cuda.device_count()):
                              print(f"  Device {i}: {torch.cuda.get_device_name(i)}")
                      else:
                          print("CUDA is not available with PyTorch")
                  except ImportError:
                      print("PyTorch is not installed")

              except Exception as e:
                  print(f"Error during diagnostics: {e}")

          if __name__ == "__main__":
              main()
          EOF
          fi

          # Export the functions
          export -f setup_environment
          export -f start_development

          # Auto-run environment setup
          setup_environment

          # Run the diagnostics script
          echo "Running CUDA diagnostics..."
          python $PLATFORM_ROOT/scripts/cuda_diagnostics.py

          # Check if K3s is available, just for information
          check_k3s || echo "K3s access not configured. You may need to install it or fix configuration."

          # With this:
          echo ""
          echo "FHS environment is now fully initialized and ready!"
          echo "To launch Zed Editor in this environment, run:"
          echo "  zeditor ."
          echo ""
          echo "To set up Kubernetes services, you can now run:"
          echo "  setup_environment     - Set up Python venv and install dependencies"
          echo ""
          echo ""
          # Start an interactive shell
          # With these lines instead:
          # Set up a clean bash environment with good defaults
          export PS1='\[\033[1;32m\][fractal-ai]\[\033[0m\] \[\033[1;34m\]\w\[\033[0m\] $ '
          export HISTSIZE=5000
          export HISTFILESIZE=10000
          export HISTCONTROL=ignoreboth
          export PROMPT_COMMAND='history -a'
          export EDITOR=zed

          # Enable better command completion
          if [ -f /etc/bash_completion ]; then
            . /etc/bash_completion
          fi

          echo "Type 'exit' to leave the FHS environment."
          echo ""

          # Drop into a clean bash shell
          exec bash
        '';
      };
    in {
      default = pkgs.mkShell {
        packages = [
          uaiFhsEnv
        ];

        shellHook = ''
          echo "Starting FHS environment for AI development with CUDA support..."
          exec ${uaiFhsEnv}/bin/uai-fhs-env
        '';
      };
    });
  };
}
