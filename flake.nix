# SPDX-FileCopyrightText: 2024 Nixpkgs contributors
# SPDX-License-Identifier: MIT
#
# This file is derived from nixpkgs pkgs/by-name/ki/kitty/package.nix
# Original source: https://github.com/NixOS/nixpkgs/tree/master/pkgs/by-name/ki/kitty
# Original maintainers: rvolosatovs, Luflosi, kashw2, leiserfg
#
# MIT License
#
# Copyright (c) Nixpkgs contributors
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

{
  nixConfig = {
    extra-substituters = [ "https://kitty-yysushi.cachix.org" ];
    extra-trusted-public-keys = [
      "kitty-yysushi.cachix.org-1:d8DngoRn+eC6hXjYLeIArFWQjBMVqIugMo1Y9SqyBsQ="
    ];
  };

  description = "Fast, feature-rich, GPU based terminal emulator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          inherit (pkgs)
            lib
            stdenv
            ;
          inherit (pkgs.darwin.apple_sdk.frameworks)
            Cocoa
            CoreGraphics
            Foundation
            IOKit
            Kernel
            OpenGL
            UniformTypeIdentifiers
            ;

          buildGo126Module = pkgs.buildGo126Module;
          python3 = pkgs.python3;
          python3Packages = pkgs.python3Packages;

          version = "0.46.0";

          goModules =
            (buildGo126Module {
              pname = "kitty-go-modules";
              inherit version;
              src = ./.;
              vendorHash = "sha256-DEaMBblHpfcrySuMqM6SGFPyEyVd8SiXYiftHQBnYdE=";
            }).goModules;

        in
        {
          default = python3Packages.buildPythonApplication {
            pname = "kitty";
            inherit version;
            pyproject = false;

            src = ./.;

            inherit goModules;

            buildInputs = [
              pkgs.harfbuzz
              pkgs.ncurses
              pkgs.simde
              pkgs.lcms2
              pkgs.librsync
              python3Packages.matplotlib
              pkgs.openssl.dev
              pkgs.xxHash
            ]
            ++ lib.optionals stdenv.hostPlatform.isDarwin [
              pkgs.libpng
              python3
              pkgs.zlib
            ]
            ++ lib.optionals stdenv.hostPlatform.isLinux [
              pkgs.fontconfig
              pkgs.libunistring
              pkgs.libcanberra
              pkgs.xorg.libX11
              pkgs.xorg.libXrandr
              pkgs.xorg.libXinerama
              pkgs.xorg.libXcursor
              pkgs.libxkbcommon
              pkgs.xorg.libXi
              pkgs.xorg.libXext
              pkgs.wayland-protocols
              pkgs.wayland
              pkgs.dbus
              pkgs.libGL
              pkgs.cairo
            ];

            nativeBuildInputs = [
              pkgs.installShellFiles
              pkgs.ncurses
              pkgs.pkg-config
              python3Packages.sphinx
              python3Packages.furo
              python3Packages.sphinx-copybutton
              python3Packages.sphinxext-opengraph
              python3Packages.sphinx-inline-tabs
              pkgs.go_1_26
              pkgs.fontconfig
              pkgs.makeBinaryWrapper
            ]
            ++ lib.optionals stdenv.hostPlatform.isDarwin [
              pkgs.imagemagick
              pkgs.libicns
              pkgs.darwin.autoSignDarwinBinariesHook
            ]
            ++ lib.optionals stdenv.hostPlatform.isLinux [
              pkgs.wayland-scanner
            ];

            depsBuildBuild = [ pkgs.pkg-config ];

            outputs = [
              "out"
              "terminfo"
              "shell_integration"
              "kitten"
            ];

            hardeningDisable = [
              "fortify3"
            ];

            env = {
              CGO_ENABLED = 0;
              GOFLAGS = "-trimpath";
            };

            configurePhase = ''
              export GOCACHE=$TMPDIR/go-cache
              export GOPATH="$TMPDIR/go"
              export GOPROXY=off
              cp -r --reflink=auto $goModules vendor
            '';

            buildPhase =
              let
                commonOptions = ''
                  --update-check-interval=0 \
                  --shell-integration=enabled\ no-rc
                '';
                darwinOptions = ''
                  --disable-link-time-optimization \
                  ${commonOptions}
                '';
              in
              ''
                runHook preBuild

                # Add the font by hand because fontconfig does not finds it in darwin
                mkdir ./fonts/
                cp "${pkgs.nerd-fonts.symbols-only}/share/fonts/truetype/NerdFonts/Symbols/SymbolsNerdFontMono-Regular.ttf" ./fonts/

                ${
                  if stdenv.hostPlatform.isDarwin then
                    ''
                      ${python3.pythonOnBuildForHost.interpreter} setup.py build ${darwinOptions}
                      ${python3.pythonOnBuildForHost.interpreter} setup.py kitty.app ${darwinOptions}
                    ''
                  else
                    ''
                      ${python3.pythonOnBuildForHost.interpreter} setup.py linux-package \
                      --egl-library='${lib.getLib pkgs.libGL}/lib/libEGL.so.1' \
                      --startup-notification-library='${pkgs.libstartup_notification}/lib/libstartup-notification-1.so' \
                      --canberra-library='${pkgs.libcanberra}/lib/libcanberra.so' \
                      --fontconfig-library='${pkgs.fontconfig.lib}/lib/libfontconfig.so' \
                      ${commonOptions}
                      ${python3.pythonOnBuildForHost.interpreter} setup.py build-launcher
                    ''
                }
                runHook postBuild
              '';

            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
              mkdir -p "$kitten/bin"
              ${
                if stdenv.hostPlatform.isDarwin then
                  ''
                    mkdir "$out/bin"
                    ln -s ../Applications/kitty.app/Contents/MacOS/kitty "$out/bin/kitty"
                    ln -s ../Applications/kitty.app/Contents/MacOS/kitten "$out/bin/kitten"
                    cp ./kitty.app/Contents/MacOS/kitten "$kitten/bin/kitten"
                    mkdir "$out/Applications"
                    cp -r kitty.app "$out/Applications/kitty.app"
                  ''
                else
                  ''
                    cp -r linux-package/{bin,share,lib} "$out"
                    cp linux-package/bin/kitten "$kitten/bin/kitten"
                  ''
              }

              # dereference the `kitty` symlink to make sure the actual executable
              # is wrapped on macOS as well (and not just the symlink)
              wrapProgram $(realpath "$out/bin/kitty") --suffix PATH : "$out/bin:${
                lib.makeBinPath [
                  pkgs.imagemagick
                  pkgs.ncurses.dev
                ]
              }"

              installShellCompletion --cmd kitty \
                --bash <("$out/bin/kitty" +complete setup bash) \
                --fish <("$out/bin/kitty" +complete setup fish2) \
                --zsh  <("$out/bin/kitty" +complete setup zsh)

              terminfo_src=${
                if stdenv.hostPlatform.isDarwin then
                  ''"$out/Applications/kitty.app/Contents/Resources/terminfo"''
                else
                  "$out/share/terminfo"
              }

              mkdir -p $terminfo/share
              mv "$terminfo_src" $terminfo/share/terminfo

              mkdir -p "$out/nix-support"
              echo "$terminfo" >> $out/nix-support/propagated-user-env-packages

              cp -r 'shell-integration' "$shell_integration"

              runHook postInstall
            '';

            meta = {
              homepage = "https://github.com/yysushi/kitty";
              description = "Fast, feature-rich, GPU based terminal emulator (fork)";
              license = lib.licenses.gpl3Only;
              changelog = [
                "https://sw.kovidgoyal.net/kitty/changelog/"
                "https://github.com/kovidgoyal/kitty/blob/v${version}/docs/changelog.rst"
              ];
              platforms = lib.platforms.darwin ++ lib.platforms.linux;
              mainProgram = "kitty";
              maintainers = [ ];
            };
          };
        }
      );
    };
}
