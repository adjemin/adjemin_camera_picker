import 'package:adjemin_camera_picker/src/models/camera_type.dart';

class CameraConfig{
  final String title;
  final CameraType cameraType;
  const CameraConfig({ this.title = "Camera", this.cameraType = CameraType.back});

  isFront() => cameraType == CameraType.front;

  isBack() => cameraType == CameraType.back;
}