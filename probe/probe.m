// Expected-behavior control: one swipe as an edge-marked touch.
//
// Runs inside the simulator (`xcrun simctl spawn`). It dispatches a hand digitizer event with
// one finger child through IOHIDEventSystemClient, with the sender ID of the simulator
// touchscreen service. With the edge mask, UIKit sets `UITouch._edgeType` and
// UIScreenEdgePanGestureRecognizer begins. Without it, the same touch is a plain touch.
//
// usage: probe <fromX> <toX> <edge 0|1>   (x is normalized 0..1 of the portrait screen)

#import <Foundation/Foundation.h>
#include <mach/mach_time.h>
#include <stdlib.h>

typedef CFTypeRef IOHIDEventRef;
extern IOHIDEventRef IOHIDEventCreateDigitizerEvent(CFAllocatorRef, uint64_t, uint32_t transducer,
  uint32_t index, uint32_t identity, uint32_t eventMask, uint32_t buttonMask, double x, double y,
  double z, double tipPressure, double barrelPressure, Boolean range, Boolean touch, uint32_t options);
extern IOHIDEventRef IOHIDEventCreateDigitizerFingerEvent(CFAllocatorRef, uint64_t, uint32_t index,
  uint32_t identity, uint32_t eventMask, double x, double y, double z, double tipPressure,
  double twist, Boolean range, Boolean touch, uint32_t options);
extern void IOHIDEventAppendEvent(IOHIDEventRef parent, IOHIDEventRef child, uint32_t options);
extern void IOHIDEventSetIntegerValue(IOHIDEventRef, uint32_t field, long value);
extern void IOHIDEventSetFloatValue(IOHIDEventRef, uint32_t field, double value);
extern void IOHIDEventSetSenderID(IOHIDEventRef, uint64_t);
extern CFTypeRef IOHIDEventSystemClientCreate(CFAllocatorRef);
extern CFArrayRef IOHIDEventSystemClientCopyServices(CFTypeRef);
extern CFTypeRef IOHIDServiceClientCopyProperty(CFTypeRef, CFStringRef);
extern CFTypeRef IOHIDServiceClientGetRegistryID(CFTypeRef);
extern void IOHIDEventSystemClientDispatchEvent(CFTypeRef, IOHIDEventRef);

enum {
  MaskRange = 1 << 0,
  MaskTouch = 1 << 1,
  MaskPosition = 1 << 2,
  MaskIdentity = 1 << 5,
  MaskFromEdgeFlat = 1 << 10,
  MaskFromEdgeTip = 1 << 11,
};
#define DIGITIZER_FIELD(n) ((11u << 16) | (n))
#define FIELD_IS_DISPLAY_INTEGRATED DIGITIZER_FIELD(25)
#define FIELD_MAJOR_RADIUS DIGITIZER_FIELD(20)
#define FIELD_MINOR_RADIUS DIGITIZER_FIELD(21)
#define TRANSDUCER_HAND 3

static long intProperty(CFTypeRef service, CFStringRef key) {
  CFTypeRef value = IOHIDServiceClientCopyProperty(service, key);
  long result = -1;
  if (value && CFGetTypeID(value) == CFNumberGetTypeID()) {
    CFNumberGetValue(value, kCFNumberLongType, &result);
  }
  if (value) CFRelease(value);
  return result;
}

// The simulator touchscreen: digitizer usage page 13, touch screen usage 4.
static uint64_t touchscreenSenderID(CFTypeRef client) {
  CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
  uint64_t sender = 0;
  for (CFIndex i = 0; services && i < CFArrayGetCount(services); i++) {
    CFTypeRef service = CFArrayGetValueAtIndex(services, i);
    if (intProperty(service, CFSTR("PrimaryUsagePage")) == 13 &&
        intProperty(service, CFSTR("PrimaryUsage")) == 4) {
      CFNumberGetValue(IOHIDServiceClientGetRegistryID(service), kCFNumberSInt64Type, &sender);
      break;
    }
  }
  if (services) CFRelease(services);
  return sender;
}

static void dispatchTouch(CFTypeRef client, uint64_t sender, double x, double y, uint32_t mask,
                          Boolean touching) {
  uint64_t now = mach_absolute_time();
  IOHIDEventRef hand = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, now, TRANSDUCER_HAND,
    0, 0, mask, 0, x, y, 0, 0, 0, touching, touching, 0);
  IOHIDEventSetIntegerValue(hand, FIELD_IS_DISPLAY_INTEGRATED, 1);
  IOHIDEventRef finger = IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, now, 1, 2,
    mask, x, y, 0, touching ? 0.5 : 0, 0, touching, touching, 0);
  IOHIDEventSetFloatValue(finger, FIELD_MAJOR_RADIUS, 0.04);
  IOHIDEventSetFloatValue(finger, FIELD_MINOR_RADIUS, 0.04);
  IOHIDEventAppendEvent(hand, finger, 0);
  IOHIDEventSetSenderID(hand, sender);
  IOHIDEventSystemClientDispatchEvent(client, hand);
  CFRelease(finger);
  CFRelease(hand);
}

int main(int argc, char **argv) {
  @autoreleasepool {
    if (argc != 4) {
      fprintf(stderr, "usage: probe <fromX> <toX> <edge 0|1>\n");
      return 2;
    }
    double fromX = atof(argv[1]);
    double toX = atof(argv[2]);
    uint32_t edge = atoi(argv[3]) ? (MaskFromEdgeFlat | MaskFromEdgeTip) : 0;
    double y = 0.5;
    CFTypeRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    uint64_t sender = client ? touchscreenSenderID(client) : 0;
    if (!sender) {
      fprintf(stderr, "no simulator touchscreen HID service\n");
      return 1;
    }
    const int frames = 20;
    dispatchTouch(client, sender, fromX, y, MaskRange | MaskTouch | MaskIdentity | edge, true);
    for (int i = 1; i <= frames; i++) {
      usleep(16000);
      double x = fromX + (toX - fromX) * i / frames;
      dispatchTouch(client, sender, x, y, MaskPosition | edge, true);
    }
    usleep(16000);
    dispatchTouch(client, sender, toX, y, MaskRange | MaskTouch | MaskIdentity, false);
    usleep(100000);
    CFRelease(client);
  }
  return 0;
}
