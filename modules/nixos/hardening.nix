{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.system.security.hardening;
in
{
  options.custom.system.security.hardening = {
    enable = lib.mkEnableOption "System security hardening (strict IOMMU, kernel pointer protection, stable MAC randomization)";

    lockdownEmergencyShell = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Disable emergency rescue shells in initrd (reboots on boot failure instead of opening a root shell). Only enable after LUKS/Lanzaboote rollout is validated.";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. Strict IOMMU Translation (Hardware DMA isolation for Intel VT-d & AMD-Vi)
    boot.kernelParams = [
      "intel_iommu=on"
      "amd_iommu=force_isolation"
      "iommu=force"
      "iommu.strict=1"
      "iommu.passthrough=0"
    ] ++ lib.optionals cfg.lockdownEmergencyShell [
      "rd.shell=0"
      "rd.emergency=reboot"
      "panic=10"
    ];

    # Explicitly lock down emergency shell only when requested (never force unauthenticated access)
    boot.initrd.systemd.emergencyAccess = lib.mkIf cfg.lockdownEmergencyShell (lib.mkForce false);

    # 2. Thunderbolt / USB4 DMA device authorization
    services.hardware.bolt.enable = true;

    # 3. Kernel hardening & pointer restriction
    # Note: We avoid 'security.protectKernelImage = true' because it injects 'nohibernate'
    # which breaks suspend-then-hibernate. We configure the sysctls directly instead.
    boot.kernel.sysctl = {
      # Hide kernel pointers from unprivileged users
      "kernel.kptr_restrict" = 2;

      # Restrict dmesg buffer access to root
      "kernel.dmesg_restrict" = 1;

      # Disable kexec (prevents live kernel replacement attacks)
      "kernel.kexec_load_disabled" = 1;

      # Restrict unprivileged eBPF & harden JIT
      "kernel.unprivileged_bpf_disabled" = 1;
      "net.core.bpf_jit_harden" = 2;

      # Restrict ptrace scope to parent processes
      "kernel.yama.ptrace_scope" = 1;
    };

    # 4. Per-SSID Stable MAC Address Randomization
    # 'stable' derives a unique pseudorandom MAC per network SSID, preventing cross-network
    # tracking without causing DHCP lease instability on the same network.
    networking.networkmanager.wifi.macAddress = "stable";
  };
}
