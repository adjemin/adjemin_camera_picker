import 'package:adjemin_camera_picker/src/models/camera_config.dart';
import 'package:adjemin_camera_picker/src/widgets/custom_button_widget.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';

import 'package:video_player/video_player.dart';

class CameraPicker extends StatefulWidget {

  final CameraConfig config;
  const CameraPicker({super.key, required this.config});

  static Future<XFile?> pickFromCamera(BuildContext context,{CameraConfig config = const CameraConfig(),bool useRootNavigator = true})async{
    return Navigator.of(context, rootNavigator: useRootNavigator).push<XFile>(
        MaterialPageRoute(builder: (_)=>  CameraPicker(config: config)));
  }


  @override
  State<CameraPicker> createState() => _CameraPickerState();

}

class _CameraPickerState extends State<CameraPicker> with WidgetsBindingObserver, TickerProviderStateMixin {

  List<CameraDescription> _cameras = <CameraDescription>[];
  CameraController? _cameraController;
  XFile? imageFile;
  XFile? videoFile;
  VideoPlayerController? videoController;
  VoidCallback? videoPlayerListener;
  bool enableAudio = true;
  double _minAvailableExposureOffset = 0.0;
  double _maxAvailableExposureOffset = 0.0;
  double _currentExposureOffset = 0.0;
  late AnimationController _flashModeControlRowAnimationController;
  late Animation<double> _flashModeControlRowAnimation;
  late AnimationController _exposureModeControlRowAnimationController;
  late Animation<double> _exposureModeControlRowAnimation;
  late AnimationController _focusModeControlRowAnimationController;
  late Animation<double> _focusModeControlRowAnimation;
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _currentScale = 1.0;
  double _baseScale = 1.0;

  // Counting pointers (number of user fingers on screen)
  int _pointers = 0;

  XFile? _currentPicture;

  @override
  void initState() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    availableCameras().then((availableCameras)async {

      _cameras = availableCameras;

      if(availableCameras.isNotEmpty){
        final List<CameraDescription> list = availableCameras.where((a)=>a.lensDirection == CameraLensDirection.front).toList();

        if(widget.config.isFront() && list.isNotEmpty){
          await onNewCameraSelected(availableCameras.last);
        }else{
          await onNewCameraSelected(availableCameras.first);
        }

      }

    }).catchError((err) {
      // 3
      print('Error: $err.code\nError Message: $err.message');

    });

     Future.delayed(Duration.zero);

    _flashModeControlRowAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _flashModeControlRowAnimation = CurvedAnimation(
      parent: _flashModeControlRowAnimationController,
      curve: Curves.easeInCubic,
    );
    _exposureModeControlRowAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _exposureModeControlRowAnimation = CurvedAnimation(
      parent: _exposureModeControlRowAnimationController,
      curve: Curves.easeInCubic,
    );
    _focusModeControlRowAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _focusModeControlRowAnimation = CurvedAnimation(
      parent: _focusModeControlRowAnimationController,
      curve: Curves.easeInCubic,
    );

  }

    @override
  void dispose() {

    WidgetsBinding.instance.removeObserver(this);
    _flashModeControlRowAnimationController.dispose();
    _exposureModeControlRowAnimationController.dispose();
    _cameraController?.dispose();
    _cameraController = null;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  // #docregion AppLifecycle
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      //cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCameraController(cameraController.description);
    }
  }
  // #enddocregion AppLifecycle

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(builder: (ctxt, orientation){
      print("OrientationBuilder =>> ${orientation}");
      if( widget.config.isBack()){
        if(orientation == Orientation.portrait){
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeRight,
            DeviceOrientation.landscapeLeft,
          ]);
        }

        return  _buildLandscapeUi();
      }else{
        if(orientation == Orientation.landscape){
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ]);
        }
        return _buildPortraitUi();
      }

    });
  }

  /// Display the preview from the camera (or a message if the preview is not available).
  Widget _cameraPreviewWidget() {
    final CameraController? cameraController = _cameraController;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return const Text(
        'Tap a camera',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24.0,
          fontWeight: FontWeight.w900,
        ),
      );
    } else {
      return Listener(
        onPointerDown: (_) => _pointers++,
        onPointerUp: (_) => _pointers--,
        child: CameraPreview(
          _cameraController!,
          child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _handleScaleStart,
                  onScaleUpdate: _handleScaleUpdate,
                  onTapDown: (TapDownDetails details) =>
                      onViewFinderTap(details, constraints),
                );
              }),
        ),
      );
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _currentScale;
  }

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    // When there are not exactly two fingers on screen don't scale
    if (_cameraController == null || _pointers != 2) {
      return;
    }

    _currentScale = (_baseScale * details.scale)
        .clamp(_minAvailableZoom, _maxAvailableZoom);

    await _cameraController!.setZoomLevel(_currentScale);
  }

  /// Display a bar with buttons to change the flash and exposure modes
  Widget _modeControlRowWidget() {
    return   Container(
      width: 55,
      height: 55,
      decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black
      ),
      child: _cameraController?.value.flashMode != FlashMode.always?IconButton(
        icon: const Icon(Icons.flash_off),
        color: Colors.white,
        onPressed: _cameraController != null
            ? () => onSetFlashModeButtonPressed(FlashMode.off)
            : null,
      ):IconButton(
        icon: const Icon(Icons.flash_on),
        color: Colors.white,
        onPressed: _cameraController != null
            ? () => onSetFlashModeButtonPressed(FlashMode.always)
            : null,
      ),
    );
  }


  /// Display the control bar with buttons to take pictures and record videos.
  Widget _captureControlRowWidget() {
    final CameraController? cameraController = _cameraController;

    return Container(
      width: 70,
      height: 70,
      margin: const EdgeInsets.only(top: 20, bottom: 20),
      decoration: const BoxDecoration(
        color: Colors.amber,
        shape: BoxShape.circle
      ),
      child: IconButton(
        icon: const Icon(Icons.camera_alt),
        color: Colors.black,
        onPressed: cameraController != null &&
            cameraController.value.isInitialized &&
            !cameraController.value.isRecordingVideo
            ? onTakePictureButtonPressed
            : null,
      ),
    );
  }

  /// Display a row of toggle to select the camera (or a message if no camera is available).
  Widget _cameraTogglesRowWidget() {

    void onChanged(CameraDescription? description) {
      if (description == null) {
        return;
      }

      onNewCameraSelected(description);
    }

/*    if (_cameras.isEmpty) {
      SchedulerBinding.instance.addPostFrameCallback((_) async {
       // showInSnackBar('No camera found.');
      });
      return const Text('None');
    }*/

    return Container(
      width: 55,
      height: 55,
      decoration: const BoxDecoration(
        color: Colors.black,
        shape: BoxShape.circle
      ),
      child: IconButton(onPressed: (){
        final currentDirec = _cameraController?.description == CameraLensDirection.back;
        if(!currentDirec){
          onChanged(_cameras[0]);
        }
        if(currentDirec){
          onChanged(_cameras[1]);
        }

       if(mounted){
         setState(() {

         });
       }

      },icon: const Icon(Icons.refresh),color: Colors.white,)
    );
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void onViewFinderTap(TapDownDetails details, BoxConstraints constraints) {
    if (_cameraController == null) {
      return;
    }

    final CameraController cameraController = _cameraController!;

    final Offset offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    cameraController.setExposurePoint(offset);
    cameraController.setFocusPoint(offset);
  }

  Future<void> onNewCameraSelected(CameraDescription cameraDescription) async {
    if (_cameraController != null) {
      return _cameraController!.setDescription(cameraDescription);
    } else {
      return _initializeCameraController(cameraDescription);
    }
  }

  Future<void> _initializeCameraController(
      CameraDescription cameraDescription) async {

    final CameraController cameraController = CameraController(
      cameraDescription,
       ResolutionPreset.medium,
      enableAudio: enableAudio,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _cameraController = cameraController;

    // If the _cameraController is updated then update the UI.
    _cameraController?.addListener(() {
      if (mounted) {
        setState(() {});
      }
      if (_cameraController!= null && _cameraController!.value.hasError) {
        showInSnackBar(
            'Camera error ${_cameraController?.value.errorDescription}');
      }
    });

    try {
      await _cameraController?.initialize();
      await Future.wait(<Future<Object?>>[
        // The exposure mode is currently not supported on the web.
        ...<Future<Object?>>[
          _cameraController!.getMinExposureOffset().then(
                  (double value) => _minAvailableExposureOffset = value),
          _cameraController!
              .getMaxExposureOffset()
              .then((double value) => _maxAvailableExposureOffset = value)
        ]
            ,
        _cameraController!
            .getMaxZoomLevel()
            .then((double value) => _maxAvailableZoom = value),
        _cameraController!
            .getMinZoomLevel()
            .then((double value) => _minAvailableZoom = value),
      ]);
    } on CameraException catch (e) {
      switch (e.code) {
        case 'CameraAccessDenied':
          showInSnackBar('You have denied camera access.');
        case 'CameraAccessDeniedWithoutPrompt':
        // iOS only
          showInSnackBar('Please go to Settings app to enable camera access.');
        case 'CameraAccessRestricted':
        // iOS only
          showInSnackBar('Camera access is restricted.');
        case 'AudioAccessDenied':
          showInSnackBar('You have denied audio access.');
        case 'AudioAccessDeniedWithoutPrompt':
        // iOS only
          showInSnackBar('Please go to Settings app to enable audio access.');
        case 'AudioAccessRestricted':
        // iOS only
          showInSnackBar('Audio access is restricted.');
        default:
          _showCameraException(e);
          break;
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  void onTakePictureButtonPressed() {
    takePicture().then((XFile? file) {
      if (mounted) {
        setState(() {
          imageFile = file;
          videoController?.dispose();
          videoController = null;
        });
        if (file != null) {
         // showInSnackBar('Picture saved to ${file.path}');

          showPicture(file);

        }
      }
    });
  }

  void onFlashModeButtonPressed() {
    if (_flashModeControlRowAnimationController.value == 1) {
      _flashModeControlRowAnimationController.reverse();
    } else {
      _flashModeControlRowAnimationController.forward();
      _exposureModeControlRowAnimationController.reverse();
      _focusModeControlRowAnimationController.reverse();
    }
  }

  void onExposureModeButtonPressed() {
    if (_exposureModeControlRowAnimationController.value == 1) {
      _exposureModeControlRowAnimationController.reverse();
    } else {
      _exposureModeControlRowAnimationController.forward();
      _flashModeControlRowAnimationController.reverse();
      _focusModeControlRowAnimationController.reverse();
    }
  }

  void onFocusModeButtonPressed() {
    if (_focusModeControlRowAnimationController.value == 1) {
      _focusModeControlRowAnimationController.reverse();
    } else {
      _focusModeControlRowAnimationController.forward();
      _flashModeControlRowAnimationController.reverse();
      _exposureModeControlRowAnimationController.reverse();
    }
  }

  void onAudioModeButtonPressed() {
    enableAudio = !enableAudio;
    if (_cameraController != null) {
      onNewCameraSelected(_cameraController!.description);
    }
  }

  Future<void> onCaptureOrientationLockButtonPressed() async {
    try {
      if (_cameraController!= null) {
        final CameraController cameraController = _cameraController!;
        if (cameraController.value.isCaptureOrientationLocked) {
          await cameraController.unlockCaptureOrientation();
          showInSnackBar('Capture orientation unlocked');
        } else {
          await cameraController.lockCaptureOrientation();
          showInSnackBar(
              'Capture orientation locked to ${cameraController.value.lockedCaptureOrientation.toString().split('.').last}');
        }
      }
    } on CameraException catch (e) {
      _showCameraException(e);
    }
  }

  void onSetFlashModeButtonPressed(FlashMode mode) {
    setFlashMode(mode).then((_) {
      if (mounted) {
        setState(() {});
      }
      showInSnackBar('Flash mode set to ${mode.toString().split('.').last}');
    });
  }

  void onSetExposureModeButtonPressed(ExposureMode mode) {
    setExposureMode(mode).then((_) {
      if (mounted) {
        setState(() {});
      }
      showInSnackBar('Exposure mode set to ${mode.toString().split('.').last}');
    });
  }

  void onSetFocusModeButtonPressed(FocusMode mode) {
    setFocusMode(mode).then((_) {
      if (mounted) {
        setState(() {});
      }
      showInSnackBar('Focus mode set to ${mode.toString().split('.').last}');
    });
  }

  Future<void> onPausePreviewButtonPressed() async {
    final CameraController? cameraController = _cameraController;

    if (cameraController == null || !cameraController.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return;
    }

    if (cameraController.value.isPreviewPaused) {
      await cameraController.resumePreview();
    } else {
      await cameraController.pausePreview();
    }

    if (mounted) {
      setState(() {});
    }
  }


  Future<void> setFlashMode(FlashMode mode) async {
    if (_cameraController == null) {
      return;
    }

    try {
      await _cameraController!.setFlashMode(mode);
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<void> setExposureMode(ExposureMode mode) async {
    if (_cameraController == null) {
      return;
    }

    try {
      await _cameraController!.setExposureMode(mode);
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<void> setExposureOffset(double offset) async {
    if (_cameraController == null) {
      return;
    }

    setState(() {
      _currentExposureOffset = offset;
    });
    try {
      offset = await _cameraController!.setExposureOffset(offset);
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<void> setFocusMode(FocusMode mode) async {
    if (_cameraController == null) {
      return;
    }

    try {
      await _cameraController!.setFocusMode(mode);
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<XFile?> takePicture() async {
    final CameraController? cameraController = _cameraController;
    if (cameraController == null || !cameraController.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }

    if (cameraController.value.isTakingPicture) {
      // A capture is already pending, do nothing.
      return null;
    }

    try {
      final XFile file = await cameraController.takePicture();
      return file;
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
  }

  void _showCameraException(CameraException e) {
    //_logError(e.code, e.description);
    showInSnackBar('Error: ${e.code}\n${e.description}');
  }

  void showPicture(XFile file){

    if(mounted){
      setState(() {
        _currentPicture = file;
      });
    }

  }

  _buildPictureUi() {
    return Row(
      children: [
        Expanded(
          child: Container(
            child: Image.file(File(_currentPicture!.path),fit: BoxFit.fitHeight,),
          ),
        ),
        Container(
          width:_currentPicture==null? 100: 150,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [

              CustomButtonWidget(
                width: 120,
                titleSize: 16,
                color: Theme.of(context).colorScheme.secondary,
                title: "Suivant", onTap: (){
                  Navigator.of(context).pop(_currentPicture!);

              },),

              CustomButtonWidget(
                width: 120,
                titleSize: 16,
                color: Theme.of(context).colorScheme.primary,
                title: "Reprendre", onTap: (){
                  setState(() {
                    _currentPicture = null;
                  });
              },)

            ],
          ),
        )
      ],
    );
  }
  _buildPortraitPictureUi() {
    return Column(
      children: [
        Expanded(
          child: Container(
            child: Image.file(File(_currentPicture!.path),fit: BoxFit.fitHeight,),
          ),
        ),
        Container(
          height: 150,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [

              CustomButtonWidget(
                width: 120,
                titleSize: 16,
                color: Theme.of(context).colorScheme.secondary,
                title: "Suivant", onTap: (){
                Navigator.of(context).pop(_currentPicture!);

              },),

              CustomButtonWidget(
                width: 120,
                titleSize: 16,
                color: Theme.of(context).colorScheme.primary,
                title: "Reprendre", onTap: (){
                setState(() {
                  _currentPicture = null;
                });
              },)

            ],
          ),
        )
      ],
    );
  }

  Widget _buildLandscapeUi() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _currentPicture == null?Row(
        children: <Widget>[
          _cameraController == null?const SizedBox():Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black,
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(1.0),
                    child: Center(
                      child: _cameraPreviewWidget(),
                    ),
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Container(
                        padding:  const EdgeInsets.only(top: 20, left: 50, ),
                        child: IconButton(onPressed: (){
                          Navigator.of(context).pop();

                        }, icon: const Icon(Icons.arrow_back, color: Colors.white,)),
                      ),

                      Container(
                        margin: const EdgeInsets.only(top: 20, left: 50),
                        child: Text(widget.config.title, style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold
                        ),),
                      )
                    ],
                  )

                ],
              ),
            ),
          ),
          Container(
            width: 100,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _modeControlRowWidget(),
                _captureControlRowWidget(),
                _cameraTogglesRowWidget(),

              ],
            ),
          )
        ],
      ):
      _buildPictureUi(),
    );
  }

  Widget _buildPortraitUi() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _currentPicture == null?
        Column(
          children: <Widget>[
            _cameraController == null?const SizedBox():
            Expanded(
              child: Container(
                // decoration: const BoxDecoration(
                //   color: Colors.black,
                // ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(
                        child: _cameraPreviewWidget(),
                      ),
                    ),

                    Padding(
                      padding: EdgeInsets.only(top: 10,),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Container(
                            padding:  const EdgeInsets.only(top: 20, bottom: 20),
                            child: IconButton(onPressed: (){
                              Navigator.of(context).pop();

                            }, icon: const Icon(Icons.arrow_back, color: Colors.black,)),
                          ),

                          Container(
                            margin: const EdgeInsets.only(top: 20, left: 10, bottom: 20),
                            child: Text(widget.config.title, style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              fontSize: 20
                            ),),
                          )
                        ],
                      ),
                    )

                  ],
                ),
              ),
            ),
            Container(
              height: 150,
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _modeControlRowWidget(),
                  _captureControlRowWidget(),
                  _cameraTogglesRowWidget(),

                ],
              ),
            )
          ],
        ): _buildPortraitPictureUi(),
      ),
    );
  }
}
