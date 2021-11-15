import UIKit
import GPUImage
import CoreAudio
import AVFoundation

class ViewController: UIViewController {
    
    @IBOutlet weak var renderView: RenderView!
    
    var movie:MovieInput!
    var filter:Pixellate!
//    var speaker:SpeakerOutput!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let bundleURL = Bundle.main.resourceURL!
        let movieURL = URL(string:"sample.m4v", relativeTo:bundleURL)!
        let movieURL1 = URL(string:"sample1.mp4", relativeTo:bundleURL)!
        let movieURL2 = URL(string:"sample2.mp4", relativeTo:bundleURL)!
        
        do {
            let audioDecodeSettings = [AVFormatIDKey:kAudioFormatLinearPCM,
                                       AVSampleRateKey: NSNumber(value: 44100.0),
                                       AVLinearPCMBitDepthKey: NSNumber(value: 16),
                                       AVLinearPCMIsNonInterleaved: NSNumber(value: false),
                                       AVLinearPCMIsFloatKey: NSNumber(value: false),
                                       AVLinearPCMIsBigEndianKey: NSNumber(value: false)] as [String : Any]
            
            movie = try MovieInput(urls: [movieURL2,movieURL,movieURL1], playAtActualSpeed:true, loop:true, audioSettings:audioDecodeSettings)
//            speaker = SpeakerOutput()
//            movie.audioEncodingTarget = speaker
            
            filter = Pixellate()
            movie --> filter --> renderView
            movie.runBenchmark = false
            
            movie.start(atTime: CMTime(seconds: 50, preferredTimescale: 1000))
//            speaker.start()
        } catch {
            print("Couldn't process movie with error: \(error)")
        }

//            let documentsDir = try NSFileManager.defaultManager().URLForDirectory(.DocumentDirectory, inDomain:.UserDomainMask, appropriateForURL:nil, create:true)
//            let fileURL = NSURL(string:"test.png", relativeToURL:documentsDir)!
//            try pngImage.writeToURL(fileURL, options:.DataWritingAtomic)
    }
    
    @IBAction func pause() {
        movie.pause()
//        speaker.cancel()
    }
    
    @IBAction func cancel() {
        movie.cancel()
//        speaker.cancel()
    }
    
    @IBAction func play() {
        movie.start()
//        speaker.start()
    }
}

