import 'dart:js_interop';

@JS('_geoStartStream')
external void _geoStartStreamJS();

@JS('_geoGetLatest')
external JSString _geoGetLatestJS();

@JS('_geoStopStream')
external void _geoStopStreamJS();

@JS('_qrStartScan')
external void _qrStartScanJS(JSString callbackName);

@JS('_qrCancelScan')
external void _qrCancelScanJS();

@JS('_flutterQrResult')
external set _flutterQrResultSetter(JSFunction? fn);

void geoStartStream() {
  try {
    _geoStartStreamJS();
  } catch (_) {}
}

String geoGetLatest() {
  try {
    return _geoGetLatestJS().toDart;
  } catch (e) {
    return '{"error":"$e"}';
  }
}

void geoStopStream() {
  try {
    _geoStopStreamJS();
  } catch (_) {}
}

void qrStartScan(void Function(String result) callback) {
  try {
    _flutterQrResultSetter = ((JSString result) {
      callback(result.toDart);
    }).toJS;
    _qrStartScanJS('_flutterQrResult'.toJS);
  } catch (e) {
    callback('__CAMERA_ERROR__');
  }
}

void qrCancelScan() {
  try {
    _qrCancelScanJS();
  } catch (_) {}
}
