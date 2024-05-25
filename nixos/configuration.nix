# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }: let
  nur-no-pkgs = import (builtins.fetchGit  {
    url = "https://github.com/nix-community/NUR";
    rev = "0f3c510de06615a8cf9a2ad3b77758bb9d155753";
    ref = "master";
  }) {};
  hibernateEnvironment = {
    HIBERNATE_SECONDS = "3600";
    HIBERNATE_LOCK = "/var/run/autohibernate.lock";
  };
in {
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # hardware quirks for Framework 13-inch AMD
      <nixos-hardware/framework/13-inch/7040-amd>
    ];
  
  services.fwupd.enable = true;
  hardware.framework.amd-7040.preventWakeOnAC = true;
  # downgrade to install fingerprint reader firmware
  #services.fwupd.package = (import (builtins.fetchTarball {
  #  url = "https://github.com/NixOS/nixpkgs/archive/bb2009ca185d97813e75736c2b8d1d8bb81bde05.tar.gz";
  #  sha256 = "sha256:003qcrsq5g5lggfrpq31gcvj82lb065xvr7bpfa8ddsw8x4dnysk";
  #}) {
  #  inherit (pkgs) system;
  #}).fwupd;

  nixpkgs = {
    overlays = [
      # for eduroam not supporting openssl3
      nur-no-pkgs.repos.cherrypiejam.overlays.wpa-supplicant-sslv3-trust-me
    ]; 
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelModules = [
    "cros_ec"
  ];

  networking.hostName = "weidao";
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.
  #environment.etc."NetworkManager/system-connections" = {
  #  source = "/var/state/networkmanager-connections";
  #};

  # Set your time zone.
  time.timeZone = "America/New_York";

  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      ubuntu_font_family
      source-han-serif
      source-han-sans
      source-han-mono
      terminus_font
      dejavu_fonts
      (nerdfonts.override { fonts = [ "Hack" ]; })
    ];

    fontconfig = {
      defaultFonts = {
        serif = ["Ubuntu" "Source Han"];
        sansSerif = ["Ubuntu" "Source Han"];
        monospace = ["Ubuntu" "Source Han"];
      };
    };
  };
  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    # keyMap = "us";
    useXkbConfig = true; # use xkb.options in tty.
  };
  
  # Enable fcitx5 a input method framework; add Chinese input method RIME
  i18n.inputMethod = {
    enabled = "fcitx5";
    fcitx5.addons = with pkgs; [
        fcitx5-rime
    ];
  };
  # see 23.11 Release Notes
  services.xserver.desktopManager.runXdgAutostartIfNone = true;

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Configure keymap in X11
  # Framework 13.5 inch has the resolution 2256x1506
  services.xserver.dpi = 167;
  services.xserver.xkb.layout = "us";
  # we use swap on a per-device basis, see below
  #services.xserver.xkb.options = "ctrl:swapcaps";
  services.xserver.desktopManager.gnome.enable = true;
  services.xserver.windowManager.i3.enable = true;
  # swap ctrl and caps only for the builtin keyboard
  services.xserver.displayManager.sessionCommands = ''
    keyboardId=$(
      ${pkgs.xorg.xinput}/bin/xinput |
        sed -nE 's/.*?AT Translated Set 2.*?id=([0-9]+).*? keyboard.*/\1/p'
    )
    if [[ $keyboardId ]]; then
      ${pkgs.xorg.setxkbmap}/bin/setxkbmap -device $keyboardId -option ctrl:swapcaps
    fi
  '';    

  services.xserver.displayManager = {
    lightdm.enable = true;
    #lightdm.background = "/var/state/background";
    # pkgs.nixos-artwork.wallpapers.nineish-dark-gray.gnomeFilePath;
    lightdm.greeters.gtk.extraConfig = ''
      hide-user-image=true
      [monitor: eDP-1]
    '';
    defaultSession = "none+i3";
  };

  # for laptop
  services.logind = {
    powerKey = "ignore";
    lidSwitch = "ignore";
  };

  services.acpid = {
    enable = true;
    lidEventCommands = ''
      lid=$(cat /proc/acpi/button/lid/LID0/state | ${pkgs.gawk}/bin/awk '{print $NF}')
      if [ "$lid" = "closed" ]; then
         echo "$(systemctl is-system-running)" > /dev/null
         systemctl suspend
      fi
    '';
    powerEventCommands = ''
      systemctl suspend
    '';
  };

  # hibernate
  systemd.services."awake-after-suspend-for-a-time" = {
    description = "Sets up the suspend so that it'll wake for hibernation";
    wantedBy = [ "suspend.target" ];
    before = [ "systemd-suspend.service" ];
    environment = hibernateEnvironment;
    script = ''
      if [ $(cat /sys/class/power_supply/ACAD/online) -eq 0 ]; then
        curtime=$(date +%s)
        echo "$curtime $1" >> /tmp/autohibernate.log
        echo "$curtime" > $HIBERNATE_LOCK
        ${pkgs.utillinux}/bin/rtcwake -m no -s $HIBERNATE_SECONDS
      else
        echo "System is on AC power, skipping wake-up scheduling for hibernation." >> /tmp/autohibernate.log
      fi
    '';
    serviceConfig.Type = "simple";
  };

  systemd.services."hibernate-after-recovery" = {
    description = "Hibernates after a suspend recovery due to timeout";
    wantedBy = [ "suspend.target" ];
    after = [ "systemd-suspend.service" ];
    environment = hibernateEnvironment;
    script = ''
      curtime=$(date +%s)
      sustime=$(cat $HIBERNATE_LOCK)
      rm $HIBERNATE_LOCK
      if [ $(($curtime - $sustime)) -ge $HIBERNATE_SECONDS ] ; then
        systemctl hibernate
      else
      ${pkgs.utillinux}/bin/rtcwake -m no -s 1
      fi
    '';
    serviceConfig.Type = "simple";
  }; 

  services.udev.extraRules = ''
    ACTION=="add",SUBSYSTEM=="pci",DRIVER=="pcieport",ATTR{power/wakeup}="disabled"
  '';

  # https://github.com/solokeys/solo2-cli/blob/main/70-solo2.rules
  services.udev.packages = [
    pkgs.yubikey-personalization
    (pkgs.writeTextFile {
    name = "wally_udev";
    text = ''
        # NXP LPC55 ROM bootloader (unmodified)
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1fc9", ATTRS{idProduct}=="0021", TAG+="uaccess"
        # NXP LPC55 ROM bootloader (with Solo 2 VID:PID)
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="b000", TAG+="uaccess"
        # Solo 2
        SUBSYSTEM=="tty", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="beee", TAG+="uaccess"
        # Solo 2
        SUBSYSTEM=="usb", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="beee", TAG+="uaccess"
    '';
    destination = "/etc/udev/rules.d/70-solo2.rules";
    })
  ];

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };
  
  services.xserver.xautolock = {
    enable = true;
    time = 10;
    locker = "${pkgs.i3lock}/bin/i3lock";
    nowlocker = "${pkgs.i3lock}/bin/i3lock";
    # deactivate when mouse is at bottom right
    extraOptions = [ "-corners 000-" ];
  };

  # Enable CUPS to print documents.
  services.printing = {
    enable = true;
    clientConf = ''
      ServerName ldrelay.cs.princeton.edu
      User yuetan
    '';
  };

  # Enable bluetooth
  services.blueman.enable = true;
  hardware.bluetooth.enable = true;  

  # Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  services.xserver.libinput = {
    enable = true;
    touchpad.naturalScrolling = true;
    touchpad.tapping = true;
    touchpad.disableWhileTyping = true;
    touchpad.accelProfile = "adaptive";
    touchpad.accelSpeed = "0.6";
  };

  # Enable fingerprint reader
  services.fprintd.enable = true;

  # Enable multi-display
  services.autorandr.enable = true;

  # Enable IMAP sync
  services.offlineimap.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.yue = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "audio" "tty" "tss" "docker" ]; # Enable ‘sudo’ for the user.
    hashedPassword = "";
    shell = pkgs.fish;
    packages = with pkgs; [
      firefox
      tree
      mutt
      mutt-ics
      zathura
      signal-desktop
   ];
  };
  
  programs.fish.enable = true;

  users.mutableUsers = false;
  users.users.root.hashedPassword = "";

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    tmux
    gitAndTools.gitFull
    acpi
    networkmanagerapplet
    file
    brightnessctl
    volctl
    arandr
    tailscale
    blueman
    parcellite
    powertop
    htop
    autojump
    power-profiles-daemon  
  ];

  environment.localBinInPath = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;
  
  # Enable Tailscale
  services.tailscale.enable = true;
  systemd.services.tailscale-autoconnect = {
    description = "Automatic connection to Tailscale";
  
    after = [ "network-pre.target" "tailscale.service" ];
    wants = [ "network-pre.target" "tailscale.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig.Type = "oneshot";

    # have the job run this shell script
    script = with pkgs; ''
      # wait for tailscaled to settle
      sleep 2
      
      # check if we are already authenticated to tailscale
      status="$(${tailscale}/bin/tailscale status -json | ${jq}/bin/jq -r .BackendState)"
      if [ $status = "Running" ]; then
        exit 0
      fi

      ${tailscale}/bin/tailscale up --authkey file:/etc/tailscale/tskey-reusable
       
    '';
  };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "23.11"; # Did you read the comment?

}

