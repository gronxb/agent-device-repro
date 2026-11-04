// Lists every touchscreen HID service on the simulator (digitizer usage page 13, touch screen
// usage 4) with the properties the agent-device runner selects on. Run with `xcrun simctl spawn`.

#import <Foundation/Foundation.h>

extern CFTypeRef IOHIDEventSystemClientCreate(CFAllocatorRef);
extern CFArrayRef IOHIDEventSystemClientCopyServices(CFTypeRef);
extern CFTypeRef IOHIDServiceClientCopyProperty(CFTypeRef, CFStringRef);
extern CFTypeRef IOHIDServiceClientGetRegistryID(CFTypeRef);

static NSString *describe(CFTypeRef service, NSString *key) {
  CFTypeRef value = IOHIDServiceClientCopyProperty(service, (__bridge CFStringRef)key);
  if (value == NULL) return @"<missing>";
  CFTypeID type = CFGetTypeID(value);
  NSString *description = (type == CFStringGetTypeID() || type == CFNumberGetTypeID() || type == CFBooleanGetTypeID())
    ? [(__bridge id)value description]
    : @"<other type>";
  CFRelease(value);
  return description;
}

int main(void) {
  @autoreleasepool {
    CFTypeRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    NSArray *services = CFBridgingRelease(IOHIDEventSystemClientCopyServices(client));
    NSUInteger count = 0;
    for (id entry in services) {
      CFTypeRef service = (__bridge CFTypeRef)entry;
      if (![describe(service, @"PrimaryUsagePage") isEqualToString:@"13"] ||
          ![describe(service, @"PrimaryUsage") isEqualToString:@"4"]) {
        continue;
      }
      count += 1;
      printf("  registryID=%s Transport=%s Product=%s Built-In=%s displayUUID=%s\n",
        [[(__bridge id)IOHIDServiceClientGetRegistryID(service) description] UTF8String],
        describe(service, @"Transport").UTF8String, describe(service, @"Product").UTF8String,
        describe(service, @"Built-In").UTF8String, describe(service, @"displayUUID").UTF8String);
    }
    if (count == 0) printf("  (none)\n");
    if (client) CFRelease(client);
  }
  return 0;
}
