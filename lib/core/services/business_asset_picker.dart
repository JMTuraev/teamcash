import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final businessAssetPickerProvider = Provider<BusinessAssetPicker>(
  (ref) => const FilePickerBusinessAssetPicker(),
);

class PickedBusinessAsset {
  const PickedBusinessAsset({
    required this.bytes,
    required this.fileName,
    required this.contentType,
  });

  final Uint8List bytes;
  final String fileName;
  final String contentType;
}

abstract class BusinessAssetPicker {
  Future<PickedBusinessAsset?> pickImage({String? dialogTitle});
}

class FilePickerBusinessAssetPicker implements BusinessAssetPicker {
  const FilePickerBusinessAssetPicker();

  @override
  Future<PickedBusinessAsset?> pickImage({String? dialogTitle}) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle ?? 'Choose image',
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
      withData: true,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('The selected image could not be read.');
    }

    return PickedBusinessAsset(
      bytes: bytes,
      fileName: _sanitizeFileName(file.name),
      contentType: _inferImageContentType(
        file.extension ?? _extensionFromFileName(file.name),
      ),
    );
  }
}

String _sanitizeFileName(String value) {
  final sanitized = value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-');
  if (sanitized.isEmpty) {
    return 'upload.png';
  }
  return sanitized;
}

String _inferImageContentType(String extension) {
  switch (extension.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'webp':
      return 'image/webp';
    case 'png':
    default:
      return 'image/png';
  }
}

String _extensionFromFileName(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == fileName.length - 1) {
    return '';
  }
  return fileName.substring(dotIndex + 1);
}
