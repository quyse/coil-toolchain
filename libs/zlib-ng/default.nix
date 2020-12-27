{ stdenv
, fetchFromGitHub
, buildPackages
}:

stdenv.mkDerivation rec {
  pname = "zlib-ng";
  version = "1.9.9-b1";

  src = fetchFromGitHub {
    owner = "zlib-ng";
    repo = "zlib-ng";
    rev = version;
    sha256 = "1yh3nmdlvm838lnqric7nzbgzj5dhja6pz7wx9ghp811x39vk81v";
  };

  nativeBuildInputs = with buildPackages; [ cmake ];

  cmakeFlags = [
    "-DBUILD_SHARED_LIBS=OFF"
    "-DZLIB_COMPAT=ON"
    "-DZLIB_ENABLE_TESTS=OFF"
    "-DWITH_OPTIM=ON"
    "-DWITH_NATIVE_INSTRUCTIONS=OFF"
  ];

  patches = [./no-rc.patch];

  outputs = ["out" "man"];

  dontDisableStatic = true;
  doCheck = false;
  enableParallelBuilding = true;

  meta = with stdenv.lib; {
    homepage = "https://github.com/zlib-ng/zlib-ng";
    description = "zlib data compression library for the next generation systems";
    license = licenses.zlib;
    platforms = platforms.all;
  };
}
