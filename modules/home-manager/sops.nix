{
  config,
  inputs,
  ...
}:
let
  secretsDir = ../../secrets;
  userSecretsFile = secretsDir + "/users/${config.home.username}.yaml";
  commonSecretsFile = secretsDir + "/common.yaml";
in
{
  imports = [
    inputs.sops-nix.homeManagerModules.sops
  ];

  sops = {
    defaultSopsFormat = "yaml";

    age = {
      keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
      generateKey = false;
    };

    defaultSopsFile =
      if builtins.pathExists userSecretsFile then
        userSecretsFile
      else if builtins.pathExists commonSecretsFile then
        commonSecretsFile
      else
        null;

    secrets.user_ssh_key = {
      path = "${config.home.homeDirectory}/.ssh/id_ed25519";
      mode = "0600";
    };
  };

  home.sessionVariables = {
    SOPS_AGE_KEY_FILE = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
  };
}
