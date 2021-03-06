//
//  Created by Willy Blandin on 12. 8. 16.
//  Copyright (c) 2012년 Willy Blandin. All rights reserved.
//

#import "WitPrivate.h"
#import "WITState.h"
#import "WITRecorder.h"
#import "WITUploader.h"
#import "util.h"
//#import "WITRecordingSession.h"
#import "WITContextSetter.h"
#import "WITRecordingSessionDelegate.h"
#import "WITSFSpeechRecordingSession.h"
@import Speech;

@interface Wit () <WITRecordingSessionDelegate>
@property (nonatomic, strong) WITState *state;
@end

@implementation Wit {
    WITContextSetter* _wcs;
}

#pragma mark - Public API
- (void)toggleCaptureVoiceIntent {
    [self toggleCaptureVoiceIntent: nil];
}

- (void)toggleCaptureVoiceIntent:(id)customData {
    [self toggleCaptureVoiceIntent:customData disableVADViaOverride:nil];
}

- (void)toggleCaptureVoiceIntent:(id)customData disableVADViaOverride: (BOOL) disableVAD {
    if ([self isRecording]) {
        [self stop];
    } else {
        [self start: customData disableVADViaOverride:disableVAD];
    }
}

- (void)start {
    [self start: nil disableVADViaOverride:NO];
}

- (void)start:(id)customData {
    [self start:customData disableVADViaOverride:NO];
}

- (void)start: (id)customData disableVADViaOverride: (BOOL) disableVAD {
    if ([SFSpeechRecognizer class]) {
        self.recordingSession = [[WITSFSpeechRecordingSession alloc] initWithWitContext:self.state.context
                                                                                 locale: self.speechRecognitionLocale
                                                                             vadEnabled: disableVAD ? WITVadConfigDisabled : [Wit sharedInstance].detectSpeechStop withWitToken:[WITState sharedInstance].accessToken
                                                                             customData: customData withDelegate:self];
    } else {
        self.recordingSession = [[WITRecordingSession alloc] initWithWitContext:self.state.context
                                                                     vadEnabled: disableVAD ? WITVadConfigDisabled : [Wit sharedInstance].detectSpeechStop withWitToken:[WITState sharedInstance].accessToken
                                                                   withDelegate:self];
    }
    
    self.recordingSession.customData = customData;
    self.recordingSession.delegate = self;
}

- (void)stop{
    [self.recordingSession stop];
}

- (BOOL)isRecording {
    return [self.recordingSession isRecording];
}


- (void)interpretString:(NSString *) string customData:(id)customData  {
    [self interpretString:string customData:customData urlQueryItems:nil];
}
- (void)interpretString:(NSString *) string customData:(id)customData urlQueryItems: (NSArray *) urlQueryItems {
    NSDate *start = [NSDate date];
    NSString *urlString = [NSString stringWithFormat:@"%@/message?q=%@&v=%@&verbose=true", self.serverAddress, urlencodeString(string), kWitAPIVersion];
    NSURLComponents *urlComponents = [NSURLComponents componentsWithString:urlString];
    if (urlQueryItems) {
        NSMutableArray *tempArray = [NSMutableArray arrayWithArray:urlComponents.queryItems];
        urlComponents.queryItems = [tempArray arrayByAddingObjectsFromArray:urlQueryItems];
    }
    
    NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:urlComponents.URL];
    [req setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
    [req setTimeoutInterval:30.0];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", self.accessToken] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    
    NSURLSession *session = [NSURLSession sharedSession];
    
    [[session dataTaskWithRequest:req
                completionHandler:^(NSData *data,
                                    NSURLResponse *response,
                                    NSError *connectionError) {
                    
                    [self witResponseHandler:response start:start type:@"message" data:data
                                  customData:customData connectionError:connectionError];
                }] resume];
}



- (void)converseWithString:(NSString *)string witSession:(WitSession *)session {
    NSDictionary *context = session.context;
    NSDate *start = [NSDate date];
    
    NSString *urlString = [NSString stringWithFormat:@"%@/converse?session_id=%@&v=%@&verbose=true", self.serverAddress, session.sessionID, kWitAPIVersion];
    if (string) {
        urlString = [urlString stringByAppendingString:[NSString stringWithFormat:@"&q=%@", urlencodeString(string)]];
    }
    NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString: urlString]];
    [req setHTTPMethod:@"POST"];
    NSError *serializationError = nil;
    
    if (session.context) {
        [req setHTTPBody:[NSJSONSerialization dataWithJSONObject:context
                                                         options:0
                                                           error:&serializationError]];
    }
    
    if (serializationError) {
        NSLog(@"Wit could not serialize your context: %@", serializationError.localizedDescription);
    }
    
    
    [req setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
    [req setTimeoutInterval:30];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", self.accessToken] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    
    NSURLSession *urlSsession = [NSURLSession sharedSession];
    
    [[urlSsession dataTaskWithRequest:req
                    completionHandler:^(NSData *data,
                                        NSURLResponse *response,
                                        NSError *connectionError) {
                        
                        [self witResponseHandler:response start:start type:@"converse" data:data
                                      customData:session connectionError:connectionError];
                    }] resume];
}

-(void)witResponseHandler:(NSURLResponse *)response start:(NSDate *)start type:(NSString *)type data:(NSData *)data
               customData:(id)customData connectionError:(NSError *)connectionError {
    if (WIT_DEBUG) {
        NSTimeInterval t = [[NSDate date] timeIntervalSinceDate:start];
        NSLog(@"Wit response (%f s) %@",
              t, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    }
    
    if (connectionError) {
        [self gotResponse:nil responseData: nil customData:customData type:nil error:connectionError];
        return;
    }
    
    NSError *serializationError;
    NSDictionary *object = [NSJSONSerialization JSONObjectWithData:data
                                                           options:0
                                                             error:&serializationError];
    if (serializationError) {
        [self gotResponse:nil responseData: nil customData:customData type:nil error:serializationError];
        return;
    }
    
    if (object[@"error"]) {
        NSDictionary *infos = @{NSLocalizedDescriptionKey: object[@"error"],
                                kWitKeyError: object[@"code"]};
        [self gotResponse:nil responseData: nil customData:customData type:nil
                    error:[NSError errorWithDomain:@"WitProcessing"
                                              code:1
                                          userInfo:infos]];
        return;
    }
    
    [self gotResponse:object responseData:data customData:customData type:type error:nil];
}


#pragma mark - Context management
-(void)setContext:(NSDictionary *)dict {
    self.state.context = dict;
}

-(NSDictionary*)getContext {
    return self.state.context;
}

#pragma mark - WITUploaderDelegate
- (void)gotResponse:(NSDictionary*)resp responseData: (NSData *) data customData:(id)customData type:(NSString *)type error:(NSError*)err {
    if (err) {
        [self error:err customData:customData];
        return;
    }
    if([type isEqual:@"message"]){
        [self processMessage:resp responseData: data customData:customData];
        
        
    }
    
}

#pragma mark - Response processing
- (void)errorWithDescription:(NSString*)errorDesc customData:(id)customData {
    NSError *e = [NSError errorWithDomain:@"WitProcessing" code:1 userInfo:@{NSLocalizedDescriptionKey: errorDesc}];
    [self error:e customData:customData];
}

- (void)processMessage:(NSDictionary *)resp responseData: (NSData *) data customData:(id)customData {
    id error = resp[kWitKeyError];
    if (error) {
        NSString *errorDesc = [NSString stringWithFormat:@"Code %@: %@", error[@"code"], error[@"message"]];
        return [self errorWithDescription:errorDesc customData:customData];
    }
    
    NSArray* outcomes = resp[kWitKeyOutcome];
    if (!outcomes || [outcomes count] == 0) {
        return [self errorWithDescription:@"No outcome" customData:customData];
    }
    NSString *messageId = resp[kWitKeyMsgId];
    
    if ([self.delegate respondsToSelector:@selector(witDidGraspIntent:messageId:customData:error:fullResponse:fullData:)]) {
        [self.delegate witDidGraspIntent:outcomes messageId:messageId customData:customData error:error fullResponse: resp fullData:data];
    } else {
        [self.delegate witDidGraspIntent:outcomes messageId:messageId customData:customData error:error];
    }
    
}

- (void)processConverse:(NSDictionary *)response customData:(id)customData {
    NSLog(@"response %@", response);
    id error = response[kWitKeyError];
    if (error) {
        NSString *errorDesc = [NSString stringWithFormat:@"Code %@: %@", error[@"code"], error[@"message"]];
        return [self errorWithDescription:errorDesc customData:customData];
    }
    
    
    
    WitSession *session = customData;
    
    NSString *type = response[@"type"];
    
    if ([type isEqualToString:@"action"]) {
        session = [self.delegate didReceiveAction:response[@"action"] entities:response[@"entities"] witSession:session confidence:[response[@"confidence"] doubleValue]];
    } else if ([type isEqualToString:@"msg"])  {
        session = [self.delegate didReceiveMessage:response[@"msg"] quickReplies: response[@"quickreplies"] witSession:session confidence:[response[@"confidence"] doubleValue]];
    } else if ([type isEqualToString:@"stop"])  {
        [self.delegate didStopSession:customData];
        return;
        
    } else if ([type isEqualToString:@"merge"])  {
        session = [self.delegate didReceiveMergeEntities:response[@"entities"] witSession:session confidence:[response[@"confidence"] doubleValue]];
        
    }
    NSAssert(session != nil, @"You need to return the WitSession from your delegate call.");
    
    if (session.isCancelled == NO) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self converseWithString:nil witSession:session];
        });
    }
    
    
}

- (void)error:(NSError*)e customData:(id)customData; {
    if ([customData isKindOfClass:[WitSession class]]) {
        [self.delegate didReceiveConverseError:e witSession:customData];
    } else {
        if ([self.delegate respondsToSelector:@selector(witDidGraspIntent:messageId:customData:error:fullResponse:fullData:)]) {
            [self.delegate witDidGraspIntent:nil messageId:nil customData:customData error:e fullResponse:nil fullData:nil];
        }
    }
    
}

#pragma mark - Getters and setters
- (NSString *)accessToken {
    return self.state.accessToken;
}

- (void)setAccessToken:(NSString *)accessToken {
    self.state.accessToken = accessToken;
}

#pragma mark - Lifecycle
- (void)initialize {
    self.state = [WITState sharedInstance];
    self.detectSpeechStop = WITVadConfigDetectSpeechStop;
    self.vadTimeout = 7000;
    self.vadSensitivity = 0;
    self.speechRecognitionLocale = @"en-US";
    self.serverAddress = kWitAPIUrl;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self initialize];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (Wit *)sharedInstance {
    static Wit *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[Wit alloc] init];
    });
    
    return instance;
}

- (WITContextSetter *)wcs {
    if (!_wcs) {
        _wcs = [[WITContextSetter alloc] init];
    }
    return _wcs;
}

#pragma mark - WITRecordingSessionDelegate

- (void)recordingSessionActivityDetectorStarted {
    if ([self.delegate respondsToSelector:@selector(witActivityDetectorStarted)]) {
        [self.delegate witActivityDetectorStarted];
    }
}

- (void)recordingSessionWillStartRecording {
    if ([self.delegate respondsToSelector:@selector(witWillStartRecording)]) {
        [self.delegate witWillStartRecording];
    }
}

- (void)recordingSessionDidStartRecording {
    if ([self.delegate respondsToSelector:@selector(witDidStartRecording)]) {
        [self.delegate witDidStartRecording];
    }
}

- (void)recordingSessionDidStopRecording {
    if ([self.delegate respondsToSelector:@selector(witDidStopRecording)]) {
        [self.delegate witDidStopRecording];
    }
}

- (void)recordingSessionReceivedError:(NSError *)error {
    if ([self.delegate respondsToSelector:@selector(witReceivedRecordingError:)]) {
        [self.delegate witReceivedRecordingError: error];
    }
}


- (void)recordingSessionDidRecognizePreviewText:(NSString *)previewText final: (BOOL) isFinal {
    if ([self.delegate respondsToSelector:@selector(witDidRecognizePreviewText:final:)]) {
        [self.delegate witDidRecognizePreviewText: (NSString *) previewText final: isFinal];
    }
}
- (void)recordingSessionDidDetectSpeech {
    if ([self.delegate respondsToSelector:@selector(witDidDetectSpeech)]) {
        [self.delegate witDidDetectSpeech];
    }
}

- (void)recordingSessionRecorderGotChunk:(NSData *)chunk {
    if ([self.delegate respondsToSelector:@selector(witDidGetAudio:)]) {
        [self.delegate witDidGetAudio:chunk];
    }
}

- (void)recordingSessionRecorderPowerChanged:(float)power {
    
}

- (void)recordingSessionGotResponse:(NSDictionary *)resp customData:(id)customData error:(NSError *)err sender:(id) sender {
    [self gotResponse:resp responseData: nil customData:customData type:nil error:err];
    if (self.recordingSession == sender) {
        self.recordingSession = nil;
    }
}

@end

