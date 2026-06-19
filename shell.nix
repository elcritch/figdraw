with import <nixpkgs> { };

mkShell {
  nativeBuildInputs = [
    pkg-config
    wayland
    vulkan-loader

    libX11
    libxcb
    libxcursor
    libxkbcommon
    libxrender
    libGL

    harfbuzz
  ];

  LD_LIBRARY_PATH = lib.makeLibraryPath [
    wayland.dev
    vulkan-loader.dev
    libX11.dev
    libxcb.dev
    libxcursor.dev
    libxrender.dev
    libxkbcommon.dev
    libGL.dev
    harfbuzz.dev
  ];
}
