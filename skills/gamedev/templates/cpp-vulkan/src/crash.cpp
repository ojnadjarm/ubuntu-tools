#include "crash.hpp"

#include <execinfo.h>
#include <link.h>
#include <unistd.h>

#include <csignal>
#include <cstdint>
#include <cstring>
#include <initializer_list>

namespace {

uintptr_t exe_base = 0;

void put(const char* s) {
    [[maybe_unused]] const ssize_t n = write(STDERR_FILENO, s, std::strlen(s));
}

void put_hex(uintptr_t v) {
    char buf[19];
    char* p = buf + sizeof buf;
    *--p = '\0';
    do {
        *--p = "0123456789abcdef"[v & 15];
        v >>= 4;
    } while (v);
    *--p = 'x';
    *--p = '0';
    put(p);
}

void on_crash(int sig) {  // NOLINT(bugprone-signal-handler)
    void* frames[64];
    const int n = backtrace(frames, 64);
    put("\nCRASH signal=SIG");
    put(sigabbrev_np(sig));
    put(" base=");
    put_hex(exe_base);
    put(" frames=");
    // Frames 0-1 are this handler and the kernel trampoline; frame 2 is the faulting PC, later ones return addresses.
    for (int i = 2; i < n; i++) {
        if (i > 2) put(",");
        put_hex(reinterpret_cast<uintptr_t>(frames[i]) - (i > 2 ? 1 : 0));
    }
    put("\n");
    _exit(128 + sig);
}

}  // namespace

void install_crash_handler() {
    dl_iterate_phdr([](dl_phdr_info* info, size_t, void*) {
        exe_base = info->dlpi_addr;
        return 1;
    }, nullptr);
    void* warm[1];
    backtrace(warm, 1);
    struct sigaction sa {};
    sa.sa_handler = on_crash;
    sa.sa_flags = SA_RESETHAND;
    for (int sig : {SIGSEGV, SIGABRT, SIGFPE}) sigaction(sig, &sa, nullptr);
}
