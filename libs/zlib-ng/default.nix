{ stdenv
, lib
, fetchFromGitHub
, buildPackages
}:

stdenv.mkDerivation rec {
  pname = "zlib-ng";
  version = "2.0.0-RC1";

  src = fetchFromGitHub {
    owner = "zlib-ng";
    repo = "zlib-ng";
    rev = "v${version}";
    sha256 = "0wcx0640kkmkb2hppf7prz2k8bz35xqrkkmylln8ssbb11l3flai";
  };

  nativeBuildInputs = with buildPackages; [ cmake ];

  cmakeFlags = [
    "-DBUILD_SHARED_LIBS=OFF"
    "-DZLIB_COMPAT=ON"
    "-DZLIB_ENABLE_TESTS=OFF"
    "-DWITH_OPTIM=ON"
    "-DWITH_NATIVE_INSTRUCTIONS=OFF"
  ];

  patches = [./no-rc.patch ./no-icc.patch];

  outputs = ["out" "man"];

  dontDisableStatic = true;
  doCheck = false;
  enableParallelBuilding = true;

  meta = with lib; {
    homepage = "https://github.com/zlib-ng/zlib-ng";
    description = "zlib data compression library for the next generation systems";
    license = licenses.zlib;
    platforms = platforms.all;
  };
}
