/// Native / non-web stub for JS interop functions.
void geoStartStream() {}

String geoGetLatest() => '{"error":"Not supported on native"}';

void geoStopStream() {}

void qrStartScan(void Function(String result) callback) {}

void qrCancelScan() {}
