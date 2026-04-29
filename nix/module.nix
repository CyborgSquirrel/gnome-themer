{ config, lib, pkgs, ... }:

let
  cfg = config.services.gnome-themer;
  pkg = pkgs.callPackage ./package.nix { };
in
{
  options.services.gnome-themer = {
    enable = lib.mkEnableOption "GNOME color-scheme symlink manager";

    links = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          target = lib.mkOption {
            type = lib.types.str;
            description = "Path of the symlink to manage.";
          };
          dark = lib.mkOption {
            type = lib.types.str;
            description = "Source file to link to in dark mode.";
          };
          light = lib.mkOption {
            type = lib.types.str;
            description = "Source file to link to in light mode.";
          };
          post_apply = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Shell command to run after this symlink is applied.";
          };
        };
      });
      default = [ ];
      description = "Symlink targets and their per-theme sources.";
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.configFile."gnome-themer/config.toml".source =
      (pkgs.formats.toml { }).generate "gnome-themer-config.toml" {
        link = map (l: lib.filterAttrs (_: v: v != null) l) cfg.links;
      };

    systemd.user.services.gnome-themer = {
      Unit = {
        Description = "GNOME color-scheme symlink manager";
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkg}/bin/gnome-themer";
        Restart = "on-failure";
        RestartSec = "3s";
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
