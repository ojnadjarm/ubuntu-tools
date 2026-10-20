/* LD_PRELOAD helper: ask the loaded RenderDoc to capture after RD_DELAY s (RD_FRAMES frames), or frame RD_FRAME (0-based, >= 1) by counting vkQueuePresentKHR. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "renderdoc_app.h"

typedef void (*vkfn)(void);
typedef vkfn (*getproc)(void *, const char *);
typedef int32_t (*present_fn)(void *, const void *);
typedef void *(*dlsym_fn)(void *, const char *);

static RENDERDOC_API_1_6_0 *rd_api(void) {
	void *lib = dlopen("librenderdoc.so", RTLD_NOW | RTLD_NOLOAD);
	pRENDERDOC_GetAPI get = lib ? (pRENDERDOC_GetAPI)dlsym(lib, "RENDERDOC_GetAPI") : NULL;
	RENDERDOC_API_1_6_0 *api = NULL;
	if (!get || !get(eRENDERDOC_API_Version_1_6_0, (void **)&api)) fprintf(stderr, "RDCAP no renderdoc loaded\n");
	return api;
}

static long target = -1, presents;
static getproc real_gipa, real_gdpa;
static present_fn real_present;

static int32_t my_present(void *queue, const void *info) {
	int32_t r = real_present(queue, info);
	if (++presents == target) {
		RENDERDOC_API_1_6_0 *api = rd_api();
		if (api) {
			api->TriggerCapture();
			fprintf(stderr, "RDCAP triggered frame=%ld\n", target);
		}
	}
	return r;
}
static vkfn my_gdpa(void *dev, const char *name) {
	vkfn f = real_gdpa(dev, name);
	if (f && !strcmp(name, "vkQueuePresentKHR")) {
		real_present = (present_fn)f;
		return (vkfn)my_present;
	}
	return f;
}
static vkfn my_gipa(void *inst, const char *name) {
	vkfn f = real_gipa(inst, name);
	if (f && !strcmp(name, "vkGetDeviceProcAddr")) {
		real_gdpa = (getproc)f;
		return (vkfn)my_gdpa;
	}
	if (f && !strcmp(name, "vkQueuePresentKHR")) {
		real_present = (present_fn)f;
		return (vkfn)my_present;
	}
	return f;
}

static dlsym_fn real_dlsym_fn(void) {
	static dlsym_fn real;
	if (!real) real = (dlsym_fn)dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.34");
	if (!real) real = (dlsym_fn)dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.2.5");
	return real;
}

/* Tail call keeps the caller's return address, so dlsym(RTLD_NEXT, ...) still resolves relative to the caller. */
void *dlsym(void *handle, const char *name) {
	if (target >= 0 && !strcmp(name, "vkGetInstanceProcAddr")) {
		void *f = real_dlsym_fn()(handle, name);
		if (!f) return NULL;
		real_gipa = (getproc)f;
		return (void *)my_gipa;
	}
	__attribute__((musttail)) return real_dlsym_fn()(handle, name);
}

static void *run(void *arg) {
	(void)arg;
	const char *d = getenv("RD_DELAY"), *n = getenv("RD_FRAMES");
	usleep((useconds_t)((d ? atof(d) : 2.0) * 1e6));
	RENDERDOC_API_1_6_0 *api = rd_api();
	if (!api) return NULL;
	api->TriggerMultiFrameCapture((uint32_t)(n ? atoi(n) : 1));
	fprintf(stderr, "RDCAP triggered\n");
	return NULL;
}

__attribute__((constructor)) static void start(void) {
	const char *f = getenv("RD_FRAME");
	if (f) {
		target = atol(f);
		return;
	}
	pthread_t t;
	if (pthread_create(&t, NULL, run, NULL) == 0) pthread_detach(t);
}
