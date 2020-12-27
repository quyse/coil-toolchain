# Patches

## Fix intrin-impl.h

Patch: `intrin.patch`

To fix errors with clang like:

```
...-mingw-w64-6.0.0-x86_64-w64-mingw32-dev/include/psdk_inc/intrin-impl.h:1944:18: error: redefinition of '__builtin_ia32_xgetbv' as different kind of symbol
```

See https://sourceforge.net/p/mingw-w64/mailman/mingw-w64-public/thread/5ec40e71-99c2-bdf4-1736-acd238c47539%40126.com/
