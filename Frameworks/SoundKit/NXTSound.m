/* -*- mode: objc -*- */
//
// Project: NEXTSPACE - DesktopKit framework
//
// Copyright (C) 2014-2019 Sergii Stoian
//
// This application is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public
// License as published by the Free Software Foundation; either
// version 2 of the License, or (at your option) any later version.
//
// This application is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// Library General Public License for more details.
//
// You should have received a copy of the GNU General Public
// License along with this library; if not, write to the Free
// Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.
//

#import "NXTSound.h"
#import <GNUstepGUI/GSSoundSource.h>

@implementation NXTSound

- (void)dealloc
{
  NSLog(@"[NXTSound] dealloc");
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self setDelegate:nil];
  if (_stream) {
    [_stream release];
    _stream = nil;
  }
  
  [super dealloc];
}

- (void)_initStream
{
  if (_stream != nil) {
    return;
  }
    
  NSDebugLLog(@"SoundKit", @"[NXTSound] creating play stream...");
  _stream = [[SNDPlayStream alloc]
                initOnDevice:(SNDDevice *)[[SNDServer sharedServer] defaultOutput]
                samplingRate:[_source sampleRate]
                channelCount:[_source channelCount]
                      format:3 // PA
                        type:_streamType];
  [_stream setDelegate:self];
  if (_state == NXTSoundPlay) {
    NSDebugLLog(@"SoundKit", @"[NXTSound] desired state is `Play`...");
    _state = NXTSoundInitial;
    [self play];
  }
}

- (void)_serverStateChanged:(NSNotification *)notif
{
  SNDServer *server = [notif object];
  
  NSDebugLLog(@"SoundKit", @"[NXTSound] serverStateChanged - %i", server.status);
  
  if (server.status == SNDServerReadyState && _stream == nil) {
    [self _initStream];
  }
  else if (server.status == SNDServerFailedState ||
           server.status == SNDServerTerminatedState) {
    if (_delegate &&
        [_delegate respondsToSelector:@selector(sound:didFinishPlaying:)] != NO) {
      [_delegate sound:self didFinishPlaying:YES];
    }
  }
}

- (id)initWithContentsOfFile:(NSString *)path
                 byReference:(BOOL)byRef
                  streamType:(SNDStreamType)sType
{
  SNDServer *server;
  
  self = [super initWithContentsOfFile:path byReference:byRef];
  if (self == nil) {
    return nil;
  }

  if ([_source duration] < 0.30) {
    _isShort = YES;
  }

  NSDebugLLog(@"SoundKit",
              @"[NXTSound] channels: %lu rate: %lu format: %i duraction: %.3f",
              [_source channelCount], [_source sampleRate], [_source byteOrder],
              [_source duration]);

  _state = NXTSoundInitial;
  _streamType = sType;
  
  // 1. Connect to PulseAudio on locahost
  server = [SNDServer sharedServer];
  // 2. Wait for server to be ready
  [[NSNotificationCenter defaultCenter]
    addObserver:self
       selector:@selector(_serverStateChanged:)
           name:SNDServerStateDidChangeNotification
         object:server];
  // 3. Connect to sound server (pulseaudio)
  NSDebugLLog(@"SoundKit", @"[NXTSound] server status == %i", server.status);
  if (server.status != SNDServerReadyState) {
    NSDebugLLog(@"SoundKit", @"[NXTSound] connecting to sound server");
    [server connect];
  }
  else {
    [self _initStream];
  }

  return self;
}

- (BOOL)play
{
  if (_state == NXTSoundPlay) {
    NSDebugLLog(@"SoundKit", @"[NXTSound] PLAY skipped - already playing.\n");
    return NO;
  }

  // Mark as 'Play' no matter if _stream exist or doesn't
  _state = NXTSoundPlay;
  
  if (_stream != nil) {
    if (_stream.isActive == NO) {
      [_stream activate];
    }
    else {
      [self soundStream:_stream bufferReady:[_stream bufferLength]];
    }
    // If user calls release just after this method, sound will not be played.
    // We're retain ourself to release it in -streamBufferEmpty:.
    if ([self retainCount] <= 1) {
      [self retain];
    }

    return YES;
  }

  NSDebugLLog(@"SoundKit", @"[NXTSound] PLAY skipped - no stream found.\n");
  return NO;
}
- (BOOL)stop
{
  if (_stream && _state != NXTSoundFinished) {
    NSDebugLLog(@"SoundKit", @"[NXTSound] STOP at time: %.2f/%0.2f",
                [_source currentTime], [_source duration]);
    
    _state = NXTSoundFinished;
    [_stream empty:YES];
    [self setCurrentTime:0];
    return YES;
  }
  return NO;
}
- (BOOL)pause
{
  if (_stream && _state != NXTSoundPause) {
    [_stream pause:self];
    _state = NXTSoundPause;
    return YES;
  }
  return NO;
}
- (BOOL)resume
{
  if (_stream && _state != NXTSoundPlay && _state != NXTSoundFinished) {
    [_stream resume:self];
    _state = NXTSoundPlay;
    return YES;
  }
  return NO;
}
- (BOOL)isPlaying
{
  if (_stream == nil)
    return NO;
  
  if (_state != NXTSoundPlay && _state != NXTSoundPause)
    return NO;

  return YES;
}

// --- SNDPlayStream delegate
- (void)soundStream:(SNDPlayStream *)sndStream bufferReady:(NSNumber *)count
{
  NSUInteger bytes_length;
  NSUInteger bytes_read;
  float      *buffer;

  if (_state != NXTSoundPlay) {
    return;
  }

  bytes_length = [count unsignedIntValue];
  // NSDebugLLog(@"SoundKit", @"[NXTSound] PLAY %lu bytes of sound", bytes_length);
  
  buffer = malloc(sizeof(short) * bytes_length);
  bytes_read = [_source readBytes:buffer length:bytes_length];
  // NSDebugLLog(@"SoundKit", @"[NXTSound] READ %lu bytes of sound", bytes_read);
  
  if (bytes_read == 0) {
    free(buffer);
    _state = NXTSoundFinished;
    [_stream empty:NO];
    return;
  }
  
  // `buffer` will be freed by PA function called by SNDPlayStream
  [_stream playBuffer:buffer size:bytes_read tag:0];
  if (_isShort) {
    [_stream empty:NO];
  }
}
- (void)soundStreamBufferEmpty:(SNDPlayStream *)sndStream
{
  NSDebugLLog(@"SoundKit", @"[NXTSound] stream buffer is empty %.2f/%0.2f",
              [_source currentTime], [_source duration]);
  if (_state != NXTSoundFinished) {
    [self soundStream:_stream bufferReady:[_stream bufferLength]];
  }
  else {
    if (_delegate &&
        [_delegate respondsToSelector:@selector(sound:didFinishPlaying:)] != NO) {
      [_delegate sound:self didFinishPlaying:YES];
    }

    [self setCurrentTime:0];
    // TODO: balance -play's [self retain]
    // if ([self retainCount] >= 1) {
    //   NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.1
    //                                                     target:self
    //                                                   selector:@selector(release:)
    //                                                   userInfo:nil
    //                                                    repeats:NO];
    //   [timer setFireDate:[NSDate dateWithTimeIntervalSinceNow:0.9]];
    //   // [timer fire];
    //   // [self release];
    // }
  }
}

// - (void)release:(NSTimer *)timer
// {
//   [self release];
// }

@end
