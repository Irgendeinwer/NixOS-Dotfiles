{ pkgs, ... }: {
  config.programs.yazi = {
	enable = true;
	package = pkgs.yazi.override {
	_7zz = (pkgs._7zz.override { useUasm = true; });
	};
  };
}
