import UIKit
import GPUImage

class ViewController: UIViewController {
    
    @IBOutlet weak var renderView: RenderView!
    
    var movie:MovieInput! {
        didSet {
            print("Movie did set")
        }
    }
    
    var currentSliderValue: Float = 0
    
    @IBOutlet weak var slider: UISlider!
    var filter:Pixellate!
    
    var durationVideo: Double = 0
    var isSeeking = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let bundleURL = Bundle.main.resourceURL!
        let movieURL = URL(string:"sample_iPod.m4v", relativeTo:bundleURL)!
        
        do {
            movie = try MovieInput(url:movieURL, playAtActualSpeed:true, loop: false, startSecond: 30)
            filter = Pixellate()
            movie --> filter --> renderView
            movie.runBenchmark = false
            movie.timeDidChange = { (start, end) in
                print("TTTT \(start)")
                self.durationVideo = end
                DispatchQueue.main.async {
                    if !self.isSeeking {
                        self.slider.value = Float(start / end)
                    }
                }
            }
            movie.start()
        } catch {
            print("Couldn't process movie with error: \(error)")
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        
        
        //        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        //            self.movie.seekVideoTO(seconds: 15)
        //            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        //                self.movie.seekVideoTO(seconds: 17)
        //            }
        //        }
        
    }
    
    func takePhoto() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("image.png")
        movie.saveNextFrameToURL(url, format: .png) { didSave in
            print("did save image to URL \(didSave) \(url)")
        }
    }
    
    
    
    @IBAction func valueSliderChange(slider: UISlider) {
        print("TTTT Start slider: \(slider.value)")
        currentSliderValue = slider.value
        if self.isSeeking {
            return
        }
        self.isSeeking = true
        
        Throttler.go(identifier: "Seek_video", delay: 1) { [weak self] in
            guard let self = self else {return}
            self.doSeek()
        }
    }
    
    private func doSeek() {
        
        print("TTTT  Start seeking: \(currentSliderValue)")
        let value = Double(currentSliderValue) * self.durationVideo
        try? self.movie.seekVideoTO(seconds: value, completion: {
            self.isSeeking = false
        })
    }
}

