{ python3 }:

python3.pkgs.buildPythonApplication {
  pname = "gnome-themer";
  version = "0.1.0";
  src = ../.;
  pyproject = true;
  build-system = [ python3.pkgs.setuptools ];
}
