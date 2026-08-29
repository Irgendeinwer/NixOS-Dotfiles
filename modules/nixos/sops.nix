{
  config,
  pkgs,
  ...
}:
let
  secretsDir = ../../secrets;
  hostSecretsFile = secretsDir + "/${config.networking.hostName}.yaml";
  commonSecretsFile = secretsDir + "/common.yaml";
in
{
  sops = {
    defaultSopsFormat = "yaml";

    # Use host SSH key as age identity
    age = {
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };

    # Choose host-specific secret file if it exists, otherwise common
    defaultSopsFile =
      if builtins.pathExists hostSecretsFile then
        hostSecretsFile
      else if builtins.pathExists commonSecretsFile then
        commonSecretsFile
      else
        null;
  };

  # Make sops CLI available on the system
  environment.systemPackages = with pkgs; [
    sops
    age
    ssh-to-age
  ];
}
