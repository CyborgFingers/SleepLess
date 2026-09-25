// sleepless-led off|on — the MagSafe charging light during SleepLess's lid-closed mode. Runs as root, only
// from the helper, and only ever writes the SMC key ACLC (0 = macOS decides, 1 = off, 3 = green, 4 = orange).
//   off  turn the light off.
//   on   show the colour macOS would show right now (orange while charging, green on the charger otherwise),
//        then hand the light back to macOS. Writing 0 on its own leaves the last colour latched until the
//        next charge-state change, so the colour has to be put right first.
#include <IOKit/IOKitLib.h>
#include <IOKit/ps/IOPSKeys.h>
#include <IOKit/ps/IOPowerSources.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

enum { KERNEL_INDEX_SMC = 2, CMD_WRITE = 6, CMD_KEYINFO = 9, OFF = 1, GREEN = 3, ORANGE = 4, MACOS = 0 };
typedef struct { char major, minor, build, reserved[1]; UInt16 release; } Vers;
typedef struct { UInt16 version, length; UInt32 cpu, gpu, mem; } PLimit;
typedef struct { UInt32 dataSize, dataType; char dataAttributes; } KeyInfo;
typedef struct { UInt32 key; Vers vers; PLimit pLimit; KeyInfo keyInfo; char result, status, data8; UInt32 data32; unsigned char bytes[32]; } SMCData;

static io_connect_t conn;
static const UInt32 ACLC = ('A' << 24) | ('C' << 16) | ('L' << 8) | 'C';

static int call(SMCData *in, SMCData *out) {
    size_t size = sizeof(SMCData);
    return IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, in, sizeof(SMCData), out, &size) == kIOReturnSuccess && out->result == 0 ? 0 : -1;
}

static int writeLED(unsigned char value) {
    SMCData in = {0}, out = {0};
    in.key = ACLC; in.data8 = CMD_KEYINFO;
    if (call(&in, &out) || out.keyInfo.dataSize != 1) return -1;   // no MagSafe light on this Mac
    SMCData w = {0}, r = {0};
    w.key = ACLC; w.keyInfo.dataSize = 1; w.data8 = CMD_WRITE; w.bytes[0] = value;
    return call(&w, &r);
}

// Orange while charging, green on the charger otherwise, nothing to show on battery (no cable, no light).
static int currentColour(void) {
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    if (!info) return MACOS;
    int colour = MACOS;
    CFStringRef source = IOPSGetProvidingPowerSourceType(info);
    if (source && CFStringCompare(source, CFSTR(kIOPSACPowerValue), 0) == kCFCompareEqualTo) {
        colour = GREEN;
        CFArrayRef list = IOPSCopyPowerSourcesList(info);
        for (CFIndex i = 0; list && i < CFArrayGetCount(list); i++) {
            CFDictionaryRef d = IOPSGetPowerSourceDescription(info, CFArrayGetValueAtIndex(list, i));
            CFBooleanRef charging = d ? CFDictionaryGetValue(d, CFSTR(kIOPSIsChargingKey)) : NULL;
            if (charging == kCFBooleanTrue) colour = ORANGE;
        }
        if (list) CFRelease(list);
    }
    CFRelease(info);
    return colour;
}

int main(int argc, char **argv) {
    if (argc != 2 || (strcmp(argv[1], "off") && strcmp(argv[1], "on"))) { fprintf(stderr, "usage: sleepless-led off|on\n"); return 64; }
    io_service_t smc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!smc || IOServiceOpen(smc, mach_task_self(), 0, &conn) != kIOReturnSuccess) { fprintf(stderr, "sleepless-led: no AppleSMC\n"); return 1; }
    if (!strcmp(argv[1], "off")) return writeLED(OFF) ? 1 : 0;
    int colour = currentColour();
    if (colour != MACOS) { writeLED((unsigned char)colour); usleep(300000); }
    return writeLED(MACOS) ? 1 : 0;
}
