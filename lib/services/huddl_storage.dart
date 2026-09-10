import 'package:firebase_storage/firebase_storage.dart';

/// STORAGE-REGION-US-1: the project's DEFAULT bucket is in US-EAST1 and its
/// region cannot be changed. All Huddl uploads must go to huddl-connect-eu
/// (europe-west2). google-services.json / GoogleService-Info.plist emit the
/// default bucket, so FirebaseStorage.instance resolves to the US bucket —
/// the bucket MUST be named explicitly here.
///
/// Every upload path in the app uses HuddlStorage.instance. Do not call
/// FirebaseStorage.instance directly; a single missed call site writes user
/// photographs to the United States without any visible symptom.
///
/// API note (firebase_storage 12.0.1, verified against package source):
///   FirebaseStorage.instanceFor({FirebaseApp? app, String? bucket})
///   The named parameter is `bucket`. The gs:// prefix IS accepted — the
///   package strips it internally (firebase_storage.dart lines 77-82). Both
///   the bare bucket name and the gs:// form are valid; the gs:// form is used
///   here to make the intent unambiguous at a glance.
class HuddlStorage {
  static const String bucket = 'gs://huddl-connect-eu';
  static FirebaseStorage get instance =>
      FirebaseStorage.instanceFor(bucket: bucket);
}
