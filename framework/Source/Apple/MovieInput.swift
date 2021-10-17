import AVFoundation

public typealias MovieCompletion = (() -> Void)

public class MovieInput: ImageSource {
    public let targets = TargetContainer()
    public var runBenchmark = false
    public var playSound = false
    
    var completionCallback: MovieCompletion? = nil
    public var timeDidChange: ((TimeInterval, TimeInterval) -> Void)? = nil
    
    let yuvConversionShader:ShaderProgram
    let asset:AVAsset
    var assetReader:AVAssetReader
    let playAtActualSpeed:Bool
    let loop:Bool
    var videoEncodingIsFinished = false
    var previousFrameTime = kCMTimeZero
    var previousActualFrameTime = CFAbsoluteTimeGetCurrent()

    var numberOfFramesCaptured = 0
    var totalFrameTimeDuringCapture:Double = 0.0
    
    var startSecond: Double = 0
    
    var seekTime: Double = 0
    var completionSeekCallback: MovieCompletion? = nil
    
    var hasAudioTrack = false
    // Add all below three lines
    var theAudioPlayer: AVPlayer?
    var startActualFrameTime: CFAbsoluteTime?
    var currentVideoTime: Double = 0

    // TODO: Add movie reader synchronization
    // TODO: Someone will have to add back in the AVPlayerItem logic, because I don't know how that works
    public init(asset:AVAsset, playAtActualSpeed:Bool = false, loop:Bool = false, startSecond: Double = 0) throws {
        self.asset = asset
        self.playAtActualSpeed = playAtActualSpeed
        self.loop = loop
        self.startSecond = startSecond
        self.yuvConversionShader = crashOnShaderCompileFailure("MovieInput"){try sharedImageProcessingContext.programForVertexShader(defaultVertexShaderForInputs(2), fragmentShader:YUVConversionFullRangeFragmentShader)}
        
        assetReader = try AVAssetReader(asset:self.asset)
        
        let outputSettings:[String:AnyObject] = [(kCVPixelBufferPixelFormatTypeKey as String):NSNumber(value:Int32(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange))]
        let readerVideoTrackOutput = AVAssetReaderTrackOutput(track:self.asset.tracks(withMediaType: AVMediaType.video)[0], outputSettings:outputSettings)
        readerVideoTrackOutput.alwaysCopiesSampleData = false
        readerVideoTrackOutput.supportsRandomAccess = true
        assetReader.add(readerVideoTrackOutput)
        // TODO: Audio here
        hasAudioTrack = self.asset.tracks(withMediaType: AVMediaType.audio).count > 0
    }

    public convenience init(url:URL, playAtActualSpeed:Bool = false, loop:Bool = false, startSecond: Double = 0) throws {
        let inputOptions = [AVURLAssetPreferPreciseDurationAndTimingKey:NSNumber(value:true)]
        let inputAsset = AVURLAsset(url:url, options:inputOptions)
        try self.init(asset:inputAsset, playAtActualSpeed:playAtActualSpeed, loop:loop, startSecond: startSecond)
    }

    // MARK: -
    // MARK: Playback control

    
    public func start(startSecond: Double = 0, completionCallback callback: MovieCompletion? = nil) {
        self.completionCallback = callback
        self.startSecond = startSecond
        currentVideoTime = 0.0
        if playSound {
            setupSound()
        }
        asset.loadValuesAsynchronously(forKeys:["tracks"], completionHandler:{ [weak self] in
            standardProcessingQueue.async(execute: {  [weak self] in
                guard let self = self else { return }
                guard (self.asset.statusOfValue(forKey: "tracks", error:nil) == .loaded) else { return }

                guard self.assetReader.startReading() else {
                    print("Couldn't start reading")
                    return
                }
                
                var readerVideoTrackOutput:AVAssetReaderOutput? = nil;
                
                for output in self.assetReader.outputs {
                    if(output.mediaType == AVMediaType.video.rawValue) {
                        readerVideoTrackOutput = output;
                    }
                }
                
                self.startPlayAfterLoadedAsset(readerVideoTrackOutput: readerVideoTrackOutput)
            })
        })
    }
    
    public func seekVideoTO(seconds: Double, completion: MovieCompletion? = nil) throws {
        self.completionSeekCallback = completion
        seekTime = seconds
        print("TTTT: start seeking \(seekTime)")

    }
    
    private func doSeek() throws {
        
        
        assetReader = try AVAssetReader(asset:self.asset)
        let outputSettings:[String:AnyObject] = [(kCVPixelBufferPixelFormatTypeKey as String):NSNumber(value:Int32(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange))]
        let readerVideoTrackOutput = AVAssetReaderTrackOutput(track:self.asset.tracks(withMediaType: AVMediaType.video)[0], outputSettings:outputSettings)
        readerVideoTrackOutput.alwaysCopiesSampleData = false
        readerVideoTrackOutput.supportsRandomAccess = true
        assetReader.add(readerVideoTrackOutput)
        // TODO: Audio here
        hasAudioTrack = self.asset.tracks(withMediaType: AVMediaType.audio).count > 0
        
        start(startSecond: seekTime, completionCallback: completionCallback)
        
        seekTime = 0
    }
    
    private func startPlayAfterLoadedAsset(readerVideoTrackOutput: AVAssetReaderOutput?) {
        guard let readerVideoTrackOutput = readerVideoTrackOutput else {
            self.endProcessing()
            return
        }
            
        while (self.assetReader.status == .reading && seekTime == 0) {
            self.readNextVideoFrame(from:readerVideoTrackOutput)
        }
        
        if (self.assetReader.status == .completed) {
            self.assetReader.cancelReading()
            
            if (self.loop) {
                // TODO: Restart movie processing
            } else {
                self.endProcessing()
            }
        }
        
        if seekTime > 0 {
            try? doSeek()
        }
    }
    
    public func cancel() {
        assetReader.cancelReading()
        self.completionCallback = nil
        self.timeDidChange = nil
//        self.endProcessing()
        if (theAudioPlayer != nil) {
            theAudioPlayer?.pause();
            theAudioPlayer = nil
        }
    }
    
    func endProcessing() {
        if let callback = self.completionCallback {
            callback()
            self.completionCallback = nil
        }
        self.timeDidChange = nil
        
        if (theAudioPlayer != nil) {
            theAudioPlayer?.pause();
            theAudioPlayer = nil
        }
    }
    
    func setupSound() {
        if (theAudioPlayer != nil) {
            theAudioPlayer?.pause()
            theAudioPlayer = nil
        }
        let playerItem = AVPlayerItem(asset: asset)
        theAudioPlayer = AVPlayer(playerItem: playerItem)
    }
    
    // MARK: -
    // MARK: Internal processing functions
    
    func checkValidTime(time: CMTime) -> Bool {
        return time.seconds >= self.startSecond
    }
    
    func readNextVideoFrame(from videoTrackOutput:AVAssetReaderOutput) {
        if ((assetReader.status == .reading) && !videoEncodingIsFinished) {
            if let sampleBuffer = videoTrackOutput.copyNextSampleBuffer() {
                
                let currentSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
                
                    // Do this outside of the video processing queue to not slow that down while waiting
                let differenceFromLastFrame = CMTimeSubtract(currentSampleTime, previousFrameTime)
                let currentActualTime = CFAbsoluteTimeGetCurrent()
                
                startActualFrameTime = currentActualTime - currentVideoTime
                
                let frameTimeDifference = CMTimeGetSeconds(differenceFromLastFrame)
                let actualTimeDifference = currentActualTime - previousActualFrameTime
                
                if (frameTimeDifference > actualTimeDifference) && checkValidTime(time: currentSampleTime) && playAtActualSpeed {
                    timeDidChange?(currentSampleTime.seconds, asset.duration.seconds)
                    self.completionSeekCallback?()
                    self.completionSeekCallback = nil
                    usleep(UInt32(round(1000000.0 * (frameTimeDifference - actualTimeDifference))))
                }
                
                previousFrameTime = currentSampleTime
                previousActualFrameTime = CFAbsoluteTimeGetCurrent()

                sharedImageProcessingContext.runOperationSynchronously{
                    if checkValidTime(time: currentSampleTime) {
                        self.process(movieFrame:sampleBuffer)
                    }
                    
                    CMSampleBufferInvalidate(sampleBuffer)
                }
            } else {
                if (!loop) {
                    videoEncodingIsFinished = true
                    if (videoEncodingIsFinished) {
                        self.endProcessing()
                    }
                }
            }
        }

    }
    
    func process(movieFrame frame:CMSampleBuffer) {
        let currentSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(frame)
        let movieFrame = CMSampleBufferGetImageBuffer(frame)!
        self.process(movieFrame:movieFrame, withSampleTime:currentSampleTime)
    }
    
    func process(movieFrame:CVPixelBuffer, withSampleTime:CMTime) {
        let bufferHeight = CVPixelBufferGetHeight(movieFrame)
        let bufferWidth = CVPixelBufferGetWidth(movieFrame)
        CVPixelBufferLockBaseAddress(movieFrame, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))

        let conversionMatrix = colorConversionMatrix601FullRangeDefault
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        if (self.playSound && hasAudioTrack && (theAudioPlayer?.rate == 0 && theAudioPlayer?.error == nil)) {
            let time = CMTime(seconds: startSecond, preferredTimescale: 1000)
            theAudioPlayer?.seek(to: time)
            theAudioPlayer?.play()
        }
        
#if os(iOS)
        var luminanceGLTexture: CVOpenGLESTexture?
        
        glActiveTexture(GLenum(GL_TEXTURE0))
        
        let luminanceGLTextureResult = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, sharedImageProcessingContext.coreVideoTextureCache, movieFrame, nil, GLenum(GL_TEXTURE_2D), GL_LUMINANCE, GLsizei(bufferWidth), GLsizei(bufferHeight), GLenum(GL_LUMINANCE), GLenum(GL_UNSIGNED_BYTE), 0, &luminanceGLTexture)
        
        assert(luminanceGLTextureResult == kCVReturnSuccess && luminanceGLTexture != nil)
        
        let luminanceTexture = CVOpenGLESTextureGetName(luminanceGLTexture!)
        
        glBindTexture(GLenum(GL_TEXTURE_2D), luminanceTexture)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE));
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE));
        
        let luminanceFramebuffer: Framebuffer
        do {
            luminanceFramebuffer = try Framebuffer(context: sharedImageProcessingContext, orientation: .portrait, size: GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)), textureOnly: true, overriddenTexture: luminanceTexture)
        } catch {
            fatalError("Could not create a framebuffer of the size (\(bufferWidth), \(bufferHeight)), error: \(error)")
        }
        
//         luminanceFramebuffer.cache = sharedImageProcessingContext.framebufferCache
        luminanceFramebuffer.lock()
        
        
        var chrominanceGLTexture: CVOpenGLESTexture?
        
        glActiveTexture(GLenum(GL_TEXTURE1))
        
        let chrominanceGLTextureResult = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, sharedImageProcessingContext.coreVideoTextureCache, movieFrame, nil, GLenum(GL_TEXTURE_2D), GL_LUMINANCE_ALPHA, GLsizei(bufferWidth / 2), GLsizei(bufferHeight / 2), GLenum(GL_LUMINANCE_ALPHA), GLenum(GL_UNSIGNED_BYTE), 1, &chrominanceGLTexture)
        
        assert(chrominanceGLTextureResult == kCVReturnSuccess && chrominanceGLTexture != nil)
        
        let chrominanceTexture = CVOpenGLESTextureGetName(chrominanceGLTexture!)
        
        glBindTexture(GLenum(GL_TEXTURE_2D), chrominanceTexture)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE));
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE));
        
        let chrominanceFramebuffer: Framebuffer
        do {
            chrominanceFramebuffer = try Framebuffer(context: sharedImageProcessingContext, orientation: .portrait, size: GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)), textureOnly: true, overriddenTexture: chrominanceTexture)
        } catch {
            fatalError("Could not create a framebuffer of the size (\(bufferWidth), \(bufferHeight)), error: \(error)")
        }
        
//         chrominanceFramebuffer.cache = sharedImageProcessingContext.framebufferCache
        chrominanceFramebuffer.lock()
#else
        let luminanceFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation:.portrait, size:GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)), textureOnly:true)
        luminanceFramebuffer.lock()
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), luminanceFramebuffer.texture)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_LUMINANCE, GLsizei(bufferWidth), GLsizei(bufferHeight), 0, GLenum(GL_LUMINANCE), GLenum(GL_UNSIGNED_BYTE), CVPixelBufferGetBaseAddressOfPlane(movieFrame, 0))
        
        let chrominanceFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation:.portrait, size:GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)), textureOnly:true)
        chrominanceFramebuffer.lock()
        glActiveTexture(GLenum(GL_TEXTURE1))
        glBindTexture(GLenum(GL_TEXTURE_2D), chrominanceFramebuffer.texture)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_LUMINANCE_ALPHA, GLsizei(bufferWidth / 2), GLsizei(bufferHeight / 2), 0, GLenum(GL_LUMINANCE_ALPHA), GLenum(GL_UNSIGNED_BYTE), CVPixelBufferGetBaseAddressOfPlane(movieFrame, 1))
#endif
        let movieFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation:.portrait, size:GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)), textureOnly:false)
        
        convertYUVToRGB(shader:self.yuvConversionShader, luminanceFramebuffer:luminanceFramebuffer, chrominanceFramebuffer:chrominanceFramebuffer, resultFramebuffer:movieFramebuffer, colorConversionMatrix:conversionMatrix)
        CVPixelBufferUnlockBaseAddress(movieFrame, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))

        movieFramebuffer.timingStyle = .videoFrame(timestamp:Timestamp(withSampleTime))
        self.updateTargetsWithFramebuffer(movieFramebuffer)
        
        if self.runBenchmark {
            let currentFrameTime = (CFAbsoluteTimeGetCurrent() - startTime)
            self.numberOfFramesCaptured += 1
            self.totalFrameTimeDuringCapture += currentFrameTime
            print("Average frame time : \(1000.0 * self.totalFrameTimeDuringCapture / Double(self.numberOfFramesCaptured)) ms")
            print("Current frame time : \(1000.0 * currentFrameTime) ms")
        }
    }

    public func transmitPreviousImage(to target:ImageConsumer, atIndex:UInt) {
        // Not needed for movie inputs
    }
}
