let
  pkgs = import <nixpkgs> {};

  dappSrc = builtins.fetchGit rec {
    name = "dapptools-${rev}";
    url = https://github.com/dapphub/dapptools;
    # provides solc 0.5.16
    rev = "96c4bfd228cf6e116c2d93f3e89d795bcd8b5511";
    ref = "master";
  };
  dapptools = import dappSrc {};

in
  pkgs.mkShell {
    src = null;
    name = "k-uniswap";
    buildInputs = with pkgs; [
      gnused
      dapptools.dapp
    ];
    shellHook = ''
      export NIX_PATH="nixpkgs=${toString pkgs.path}"
      export DAPPTOOLS=${dappSrc}
    '';
  }
