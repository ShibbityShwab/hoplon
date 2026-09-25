# =============================================================================
# Hoplon package.
#
# Copies the repository payload (scripts, config, themes, agents, skills, tui,
# AGENTS.md, VERSION) into the Nix store, adds the pinned opencode binary, and
# installs a `hoplon` wrapper. The wrapper seeds a writable runtime home under
# the user's XDG data dir because the store itself is read-only.
#
# The opencode binary is a fixed-output derivation pinned by sha256; it was
# computed by downloading the v1.18.25 linux x64 asset:
#
#   58a3729a6f3432dd6d2917fcc4a949788891a035818646ad480e12c947f56e78
# =============================================================================
{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
}:
let
  opencode = fetchurl {
    url = "https://github.com/anomalyco/opencode/releases/download/v1.18.25/opencode-linux-x64.tar.gz";
    hash = "sha256-WKNymm80Mt1tKRf8xKlJeIiRoDWBhkatSA4SyUf1bng=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "hoplon";
  version = lib.removeSuffix "\n" (builtins.readFile ../VERSION);

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    share="$out/share/hoplon"
    mkdir -p "$share/bin" "$out/bin"

    # The launcher resolves HOPLON_HOME from its own location, so the payload
    # and the launcher must sit together under $share.
    cp -r ${../scripts} "$share/scripts"
    cp -r ${../config} "$share/config"
    cp -r ${../themes} "$share/themes"
    cp -r ${../agents} "$share/agents"
    cp -r ${../skills} "$share/skills"
    cp -r ${../tui} "$share/tui"
    install -m 0644 ${../AGENTS.md} "$share/AGENTS.md"
    install -m 0644 ${../VERSION} "$share/VERSION"
    install -m 0755 ${../hoplon} "$share/hoplon"

    # Offline opencode: the pinned tarball contains a single `opencode` binary.
    tar -xzf ${opencode} -C "$share/bin"
    chmod 0755 "$share/bin/opencode"

    # Wrapper on PATH. It cannot be the launcher itself: the launcher would
    # resolve HOPLON_HOME to the read-only store. See nix/hoplon-wrapper.sh.
    install -m 0755 ${./hoplon-wrapper.sh} "$out/bin/hoplon"
    wrapProgram "$out/bin/hoplon" --set HOPLON_STORE_DIR "$share"

    runHook postInstall
  '';

  meta = {
    description = "Hoplon red-team operator distribution with a bundled opencode";
    homepage = "https://github.com/ShibbityShwab/hoplon";
    license = lib.licenses.mit;
    mainProgram = "hoplon";
    platforms = lib.platforms.linux;
  };
}
