#import "TemperatureReader.h"

#include <Foundation/Foundation.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
#ifdef __LP64__
typedef double IOHIDFloat;
#else
typedef float IOHIDFloat;
#endif

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
IOHIDFloat IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);
CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);


#define IOHIDEventFieldBase(type) (type << 16)
#define kIOHIDEventTypeTemperature 15

@implementation TemperatureReading
- (instancetype)initWithName:(NSString *)name value:(double)value {
    self = [super init];
    if (self) {
        _name = [name copy];
        _value = value;
    }
    return self;
}
@end

@implementation TemperatureSnapshot
- (instancetype)initWithCPUReadings:(NSArray<TemperatureReading *> *)cpuReadings
                        gpuReadings:(NSArray<TemperatureReading *> *)gpuReadings
                        allReadings:(NSArray<TemperatureReading *> *)allReadings
                    thermalPressure:(NSString *)thermalPressure
                          timestamp:(NSDate *)timestamp {
    self = [super init];
    if (self) {
        _cpuReadings = cpuReadings;
        _gpuReadings = gpuReadings;
        _allReadings = allReadings;
        _thermalPressure = [thermalPressure copy];
        _timestamp = timestamp;
    }
    return self;
}
@end

static CFDictionaryRef Matching(int page, int usage) {
    CFStringRef keys[2];
    CFNumberRef nums[2];

    keys[0] = CFSTR("PrimaryUsagePage");
    keys[1] = CFSTR("PrimaryUsage");
    nums[0] = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &page);
    nums[1] = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &usage);

    CFDictionaryRef dict = CFDictionaryCreate(kCFAllocatorDefault,
                                              (const void **)keys,
                                              (const void **)nums,
                                              2,
                                              &kCFTypeDictionaryKeyCallBacks,
                                              &kCFTypeDictionaryValueCallBacks);
    CFRelease(nums[0]);
    CFRelease(nums[1]);
    return dict;
}

static NSArray<NSString *> *GetThermalNames(void) {
    CFDictionaryRef sensors = Matching(0xff00, 5);
    IOHIDEventSystemClientRef system = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    IOHIDEventSystemClientSetMatching(system, sensors);
    CFArrayRef services = IOHIDEventSystemClientCopyServices(system);

    NSMutableArray<NSString *> *names = [NSMutableArray array];
    CFIndex count = CFArrayGetCount(services);
    for (CFIndex i = 0; i < count; i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        CFStringRef name = (CFStringRef)IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        [names addObject:name ? (__bridge_transfer NSString *)name : @"noname"];
    }

    CFRelease(services);
    CFRelease(system);
    CFRelease(sensors);
    return names;
}

static NSArray<NSNumber *> *GetThermalValues(void) {
    CFDictionaryRef sensors = Matching(0xff00, 5);
    IOHIDEventSystemClientRef system = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    IOHIDEventSystemClientSetMatching(system, sensors);
    CFArrayRef services = IOHIDEventSystemClientCopyServices(system);

    NSMutableArray<NSNumber *> *values = [NSMutableArray array];
    CFIndex count = CFArrayGetCount(services);
    for (CFIndex i = 0; i < count; i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0);
        double value = 0;
        if (event != NULL) {
            value = IOHIDEventGetFloatValue(event, IOHIDEventFieldBase(kIOHIDEventTypeTemperature));
            CFRelease(event);
        }
        [values addObject:@(value)];
    }

    CFRelease(services);
    CFRelease(system);
    CFRelease(sensors);
    return values;
}

static BOOL IsValidTemperature(double value) {
    return value >= 0.0 && value < 110.0;
}

static BOOL IsLikelyCPUName(NSString *name) {
    return [name hasPrefix:@"PMU tdie"] ||
           [name hasPrefix:@"PMU tdev"] ||
           [name hasPrefix:@"pACC MTR Temp"] ||
           [name hasPrefix:@"eACC MTR Temp"] ||
           [name rangeOfString:@"CPU"].location != NSNotFound;
}

static BOOL IsExplicitLikelyGPUName(NSString *name) {
    return [name hasPrefix:@"GPU MTR Temp Sensor"] ||
           [name rangeOfString:@"GPU"].location != NSNotFound;
}

static BOOL IsFallbackLikelyGPUName(NSString *name) {
    return [name hasPrefix:@"PMU2 tdie"] || [name hasPrefix:@"PMU2 tdev"];
}

static NSString *ThermalPressureString(void) {
    switch ([NSProcessInfo processInfo].thermalState) {
        case NSProcessInfoThermalStateNominal:
            return @"Nominal";
        case NSProcessInfoThermalStateFair:
            return @"Fair";
        case NSProcessInfoThermalStateSerious:
            return @"Serious";
        case NSProcessInfoThermalStateCritical:
            return @"Critical";
    }
}

@implementation TemperatureReader

- (TemperatureSnapshot *)readSnapshot {
    NSArray<NSString *> *names = GetThermalNames();
    NSArray<NSNumber *> *values = GetThermalValues();
    NSMutableArray<TemperatureReading *> *allReadings = [NSMutableArray array];
    NSMutableArray<TemperatureReading *> *cpuReadings = [NSMutableArray array];
    NSMutableArray<TemperatureReading *> *explicitGPUReadings = [NSMutableArray array];
    NSMutableArray<TemperatureReading *> *fallbackGPUReadings = [NSMutableArray array];

    NSUInteger count = MIN(names.count, values.count);
    for (NSUInteger i = 0; i < count; i++) {
        NSString *name = names[i];
        double value = values[i].doubleValue;
        if (!IsValidTemperature(value)) {
            continue;
        }

        TemperatureReading *reading = [[TemperatureReading alloc] initWithName:name value:value];
        [allReadings addObject:reading];

        if (IsLikelyCPUName(name)) {
            [cpuReadings addObject:reading];
        }
        if (IsExplicitLikelyGPUName(name)) {
            [explicitGPUReadings addObject:reading];
        } else if (IsFallbackLikelyGPUName(name)) {
            [fallbackGPUReadings addObject:reading];
        }
    }

    NSArray<TemperatureReading *> *gpuReadings = explicitGPUReadings.count > 0 ? explicitGPUReadings : fallbackGPUReadings;
    return [[TemperatureSnapshot alloc] initWithCPUReadings:cpuReadings
                                                gpuReadings:gpuReadings
                                                allReadings:allReadings
                                            thermalPressure:ThermalPressureString()
                                                  timestamp:[NSDate date]];
}

@end
