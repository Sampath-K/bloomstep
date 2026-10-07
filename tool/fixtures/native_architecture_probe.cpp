#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <cstdio>
#include <cstring>

#if !defined(_M_X64) || defined(_M_ARM64EC) || defined(_M_CEE)
#error This read-only probe requires native AMD64 machine code.
#endif

int main(int argc, char* argv[]) {
  USHORT wow64ProcessMachine = 0;
  USHORT nativeMachine = 0;
  if (!IsWow64Process2(GetCurrentProcess(), &wow64ProcessMachine, &nativeMachine)) {
    std::fprintf(stderr, "Native architecture query failed; no routing fallback.\n");
    return 1;
  }
  PROCESS_MACHINE_INFORMATION information = {};
  if (!GetProcessInformation(GetCurrentProcess(), ProcessMachineTypeInfo, &information, sizeof(information))) {
    std::fprintf(stderr, "Actual process-machine query failed; no emulation inference.\n");
    return 1;
  }
  const char* architecture = nativeMachine == IMAGE_FILE_MACHINE_ARM64 ? "arm64" :
    nativeMachine == IMAGE_FILE_MACHINE_AMD64 ? "x64" : "unsupported";
  std::printf("{\"nativeArchitecture\":\"%s\",\"nativeMachine\":%u,\"processMachine\":%u,\"wow64ProcessMachine\":%u,\"process64Bit\":%s}\n",
    architecture, static_cast<unsigned>(nativeMachine), static_cast<unsigned>(information.ProcessMachine),
    static_cast<unsigned>(wow64ProcessMachine),
    sizeof(void*) == 8 ? "true" : "false");
  return argc == 2 && std::strcmp(architecture, argv[1]) == 0 ? 0 : 1;
}
