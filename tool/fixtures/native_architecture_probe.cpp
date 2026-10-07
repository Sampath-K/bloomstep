#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <cstdio>
#include <cstring>

int main(int argc, char* argv[]) {
  USHORT processMachine = 0;
  USHORT nativeMachine = 0;
  if (!IsWow64Process2(GetCurrentProcess(), &processMachine, &nativeMachine)) {
    std::fprintf(stderr, "Native architecture query failed; no routing fallback.\n");
    return 1;
  }
  const char* architecture = nativeMachine == IMAGE_FILE_MACHINE_ARM64 ? "arm64" :
    nativeMachine == IMAGE_FILE_MACHINE_AMD64 ? "x64" : "unsupported";
  std::printf("{\"nativeArchitecture\":\"%s\",\"nativeMachine\":%u,\"processMachine\":%u,\"process64Bit\":%s}\n",
    architecture, static_cast<unsigned>(nativeMachine), static_cast<unsigned>(processMachine),
    sizeof(void*) == 8 ? "true" : "false");
  return argc == 2 && std::strcmp(architecture, argv[1]) == 0 ? 0 : 1;
}
