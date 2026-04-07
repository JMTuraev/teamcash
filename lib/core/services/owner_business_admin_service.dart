import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:teamcash/app/app.dart';
import 'package:teamcash/app/bootstrap/firebase_bootstrap.dart';
import 'package:teamcash/core/models/business_content_models.dart';
import 'package:teamcash/core/services/business_asset_picker.dart';

final ownerBusinessAdminServiceProvider = Provider<OwnerBusinessAdminService>(
  (ref) => OwnerBusinessAdminService(
    firestore: FirebaseFirestore.instance,
    storage: FirebaseStorage.instance,
    bootstrapResult: ref.watch(firebaseStatusProvider),
  ),
);

final businessLocationsProvider =
    StreamProvider.family<List<BusinessLocationSummary>, String>((
      ref,
      businessId,
    ) {
      return ref
          .watch(ownerBusinessAdminServiceProvider)
          .watchLocations(businessId);
    });

final businessProductsProvider =
    StreamProvider.family<List<BusinessCatalogItemSummary>, String>((
      ref,
      businessId,
    ) {
      return ref
          .watch(ownerBusinessAdminServiceProvider)
          .watchCatalogItems(
            businessId: businessId,
            collectionName: 'products',
          );
    });

final businessServicesProvider =
    StreamProvider.family<List<BusinessCatalogItemSummary>, String>((
      ref,
      businessId,
    ) {
      return ref
          .watch(ownerBusinessAdminServiceProvider)
          .watchCatalogItems(
            businessId: businessId,
            collectionName: 'services',
          );
    });

final businessMediaProvider =
    StreamProvider.family<List<BusinessMediaSummary>, String>((
      ref,
      businessId,
    ) {
      return ref
          .watch(ownerBusinessAdminServiceProvider)
          .watchMedia(businessId);
    });

class OwnerBusinessAdminService {
  static const Duration _storageOperationTimeout = Duration(seconds: 30);

  OwnerBusinessAdminService({
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
    required FirebaseBootstrapResult bootstrapResult,
  }) : _firestore = firestore,
       _storage = storage,
       _bootstrapResult = bootstrapResult;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseBootstrapResult _bootstrapResult;

  bool get isConnected =>
      _bootstrapResult.mode == FirebaseBootstrapMode.connected;

  Future<void> updateBusinessProfile({
    required String businessId,
    required String name,
    required String category,
    required String description,
    required String address,
    required String workingHours,
    required List<String> phoneNumbers,
    required int cashbackBasisPoints,
    required String redeemPolicy,
  }) async {
    if (!isConnected) {
      throw OwnerBusinessAdminUnavailable(_bootstrapResult.message);
    }

    final normalizedPhoneNumbers = phoneNumbers
        .map((phone) => phone.trim())
        .where((phone) => phone.isNotEmpty)
        .toSet()
        .toList();

    await _firestore.doc('businesses/$businessId').update({
      'name': name.trim(),
      'category': category.trim(),
      'description': description.trim(),
      'address': address.trim(),
      'workingHours': workingHours.trim(),
      'phoneNumbers': normalizedPhoneNumbers,
      'cashbackBasisPoints': cashbackBasisPoints,
      'redeemPolicy': redeemPolicy.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateBusinessBranding({
    required String businessId,
    required String logoUrl,
    required String coverImageUrl,
    required String currentLogoStoragePath,
    required String currentCoverImageStoragePath,
    PickedBusinessAsset? logoFile,
    PickedBusinessAsset? coverFile,
  }) async {
    _ensureConnected();

    final businessRef = _firestore.doc('businesses/$businessId');
    StoredBusinessAsset? uploadedLogo;
    StoredBusinessAsset? uploadedCover;

    var resolvedLogoUrl = logoUrl.trim();
    var resolvedLogoStoragePath = currentLogoStoragePath.trim();
    var resolvedCoverImageUrl = coverImageUrl.trim();
    var resolvedCoverImageStoragePath = currentCoverImageStoragePath.trim();

    try {
      if (logoFile != null) {
        uploadedLogo = await _uploadBusinessAsset(
          businessId: businessId,
          scope: 'branding',
          docId: 'logo',
          asset: logoFile,
        );
        resolvedLogoUrl = uploadedLogo.downloadUrl;
        resolvedLogoStoragePath = uploadedLogo.storagePath;
      } else if (resolvedLogoUrl.isEmpty) {
        resolvedLogoStoragePath = '';
      }

      if (coverFile != null) {
        uploadedCover = await _uploadBusinessAsset(
          businessId: businessId,
          scope: 'branding',
          docId: 'cover',
          asset: coverFile,
        );
        resolvedCoverImageUrl = uploadedCover.downloadUrl;
        resolvedCoverImageStoragePath = uploadedCover.storagePath;
      } else if (resolvedCoverImageUrl.isEmpty) {
        resolvedCoverImageStoragePath = '';
      }

      await businessRef.update({
        'logoUrl': resolvedLogoUrl,
        'logoStoragePath': resolvedLogoStoragePath,
        'coverImageUrl': resolvedCoverImageUrl,
        'coverImageStoragePath': resolvedCoverImageStoragePath,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      await Future.wait([
        if (uploadedLogo != null)
          _deleteStorageObjectQuietly(uploadedLogo.storagePath),
        if (uploadedCover != null)
          _deleteStorageObjectQuietly(uploadedCover.storagePath),
      ]);
      rethrow;
    }

    await Future.wait([
      if (_shouldDeleteStorageObject(
        businessId: businessId,
        previousPath: currentLogoStoragePath,
        nextPath: resolvedLogoStoragePath,
      ))
        _deleteStorageObjectQuietly(currentLogoStoragePath),
      if (_shouldDeleteStorageObject(
        businessId: businessId,
        previousPath: currentCoverImageStoragePath,
        nextPath: resolvedCoverImageStoragePath,
      ))
        _deleteStorageObjectQuietly(currentCoverImageStoragePath),
    ]);
  }

  Future<List<JoinableGroupOption>> loadVisibleGroups() async {
    if (!isConnected) {
      throw OwnerBusinessAdminUnavailable(_bootstrapResult.message);
    }

    final snapshot = await _firestore.collection('groups').get();
    final groups = snapshot.docs.map((doc) {
      final data = doc.data();
      final activeBusinessIds =
          (data['activeBusinessIds'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList();
      return JoinableGroupOption(
        id: doc.id,
        name: data['name'] as String? ?? doc.id,
        activeBusinessCount: activeBusinessIds.length,
      );
    }).toList()..sort((left, right) => left.name.compareTo(right.name));

    return groups;
  }

  Stream<List<BusinessLocationSummary>> watchLocations(String businessId) {
    _ensureConnected();

    return _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('locations')
        .snapshots()
        .map((snapshot) {
          final locations = snapshot.docs
              .map((doc) => _mapLocation(doc.id, doc.data()))
              .toList();
          locations.sort((left, right) {
            if (left.isPrimary != right.isPrimary) {
              return left.isPrimary ? -1 : 1;
            }
            return left.name.compareTo(right.name);
          });
          return locations;
        });
  }

  Stream<List<BusinessCatalogItemSummary>> watchCatalogItems({
    required String businessId,
    required String collectionName,
  }) {
    _ensureConnected();

    return _firestore
        .collection('businesses')
        .doc(businessId)
        .collection(collectionName)
        .orderBy('name')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => _mapCatalogItem(doc.id, doc.data()))
              .toList(),
        );
  }

  Stream<List<BusinessMediaSummary>> watchMedia(String businessId) {
    _ensureConnected();

    return _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('media')
        .snapshots()
        .map((snapshot) {
          final media = snapshot.docs
              .map((doc) => _mapMedia(doc.id, doc.data()))
              .toList();
          media.sort((left, right) {
            if (left.isFeatured != right.isFeatured) {
              return left.isFeatured ? -1 : 1;
            }
            return left.title.compareTo(right.title);
          });
          return media;
        });
  }

  Future<void> upsertLocation({
    required String businessId,
    String? locationId,
    required String name,
    required String address,
    required String workingHours,
    required List<String> phoneNumbers,
    required String notes,
    required bool isPrimary,
  }) async {
    _ensureConnected();

    final normalizedPhoneNumbers = phoneNumbers
        .map((phone) => phone.trim())
        .where((phone) => phone.isNotEmpty)
        .toSet()
        .toList();
    final doc = _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('locations')
        .doc(
          locationId == null || locationId.trim().isEmpty ? null : locationId,
        );
    final isCreate = locationId == null || locationId.trim().isEmpty;
    final payload = <String, Object?>{
      'id': doc.id,
      'businessId': businessId,
      'name': name.trim(),
      'address': address.trim(),
      'workingHours': workingHours.trim(),
      'phoneNumbers': normalizedPhoneNumbers,
      'notes': notes.trim(),
      'isPrimary': isPrimary,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (isCreate) {
      payload['createdAt'] = FieldValue.serverTimestamp();
    }

    await doc.set(payload, SetOptions(merge: true));
    await _syncBusinessCounts(businessId);
  }

  Future<void> deleteLocation({
    required String businessId,
    required String locationId,
  }) async {
    _ensureConnected();

    await _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('locations')
        .doc(locationId)
        .delete();
    await _syncBusinessCounts(businessId);
  }

  Future<void> upsertProduct({
    required String businessId,
    String? productId,
    required String name,
    required String description,
    required String priceLabel,
    required bool isActive,
  }) async {
    await _upsertCatalogItem(
      businessId: businessId,
      collectionName: 'products',
      itemId: productId,
      name: name,
      description: description,
      priceLabel: priceLabel,
      isActive: isActive,
    );
  }

  Future<void> deleteProduct({
    required String businessId,
    required String productId,
  }) async {
    await _deleteCatalogItem(
      businessId: businessId,
      collectionName: 'products',
      itemId: productId,
    );
  }

  Future<void> upsertService({
    required String businessId,
    String? serviceId,
    required String name,
    required String description,
    required String priceLabel,
    required bool isActive,
  }) async {
    await _upsertCatalogItem(
      businessId: businessId,
      collectionName: 'services',
      itemId: serviceId,
      name: name,
      description: description,
      priceLabel: priceLabel,
      isActive: isActive,
    );
  }

  Future<void> deleteService({
    required String businessId,
    required String serviceId,
  }) async {
    await _deleteCatalogItem(
      businessId: businessId,
      collectionName: 'services',
      itemId: serviceId,
    );
  }

  Future<void> upsertMedia({
    required String businessId,
    String? mediaId,
    required String title,
    required String caption,
    required String mediaType,
    required String imageUrl,
    required bool isFeatured,
    String currentStoragePath = '',
    PickedBusinessAsset? imageFile,
  }) async {
    _ensureConnected();

    final doc = _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('media')
        .doc(mediaId == null || mediaId.trim().isEmpty ? null : mediaId);
    final isCreate = mediaId == null || mediaId.trim().isEmpty;
    StoredBusinessAsset? uploadedAsset;
    var resolvedImageUrl = imageUrl.trim();
    var resolvedStoragePath = currentStoragePath.trim();

    try {
      if (imageFile != null) {
        uploadedAsset = await _uploadBusinessAsset(
          businessId: businessId,
          scope: 'media',
          docId: doc.id,
          asset: imageFile,
        );
        resolvedImageUrl = uploadedAsset.downloadUrl;
        resolvedStoragePath = uploadedAsset.storagePath;
      } else if (resolvedImageUrl.isEmpty) {
        resolvedStoragePath = '';
      }

      final payload = <String, Object?>{
        'id': doc.id,
        'businessId': businessId,
        'title': title.trim(),
        'caption': caption.trim(),
        'mediaType': mediaType.trim(),
        'imageUrl': resolvedImageUrl,
        'storagePath': resolvedStoragePath,
        'isFeatured': isFeatured,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (isCreate) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }

      await doc.set(payload, SetOptions(merge: true));
    } catch (_) {
      if (uploadedAsset != null) {
        await _deleteStorageObjectQuietly(uploadedAsset.storagePath);
      }
      rethrow;
    }

    if (_shouldDeleteStorageObject(
      businessId: businessId,
      previousPath: currentStoragePath,
      nextPath: resolvedStoragePath,
    )) {
      await _deleteStorageObjectQuietly(currentStoragePath);
    }
  }

  Future<void> deleteMedia({
    required String businessId,
    required String mediaId,
    String storagePath = '',
  }) async {
    _ensureConnected();

    await _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('media')
        .doc(mediaId)
        .delete();

    if (storagePath.trim().isNotEmpty) {
      await _deleteStorageObjectQuietly(storagePath);
    }
  }

  Future<void> _upsertCatalogItem({
    required String businessId,
    required String collectionName,
    String? itemId,
    required String name,
    required String description,
    required String priceLabel,
    required bool isActive,
  }) async {
    _ensureConnected();

    final doc = _firestore
        .collection('businesses')
        .doc(businessId)
        .collection(collectionName)
        .doc(itemId == null || itemId.trim().isEmpty ? null : itemId);
    final isCreate = itemId == null || itemId.trim().isEmpty;
    final payload = <String, Object?>{
      'id': doc.id,
      'businessId': businessId,
      'name': name.trim(),
      'description': description.trim(),
      'priceLabel': priceLabel.trim(),
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (isCreate) {
      payload['createdAt'] = FieldValue.serverTimestamp();
    }

    await doc.set(payload, SetOptions(merge: true));
    await _syncBusinessCounts(businessId);
  }

  Future<void> _deleteCatalogItem({
    required String businessId,
    required String collectionName,
    required String itemId,
  }) async {
    _ensureConnected();

    await _firestore
        .collection('businesses')
        .doc(businessId)
        .collection(collectionName)
        .doc(itemId)
        .delete();
    await _syncBusinessCounts(businessId);
  }

  Future<StoredBusinessAsset> _uploadBusinessAsset({
    required String businessId,
    required String scope,
    required String docId,
    required PickedBusinessAsset asset,
  }) async {
    final ownerUid = FirebaseAuth.instance.currentUser?.uid;
    if (ownerUid == null || ownerUid.isEmpty) {
      throw const OwnerBusinessAdminUnavailable(
        'Owner session is required before uploading business assets.',
      );
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storagePath =
        'owners/$ownerUid/businesses/$businessId/$scope/$docId/$timestamp-${asset.fileName}';
    final ref = _storage.ref(storagePath);

    await ref
        .putData(asset.bytes, SettableMetadata(contentType: asset.contentType))
        .timeout(
          _storageOperationTimeout,
          onTimeout: () => throw const OwnerBusinessAdminUnavailable(
            'Firebase Storage upload timed out. Open Firebase Console > Storage > Get started, then try again.',
          ),
        );
    final downloadUrl = await ref.getDownloadURL().timeout(
      _storageOperationTimeout,
      onTimeout: () => throw const OwnerBusinessAdminUnavailable(
        'Firebase Storage download URL could not be created. Open Firebase Console > Storage > Get started, then try again.',
      ),
    );

    return StoredBusinessAsset(
      downloadUrl: downloadUrl,
      storagePath: storagePath,
    );
  }

  Future<void> _syncBusinessCounts(String businessId) async {
    final counts = await Future.wait([
      _countDocuments(
        _firestore
            .collection('businesses')
            .doc(businessId)
            .collection('locations'),
      ),
      _countDocuments(
        _firestore
            .collection('businesses')
            .doc(businessId)
            .collection('products'),
      ),
      _countDocuments(
        _firestore
            .collection('businesses')
            .doc(businessId)
            .collection('services'),
      ),
    ]);

    await _firestore.doc('businesses/$businessId').update({
      'locationsCount': counts[0],
      'productsCount': counts[1] + counts[2],
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<int> _countDocuments(
    CollectionReference<Map<String, dynamic>> query,
  ) async {
    final snapshot = await query.get();
    return snapshot.docs.length;
  }

  bool _shouldDeleteStorageObject({
    required String businessId,
    required String previousPath,
    required String nextPath,
  }) {
    final trimmedPrevious = previousPath.trim();
    final trimmedNext = nextPath.trim();
    if (trimmedPrevious.isEmpty || trimmedPrevious == trimmedNext) {
      return false;
    }
    final ownerUid = FirebaseAuth.instance.currentUser?.uid;
    final currentOwnerPrefix = ownerUid == null || ownerUid.isEmpty
        ? null
        : 'owners/$ownerUid/businesses/$businessId/';
    return trimmedPrevious.startsWith('businesses/$businessId/') ||
        (currentOwnerPrefix != null &&
            trimmedPrevious.startsWith(currentOwnerPrefix));
  }

  Future<void> _deleteStorageObjectQuietly(String storagePath) async {
    final trimmed = storagePath.trim();
    if (trimmed.isEmpty) {
      return;
    }

    try {
      await _storage.ref(trimmed).delete();
    } on FirebaseException {
      // Best-effort cleanup should never block the owner flow.
    } catch (_) {
      // Keep asset cleanup non-blocking for profile updates.
    }
  }

  void _ensureConnected() {
    if (!isConnected) {
      throw OwnerBusinessAdminUnavailable(_bootstrapResult.message);
    }
  }

  BusinessLocationSummary _mapLocation(
    String docId,
    Map<String, dynamic> data,
  ) {
    return BusinessLocationSummary(
      id: docId,
      name: data['name'] as String? ?? docId,
      address: data['address'] as String? ?? 'Address not set',
      workingHours: data['workingHours'] as String? ?? 'Hours not set',
      phoneNumbers: (data['phoneNumbers'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      notes: data['notes'] as String? ?? '',
      isPrimary: data['isPrimary'] as bool? ?? false,
    );
  }

  BusinessCatalogItemSummary _mapCatalogItem(
    String docId,
    Map<String, dynamic> data,
  ) {
    return BusinessCatalogItemSummary(
      id: docId,
      name: data['name'] as String? ?? docId,
      description: data['description'] as String? ?? 'No description yet.',
      priceLabel: data['priceLabel'] as String? ?? 'Price not set',
      isActive: data['isActive'] as bool? ?? true,
    );
  }

  BusinessMediaSummary _mapMedia(String docId, Map<String, dynamic> data) {
    return BusinessMediaSummary(
      id: docId,
      title: data['title'] as String? ?? docId,
      caption: data['caption'] as String? ?? '',
      mediaType: data['mediaType'] as String? ?? 'gallery',
      imageUrl: data['imageUrl'] as String? ?? '',
      storagePath: data['storagePath'] as String? ?? '',
      isFeatured: data['isFeatured'] as bool? ?? false,
    );
  }
}

class StoredBusinessAsset {
  const StoredBusinessAsset({
    required this.downloadUrl,
    required this.storagePath,
  });

  final String downloadUrl;
  final String storagePath;
}

class JoinableGroupOption {
  const JoinableGroupOption({
    required this.id,
    required this.name,
    required this.activeBusinessCount,
  });

  final String id;
  final String name;
  final int activeBusinessCount;
}

class OwnerBusinessAdminUnavailable implements Exception {
  const OwnerBusinessAdminUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}
