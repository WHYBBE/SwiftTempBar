#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TemperatureReading : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) double value;
- (instancetype)initWithName:(NSString *)name value:(double)value;
@end

@interface TemperatureSnapshot : NSObject
@property (nonatomic, strong) NSArray<TemperatureReading *> *cpuReadings;
@property (nonatomic, strong) NSArray<TemperatureReading *> *gpuReadings;
@property (nonatomic, strong) NSArray<TemperatureReading *> *allReadings;
@property (nonatomic, copy) NSString *thermalPressure;
@property (nonatomic, strong) NSDate *timestamp;
- (instancetype)initWithCPUReadings:(NSArray<TemperatureReading *> *)cpuReadings
                        gpuReadings:(NSArray<TemperatureReading *> *)gpuReadings
                        allReadings:(NSArray<TemperatureReading *> *)allReadings
                    thermalPressure:(NSString *)thermalPressure
                          timestamp:(NSDate *)timestamp;
@end

@interface TemperatureReader : NSObject
- (TemperatureSnapshot *)readSnapshot;
@end

NS_ASSUME_NONNULL_END
