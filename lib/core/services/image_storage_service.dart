// lib/core/services/image_storage_service.dart
//
// Product photo pipeline: compress -> save locally -> upload to cloud.
// Storage backend is abstracted so swapping Supabase Storage for
// Cloudflare R2 later only means writing a new ImageStorageService impl.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/auth_provider.dart';

abstract class ImageStorageService {
  Future<String> upload(Uint8List bytes, String remotePath);
  Future<void> delete(String remotePath);
}

class SupabaseImageStorage implements ImageStorageService {
  final SupabaseClient _client;
  static const _bucket = 'product-images';

  SupabaseImageStorage(this._client);

  @override
  Future<String> upload(Uint8List bytes, String remotePath) async {
    await _client.storage.from(_bucket).uploadBinary(
          remotePath,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    return _client.storage.from(_bucket).getPublicUrl(remotePath);
  }

  @override
  Future<void> delete(String remotePath) async {
    await _client.storage.from(_bucket).remove([remotePath]);
  }
}

final imageStorageServiceProvider = Provider<ImageStorageService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SupabaseImageStorage(client);
});

class ProductImagePipeline {
  static const int maxDimension = 800;
  static const int jpegQuality = 75;

  /// Resizes [sourcePath] (longest side <= 800px), re-encodes as JPEG q75,
  /// saves under app docs/product_images/{productId}.jpg. Returns the path.
  static Future<String> compressAndSaveLocal({
    required String sourcePath,
    required String productId,
  }) async {
    final bytes = await File(sourcePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Could not decode image at $sourcePath');
    }

    final resized = (decoded.width > maxDimension || decoded.height > maxDimension)
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? maxDimension : null,
            height: decoded.height > decoded.width ? maxDimension : null,
          )
        : decoded;

    final jpegBytes = img.encodeJpg(resized, quality: jpegQuality);

    final docsDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(docsDir.path, 'product_images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    final outPath = p.join(imagesDir.path, '$productId.jpg');
    await File(outPath).writeAsBytes(jpegBytes, flush: true);

    return outPath;
  }

  static Future<Uint8List> readLocalBytes(String localPath) {
    return File(localPath).readAsBytes();
  }
}