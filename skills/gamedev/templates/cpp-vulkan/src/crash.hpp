#pragma once

/** Install a SIGSEGV/SIGABRT/SIGFPE handler that prints raw stack PCs as one CRASH line on stderr and exits 128 + signal. */
void install_crash_handler();
