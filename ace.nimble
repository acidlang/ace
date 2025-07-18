# Package

version       = "0.0.1"
author        = "Navid M"
description   = "Package manager for Acid"
license       = "GPL-3.0-or-later"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["ace"]

task make, "Build the project in release mode":
  exec "nimble build -d:release --opt:size --stackTrace:off -d:strip --mm:arc"


# Dependencies

requires "nim >= 2.2.2"
requires "checksums >= 0.2.1"
