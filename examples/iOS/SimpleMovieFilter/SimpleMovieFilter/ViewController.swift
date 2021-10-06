import UIKit
import GPUImage

class ViewController: UIViewController {
    
    @IBOutlet weak var renderView: RenderView!
    
    var movie:MovieInput!
    var filter:Pixellate!
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        let bundleURL = Bundle.main.resourceURL!
        let movieURL = URL(string:"sample_iPod.m4v", relativeTo:bundleURL)!
        
        do {
            movie = try MovieInput(url:movieURL, playAtActualSpeed:true, loop: false, startSecond: 30)
            filter = Pixellate()
            movie --> filter --> renderView
            movie.runBenchmark = false
            movie.start()
        } catch {
            print("Couldn't process movie with error: \(error)")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.takePhoto()
        }
    }
    
    func takePhoto() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("image.png")
        movie.saveNextFrameToURL(url, format: .png) { didSave in
            print("did save image to URL \(didSave) \(url)")
        }
    }
}

