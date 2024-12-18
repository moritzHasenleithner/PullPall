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
   
   private var lastPixelBufferSize: CGSize?
   
   // Define the connections (pairs of landmarks) to draw lines between
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

    // MARK: - Pose Detection
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
       // Store the pixel buffer size for coordinate conversions
       let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
       let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
       lastPixelBufferSize = CGSize(width: width, height: height)

        let visionImage = VisionImage(buffer: sampleBuffer)
        visionImage.orientation = imageOrientation()
        
        poseDetector.process(visionImage) { poses, error in
            guard error == nil, let poses = poses, !poses.isEmpty else {
                DispatchQueue.main.async {
                    self.poseOverlayLayer.path = nil // Clear overlay if no poses are detected
                }
                return
            }
            
            self.drawPoses(poses: poses)
        }
    }

    private func drawPoses(poses: [Pose]) {
       guard let pixelBufferSize = lastPixelBufferSize else {
           return
       }

       let path = UIBezierPath()

       for pose in poses {
           // Create a dictionary of landmarkType to CGPoint for easy lookup
           var landmarkPoints: [PoseLandmarkType: CGPoint] = [:]

           for landmark in pose.landmarks {
               // Normalize coordinates
               let normalizedX = landmark.position.x / pixelBufferSize.width
               let normalizedY = landmark.position.y / pixelBufferSize.height
               let normalizedPoint = CGPoint(x: normalizedX, y: normalizedY)

               // Convert to preview coordinates
               let point = videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: normalizedPoint)

               // Store for later line drawing
               landmarkPoints[landmark.type] = point

               // Draw a small circle for each landmark
               path.append(UIBezierPath(arcCenter: point, radius: 5,
                                        startAngle: 0, endAngle: 2 * .pi, clockwise: true))
           }

           // Now connect the defined landmark pairs with lines
           for (startType, endType) in poseConnections {
               if let startPoint = landmarkPoints[startType],
                  let endPoint = landmarkPoints[endType] {
                   path.move(to: startPoint)
                   path.addLine(to: endPoint)
               }
           }
       }
        
        DispatchQueue.main.async {
            self.poseOverlayLayer.path = path.cgPath
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

    // MARK: - UI Setup
    private func setupUI() {
        // Add Toggle Camera Button
        toggleButton = UIButton(type: .system)
        toggleButton.setTitle("Switch Camera", for: .normal)
        toggleButton.addTarget(self, action: #selector(toggleCamera), for: .touchUpInside)
        toggleButton.frame = CGRect(x: view.bounds.midX - 75, y: view.bounds.height - 100, width: 150, height: 50)
        toggleButton.layer.cornerRadius = 10
        toggleButton.backgroundColor = UIColor.systemBlue
        toggleButton.setTitleColor(.white, for: .normal)
        view.addSubview(toggleButton)
       view.bringSubviewToFront(toggleButton)
    }

    @objc private func toggleCamera() {
        currentCameraPosition = (currentCameraPosition == .back) ? .front : .back
        startCameraSession(position: currentCameraPosition)
    }
}
