/// Listing domain model.
/// Schema reference: DREZZY_MASTER_PLAN.md §6 — Data Models
///
/// Mirrors the Firestore document at `listings/{listingId}`.
/// All fields marked `// FS` are persisted in Firestore.

class ListingModel {
  final String id;           // FS: document ID
  final String lenderId;     // FS: uid of the lender
  final String title;        // FS: garment name / short description
  final String description;  // FS: full description used for semantic search
  final String category;     // FS: 'dress' | 'shoes' | 'bag' | 'accessory'
  final String brand;        // FS: brand name
  final String size;         // FS: free-form size string (e.g. 'S', 'M', 'EU 38')
  final double pricePerDay;  // FS: GBP
  final double depositAmount;// FS: GBP, held by Stripe during rental
  final List<String> imageUrls;   // FS: anonymised Firebase Storage URLs
  final String coverImageUrl;     // FS: first/hero image
  final List<String> tags;        // FS: ['floral', 'wedding', 'midi', ...]
  final String locationName;      // FS: human-readable city string
  final String status;       // FS: 'active' | 'rented' | 'inactive'
  final DateTime createdAt;  // FS: server timestamp

  const ListingModel({
    required this.id,
    required this.lenderId,
    required this.title,
    required this.description,
    required this.category,
    required this.brand,
    required this.size,
    required this.pricePerDay,
    required this.depositAmount,
    required this.imageUrls,
    required this.coverImageUrl,
    required this.tags,
    required this.locationName,
    required this.status,
    required this.createdAt,
  });

  // ── Firestore deserialization ─────────────────────────────────────────────

  factory ListingModel.fromMap(String id, Map<String, dynamic> map) {
    final images = List<String>.from(map['images'] as List? ?? []);
    return ListingModel(
      id: id,
      lenderId: map['lenderId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      category: map['category'] as String? ?? '',
      brand: map['brand'] as String? ?? '',
      size: map['size'] as String? ?? '',
      pricePerDay: (map['pricePerDay'] as num?)?.toDouble() ?? 0.0,
      depositAmount: (map['depositAmount'] as num?)?.toDouble() ?? 0.0,
      imageUrls: images,
      coverImageUrl: images.isNotEmpty ? images.first : '',
      tags: List<String>.from(map['tags'] as List? ?? []),
      locationName: map['locationName'] as String? ?? '',
      status: map['status'] as String? ?? 'active',
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'].toString())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'lenderId': lenderId,
        'title': title,
        'description': description,
        'category': category,
        'brand': brand,
        'size': size,
        'pricePerDay': pricePerDay,
        'depositAmount': depositAmount,
        'images': imageUrls,
        'tags': tags,
        'locationName': locationName,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
      };

  /// Formatted price string shown on listing cards.
  String get priceLabel => '£${pricePerDay.toStringAsFixed(0)} / day';
}
