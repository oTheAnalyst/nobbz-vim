{
  wrapNeovimUnstable,
  neovim-unwrapped,
  neovimUtils,
  npins,
  vimPlugins,
  self',
  lib,
  lua-language-server,
  stylua,
  markdown-oxide,
  xclip,
  utf8proc,
  fetchurl,
  gettext,
  libiconv,
  libvterm-neovim,
  luajit,
  tree-sitter,
  rustPlatform,
}: let
  # The building of `deps` and `overrides` later on are shamelessly borrowed
  # from the neovim-nightly-overlay.
  # TODO: generate an importable nix expression in update script
  deps = lib.pipe ./deps.txt [
    builtins.readFile
    (lib.splitString "\n")
    (map (builtins.match "([A-Z0-9_]+)_(URL|SHA256)[[:space:]]+([^[:space:]]+)[[:space:]]*"))
    (lib.remove null)
    (lib.flip builtins.foldl' {}
      (acc: matches: let
        name = lib.toLower (builtins.elemAt matches 0);
        key = lib.toLower (builtins.elemAt matches 1);
        value = lib.toLower (builtins.elemAt matches 2);
      in
        acc
        // {
          ${name} =
            acc.${name}
            or {}
            // {
              ${key} = value;
            };
        }))
    (builtins.mapAttrs (lib.const fetchurl))
  ];

  overrides = {
    gettext = gettext.overrideAttrs {
      src = deps.gettext;
    };

    # pkgs.libiconv.src is pointing at the darwin fork of libiconv.
    # Hence, overriding its source does not make sense on darwin.
    libiconv = libiconv.overrideAttrs {
      src = deps.libiconv;
    };
    lua = luajit;
    tree-sitter = tree-sitter.override {
      rustPlatform =
        rustPlatform
        // {
          buildRustPackage = args:
            rustPlatform.buildRustPackage (args
              // {
                src = deps.treesitter;
                cargoHash = "sha256-QvxH5uukaCmpHkWMle1klR5/rA2/HgNehmYIaESNpxc=";
              });
        };
    };
    treesitter-parsers = let
      grammars = lib.filterAttrs (name: _: lib.hasPrefix "treesitter_" name) deps;
    in
      lib.mapAttrs'
      (
        name: value:
          lib.nameValuePair
          (lib.removePrefix "treesitter_" name)
          {src = value;}
      )
      grammars;
  };

  neovim-nightly = (neovim-unwrapped.override overrides).overrideAttrs (old: {
    src = npins.neovim;
    version = npins.neovim.revision;
    patches = [];
    buildInputs = (old.buildInputs or []) ++ [(utf8proc.overrideAttrs (_: {src = deps.utf8proc;}))];
    preConfigure = ''
      ${old.preConfigure}
      sed -i cmake.config/versiondef.h.in -e "s/@NVIM_VERSION_PRERELEASE@/-dev-$version/"
    '';
  });

  config = neovimUtils.makeNeovimConfig {
    plugins = builtins.attrValues ({
        inherit (vimPlugins) onedark-nvim lualine-nvim;
        inherit (vimPlugins) lualine-lsp-progress neogit oil-nvim nvim-web-devicons;
      }
      // self'.legacyPackages.vimPlugins);
  };
in
  (wrapNeovimUnstable neovim-nightly config).overrideAttrs (old: {
    generatedWrapperArgs =
      old.generatedWrapperArgs
      or []
      ++ [
        "--set"
        "NOBBZ_NVIM_PATH"
        "${placeholder "out"}/bin/nvim"
        "--prefix"
        "PATH"
        ":"
        (lib.makeBinPath (
          builtins.attrValues {
            #
            # Runtime dependencies
            #
            inherit lua-language-server stylua markdown-oxide xclip;
          }
        ))
      ];
  })
