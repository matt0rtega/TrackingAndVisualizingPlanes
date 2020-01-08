/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 Main view controller for the AR experience.
 */

import UIKit
import SceneKit
import ARKit

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    // MARK: - IBOutlets
    
    @IBOutlet weak var sessionInfoView: UIView!
    @IBOutlet weak var sessionInfoLabel: UILabel!
    @IBOutlet weak var sceneView: ARSCNView!
    
    //4. Create Our Session
    let augmentedRealitySession = ARSession()
    
    //5. Create A Single SCNNode Which We Will Clone
    var sphereNode: SCNNode!
    
    // MARK: - View Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        generateNode()
    }
    
    /// - Tag: StartARSession
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Start the view's AR session with a configuration that uses the rear camera,
        // device position and orientation tracking, and plane detection.
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        
        // Set a delegate to track the number of plane anchors for providing UI feedback.
        sceneView.session.delegate = self
        sceneView.session = augmentedRealitySession
        
        augmentedRealitySession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        // Prevent the screen from being dimmed after a while as users will likely
        // have long periods of interaction without touching the screen or buttons.
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Show debug UI to view performance metrics (e.g. frames per second).
        sceneView.showsStatistics = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's AR session.
        sceneView.session.pause()
    }
    
    // MARK: - ARSCNViewDelegate
    
    /// - Tag: PlaceARContent
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        // Place content only for anchors found by plane detection.
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        
        // Create a custom object to visualize the plane geometry and extent.
        let plane = Plane(anchor: planeAnchor, in: sceneView)
        
        // Add the visualization to the ARKit-managed node so that it tracks
        // changes in the plane anchor as plane estimation continues.
        node.addChildNode(plane)
    }
    
    override var prefersStatusBarHidden: Bool { return true }
    
    override func didReceiveMemoryWarning() { super.didReceiveMemoryWarning() }
    
    
    /// - Tag: UpdateARContent
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        
        
        drawFeaturePoints()
        
        // Update only anchors and nodes set up by `renderer(_:didAdd:for:)`.
        if let planeAnchor = anchor as? ARPlaneAnchor {
            if let plane = node.childNodes.first as? Plane {
                
                
                // Update ARSCNPlaneGeometry to the anchor's new estimated shape.
                if let planeGeometry = plane.meshNode.geometry as? ARSCNPlaneGeometry {
                    planeGeometry.update(from: planeAnchor.geometry)
                }
                
                // Update extent visualization to the anchor's new bounding rectangle.
                if let extentGeometry = plane.extentNode.geometry as? SCNPlane {
                    extentGeometry.width = CGFloat(planeAnchor.extent.x)
                    extentGeometry.height = CGFloat(planeAnchor.extent.z)
                    plane.extentNode.simdPosition = planeAnchor.center
                }
                
                // Update the plane's classification and the text position
                if #available(iOS 12.0, *),
                    let classificationNode = plane.classificationNode,
                    let classificationGeometry = classificationNode.geometry as? SCNText {
                    let currentClassification = planeAnchor.classification.description
                    if let oldClassification = classificationGeometry.string as? String, oldClassification != currentClassification {
                        classificationGeometry.string = currentClassification
                        classificationNode.centerAlign()
                    }
                }
            }
        }
        
        
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        guard let frame = session.currentFrame else { return }
        updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        //print(frame.rawFeaturePoints)
    }
    
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        guard let frame = session.currentFrame else { return }
        updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        updateSessionInfoLabel(for: session.currentFrame!, trackingState: camera.trackingState)
    }
    
    // MARK: - ARSessionObserver
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay.
        sessionInfoLabel.text = "Session was interrupted"
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required.
        sessionInfoLabel.text = "Session interruption ended"
        resetTracking()
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        sessionInfoLabel.text = "Session failed: \(error.localizedDescription)"
        guard error is ARError else { return }
        
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        // Remove optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        
        DispatchQueue.main.async {
            // Present an alert informing about the error that has occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                self.resetTracking()
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    // MARK: - Private methods
    
    private func updateSessionInfoLabel(for frame: ARFrame, trackingState: ARCamera.TrackingState) {
        // Update the UI to provide feedback on the state of the AR experience.
        let message: String
        
        switch trackingState {
        case .normal where frame.anchors.isEmpty:
            // No planes detected; provide instructions for this app's AR interactions.
            message = "Move the device around to detect horizontal and vertical surfaces."
            
        case .notAvailable:
            message = "Tracking unavailable."
            
        case .limited(.excessiveMotion):
            message = "Tracking limited - Move the device more slowly."
            
        case .limited(.insufficientFeatures):
            message = "Tracking limited - Point the device at an area with visible surface detail, or improve lighting conditions."
            
        case .limited(.initializing):
            message = "Initializing AR session."
            
        default:
            // No feedback needed when tracking is normal and planes are visible.
            // (Nor when in unreachable limited-tracking states.)
            message = ""
            
        }
        
        sessionInfoLabel.text = message
        sessionInfoView.isHidden = message.isEmpty
    }
    
    private func resetTracking() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors ])
    }
    
    //----------------------
    //MARK: SCNNode Creation
    //----------------------
    
    
    /// Generates A Spherical SCNNode
    func generateNode(){
        sphereNode = SCNNode()
        let sphereGeometry = SCNSphere(radius: 0.001)
        sphereGeometry.firstMaterial?.diffuse.contents = UIColor.white
        sphereNode.geometry = sphereGeometry
    }
    
    func drawFeaturePoints(){
        //1. Check Our Frame Is Valid & That We Have Received Our Raw Feature Points
        guard let currentFrame = self.augmentedRealitySession.currentFrame,
            let featurePointsArray = currentFrame.rawFeaturePoints?.points else { return }
        
        //2. Visualize The Feature Points
        showFeaturePoints(featurePointsArray)
    }
    
    func showFeaturePoints(_ featurePointsArray: [vector_float3]){
        
        self.sceneView.scene.rootNode.enumerateChildNodes { (featurePoint, _) in
            
            if(featurePoint.name == "featurepoint"){
                featurePoint.geometry = nil
                featurePoint.removeFromParentNode()
            }
        }
        
        featurePointsArray.forEach { (pointLocation) in
            
            //Clone The SphereNode To Reduce CPU
            let clone = sphereNode.clone()
            clone.position = SCNVector3(pointLocation.x, pointLocation.y, pointLocation.z)
            clone.name = "featurepoint"
            self.sceneView.scene.rootNode.addChildNode(clone)
        }
    }
}

