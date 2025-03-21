//
//  ViewController.swift
//  PullPal
//
//  Created by Moritz Hasenleithner on 17.12.24.
//
import UIKit
import AVFoundation
import SwiftUI
import MLKitPoseDetection
import MLKitVision

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession!
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer!
    private var currentCameraPosition: AVCaptureDevice.Position = .back
    private var toggleButton: UIButton!
    private let poseDetector: PoseDetector = PoseDetector.poseDetector(options: PoseDetectorOptions())
    private var poseOverlayLayer: CAShapeLayer!
    
    // For coordinate conversion
    private var lastPixelBufferSize: CGSize?
    
    // Landmark connections for drawing
    private let poseConnections: [(PoseLandmarkType, PoseLandmarkType)] = [
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),
        (.leftShoulder, .rightShoulder),
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle),
        (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip),
        (.leftHip, .rightHip)
    ]
    
    // Properties for pull-up counting
    private var repCount: Int = 0
    private var isPullUpInProgress: Bool = false
    private var repCountLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCameraSession()
        setupUI()
    }

    // MARK: - Camera Setup
    private func setupCameraSession() {
        captureSession = AVCaptureSession()
        startCameraSession(position: currentCameraPosition)
    }

    private func startCameraSession(position: AVCaptureDevice.Position) {
        captureSession.stopRunning()
        captureSession = AVCaptureSession()
        
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            print("Error: Unable to access camera")
            return
        }
        
        captureSession.beginConfiguration()
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        captureSession.commitConfiguration()
        setupPreviewLayer()
        setupPoseOverlayLayer()
        captureSession.startRunning()
    }

    private func setupPreviewLayer() {
        if videoPreviewLayer != nil {
            videoPreviewLayer.removeFromSuperlayer()
        }
        
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer.videoGravity = .resizeAspectFill
        videoPreviewLayer.frame = view.bounds
        view.layer.insertSublayer(videoPreviewLayer, at: 0)
    }

    private func setupPoseOverlayLayer() {
        if poseOverlayLayer != nil {
            poseOverlayLayer.removeFromSuperlayer()
        }
        
        poseOverlayLayer = CAShapeLayer()
        poseOverlayLayer.frame = view.bounds
        poseOverlayLayer.strokeColor = UIColor.red.cgColor
        poseOverlayLayer.lineWidth = 2.0
        poseOverlayLayer.fillColor = UIColor.clear.cgColor
        view.layer.addSublayer(poseOverlayLayer)
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        // Toggle camera button
        toggleButton = UIButton(type: .system)
        toggleButton.setTitle("Switch Camera", for: .normal)
        toggleButton.addTarget(self, action: #selector(toggleCamera), for: .touchUpInside)
        toggleButton.frame = CGRect(x: view.bounds.midX - 75, y: view.bounds.height - 100, width: 150, height: 50)
        toggleButton.layer.cornerRadius = 10
        toggleButton.backgroundColor = UIColor.systemBlue
        toggleButton.setTitleColor(.white, for: .normal)
        view.addSubview(toggleButton)
        view.bringSubviewToFront(toggleButton)
        
        // Rep count label
        repCountLabel = UILabel(frame: CGRect(x: 20, y: 50, width: 150, height: 50))
        repCountLabel.textColor = .white
        repCountLabel.font = UIFont.boldSystemFont(ofSize: 30)
        repCountLabel.text = "0"
        view.addSubview(repCountLabel)
        view.bringSubviewToFront(repCountLabel)
    }
    
    @objc private func toggleCamera() {
        currentCameraPosition = (currentCameraPosition == .back) ? .front : .back
        startCameraSession(position: currentCameraPosition)
    }
    
    // MARK: - Pose Detection
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        lastPixelBufferSize = CGSize(width: width, height: height)

        let visionImage = VisionImage(buffer: sampleBuffer)
        visionImage.orientation = imageOrientation()
        
        poseDetector.process(visionImage) { poses, error in
            guard error == nil, let poses = poses, !poses.isEmpty else {
                DispatchQueue.main.async {
                    self.poseOverlayLayer.path = nil // Clear overlay if no poses detected
                }
                return
            }
            self.drawPoses(poses: poses)
        }
    }
    
    // Helper: Compute angle (in degrees) at p2 given points p1, p2, p3.
    private func angle(between p1: CGPoint, p2: CGPoint, and p3: CGPoint) -> CGFloat {
        let vector1 = CGVector(dx: p1.x - p2.x, dy: p1.y - p2.y)
        let vector2 = CGVector(dx: p3.x - p2.x, dy: p3.y - p2.y)
        let dotProduct = vector1.dx * vector2.dx + vector1.dy * vector2.dy
        let magnitude1 = sqrt(vector1.dx * vector1.dx + vector1.dy * vector1.dy)
        let magnitude2 = sqrt(vector2.dx * vector2.dx + vector2.dy * vector2.dy)
        guard magnitude1 > 0, magnitude2 > 0 else { return 0 }
        let angle = acos(dotProduct / (magnitude1 * magnitude2))
        return angle * 180 / .pi
    }
    
    private func drawPoses(poses: [Pose]) {
        guard let pixelBufferSize = lastPixelBufferSize else {
            return
        }
        let path = UIBezierPath()
        
        // Process each detected pose
        for (index, pose) in poses.enumerated() {
            var landmarkPoints: [PoseLandmarkType: CGPoint] = [:]
            
            // Collect landmark points and draw small circles
            for landmark in pose.landmarks {
                let normalizedX = landmark.position.x / pixelBufferSize.width
                let normalizedY = landmark.position.y / pixelBufferSize.height
                let normalizedPoint = CGPoint(x: normalizedX, y: normalizedY)
                let point = videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: normalizedPoint)
                landmarkPoints[landmark.type] = point
                path.append(UIBezierPath(arcCenter: point, radius: 5,
                                           startAngle: 0, endAngle: 2 * .pi, clockwise: true))
            }
            
            // Draw connections between landmarks
            for (startType, endType) in poseConnections {
                if let startPoint = landmarkPoints[startType],
                   let endPoint = landmarkPoints[endType] {
                    path.move(to: startPoint)
                    path.addLine(to: endPoint)
                }
            }
            
            // For the first detected pose, run pull-up detection logic
            if index == 0 {
                var leftElbowAngle: CGFloat?
                var rightElbowAngle: CGFloat?
                
                if let leftShoulder = landmarkPoints[.leftShoulder],
                   let leftElbow = landmarkPoints[.leftElbow],
                   let leftWrist = landmarkPoints[.leftWrist] {
                    leftElbowAngle = angle(between: leftShoulder, p2: leftElbow, and: leftWrist)
                }
                
                if let rightShoulder = landmarkPoints[.rightShoulder],
                   let rightElbow = landmarkPoints[.rightElbow],
                   let rightWrist = landmarkPoints[.rightWrist] {
                    rightElbowAngle = angle(between: rightShoulder, p2: rightElbow, and: rightWrist)
                }
                
                // Use the average angle if both sides are available; otherwise use the available one.
                if let leftAngle = leftElbowAngle, let rightAngle = rightElbowAngle {
                    let averageAngle = (leftAngle + rightAngle) / 2
                    self.handlePullUpDetection(with: averageAngle)
                } else if let leftAngle = leftElbowAngle {
                    self.handlePullUpDetection(with: leftAngle)
                } else if let rightAngle = rightElbowAngle {
                    self.handlePullUpDetection(with: rightAngle)
                }
            }
        }
        
        DispatchQueue.main.async {
            self.poseOverlayLayer.path = path.cgPath
        }
    }
    
    // Uses elbow angle thresholds to update pull-up rep count.
    private func handlePullUpDetection(with elbowAngle: CGFloat) {
        // Thresholds (in degrees): adjust these values as needed
        let upThreshold: CGFloat = 50   // elbows very flexed – pull-up position
        let downThreshold: CGFloat = 160 // elbows extended – starting (or ending) position
        
        if !isPullUpInProgress && elbowAngle < upThreshold {
            // Pull-up initiated
            isPullUpInProgress = true
        } else if isPullUpInProgress && elbowAngle > downThreshold {
            // Completed one rep when returning to down position
            repCount += 1
            isPullUpInProgress = false
            DispatchQueue.main.async {
                self.repCountLabel.text = "\(self.repCount)"
            }
        }
    }
    
    private func imageOrientation() -> UIImage.Orientation {
        switch UIDevice.current.orientation {
        case .portraitUpsideDown: return .down
        case .landscapeLeft: return .left
        case .landscapeRight: return .right
        default: return .up
        }
    }
}
