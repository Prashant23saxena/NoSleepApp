#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <CoreGraphics/CoreGraphics.h>

typedef int (*DisplayServicesGetBrightness_t)(CGDirectDisplayID, float *);
typedef int (*DisplayServicesSetBrightness_t)(CGDirectDisplayID, float);

int main(int argc, char *argv[]) {
    void *ds = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY);
    if (!ds) {
        fprintf(stderr, "Error: Failed to load DisplayServices framework\n");
        return 1;
    }
    DisplayServicesGetBrightness_t getBrightness = (DisplayServicesGetBrightness_t)dlsym(ds, "DisplayServicesGetBrightness");
    DisplayServicesSetBrightness_t setBrightness = (DisplayServicesSetBrightness_t)dlsym(ds, "DisplayServicesSetBrightness");

    if (!getBrightness || !setBrightness) {
        fprintf(stderr, "Error: Failed to find DisplayServices brightness functions\n");
        return 1;
    }

    CGDirectDisplayID display = CGMainDisplayID();
    float current = 0.0f;
    getBrightness(display, &current);

    if (argc < 2) {
        // Just print current brightness (0.0 to 1.0)
        printf("%.2f\n", current);
        return 0;
    }

    float target = (float)atof(argv[1]);
    if (target < 0.0f) target = 0.0f;
    if (target > 1.0f) target = 1.0f;

    int res = setBrightness(display, target);
    if (res == 0) {
        printf("%.2f\n", target);
        return 0;
    } else {
        fprintf(stderr, "Error: Failed to set brightness (error code: %d)\n", res);
        return 1;
    }
}
