import 'storage_backend_interface.dart';
import 'storage_backend_io.dart'
    if (dart.library.html) 'storage_backend_web.dart'
    as impl;

export 'storage_backend_interface.dart';

StorageBackend createStorageBackend({String? baseDir}) =>
    impl.createStorageBackend(baseDir: baseDir);
