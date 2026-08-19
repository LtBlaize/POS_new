// lib/core/services/local_db_service.dart
//
// SCHEMA VERSIONS
// v1  — base tables: products, orders, order_items, staff_members,
//        sync_queue, reports_cache
// v2  — credit_customers + credit_transactions
// v3  — cashier_shifts
// v4  — reference_number column on orders
// v5  — device_id column on cashier_shifts
// v6  — void_order_items table
// v7  — business_id column on credit_transactions; credits_paid on shifts
// v8  — barcode index on products
// v9  — parked_orders table
// v10 — product_variants table
// v11 — low_stock_alerts table
// v12 — cost_at_sale column on order_items
// v13 — notes column on order_items; cost_price on product_variants
// v14 — pin_salt column on staff_members
// v15 — variant_id column on order_items
// v16 — tip_amount column on orders
// v17 — local_image_path column on products (local-first product photos)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/cart_item.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/product_variant.dart';
import '../models/staff.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final localDbServiceProvider = Provider<LocalDbService>((ref) {
  return LocalDbService();
});

const _kDbVersion = 18;
const _kDbName = 'pos_offline.db';

// ── Service ───────────────────────────────────────────────────────────────────

class LocalDbService {
  static Database? _db;
  static Future<void> _current = Future.value();

  Future<T> _write<T>(Future<T> Function(Database db) action) async {
    final prev = _current;
    final next = Completer<void>();
    _current = next.future;
    try {
      await prev;
      final d = await db;
      return await action(d);
    } finally {
      next.complete();
    }
  }

  Future<void> markOrderStatus(String orderId, OrderStatus status) =>
      _write((d) async {
        await d.update(
          'orders',
          {'status': status.value},
          where: 'id = ?',
          whereArgs: [orderId],
        );
      });

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  // ── Open / migrate ──────────────────────────────────────────────────────────

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), _kDbName);
    return openDatabase(
      path,
      version: _kDbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        if (!kIsWeb &&
            (Platform.isWindows ||
                Platform.isLinux ||
                Platform.isMacOS)) {
          await db.execute('PRAGMA journal_mode=WAL;');
          await db.execute('PRAGMA busy_timeout=5000;');
        }
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    // ── v1 tables ─────────────────────────────────────────────────────────────

    batch.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        category_id TEXT,
        name TEXT NOT NULL,
        description TEXT,
        price REAL NOT NULL,
        image_url TEXT,
        local_image_path TEXT,
        barcode TEXT,
        sku TEXT,
        track_inventory INTEGER NOT NULL DEFAULT 1,
        stock_quantity INTEGER NOT NULL DEFAULT 0,
        is_available INTEGER NOT NULL DEFAULT 1,
        is_active INTEGER NOT NULL DEFAULT 1,
        category_name TEXT NOT NULL DEFAULT '',
        synced_at TEXT NOT NULL
      )
    ''');

    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode)',
    );

    batch.execute('''
      CREATE TABLE orders (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        table_id TEXT,
        cashier_id TEXT,
        order_number INTEGER NOT NULL,
        order_type TEXT NOT NULL DEFAULT 'walk_in',
        status TEXT NOT NULL DEFAULT 'pending',
        subtotal REAL NOT NULL,
        tax_amount REAL NOT NULL DEFAULT 0,
        discount_amount REAL NOT NULL DEFAULT 0,
        total_amount REAL NOT NULL,
        payment_method TEXT,
        amount_tendered REAL,
        change_amount REAL,
        reference_number TEXT,
        notes TEXT,
        tip_amount REAL NOT NULL DEFAULT 0,
        paid_at TEXT,
        created_at TEXT NOT NULL,
        is_offline INTEGER NOT NULL DEFAULT 0,
        synced_at TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE order_items (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        unit_price REAL NOT NULL,
        cost_at_sale REAL NOT NULL DEFAULT 0,
        quantity INTEGER NOT NULL,
        subtotal REAL NOT NULL,
        notes TEXT,
        variant_id TEXT,
        FOREIGN KEY (order_id) REFERENCES orders(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE staff_members (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        pin_hash TEXT NOT NULL,
        pin_salt TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        synced_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation TEXT NOT NULL,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        retries INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    batch.execute('''
      CREATE TABLE reports_cache (
        date TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        total_sales REAL NOT NULL DEFAULT 0,
        order_count INTEGER NOT NULL DEFAULT 0,
        avg_order_value REAL NOT NULL DEFAULT 0,
        top_products TEXT NOT NULL DEFAULT '[]',
        synced_at TEXT NOT NULL
      )
    ''');

    // ── v2 tables ─────────────────────────────────────────────────────────────

    batch.execute('''
      CREATE TABLE credit_customers (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        total_owed REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE credit_transactions (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        business_id TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        note TEXT,
        order_id TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES credit_customers(id)
      )
    ''');

    // ── v3 tables ─────────────────────────────────────────────────────────────

    batch.execute('''
      CREATE TABLE cashier_shifts (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        staff_id TEXT NOT NULL,
        staff_name TEXT NOT NULL,
        device_id TEXT,
        opening_cash REAL NOT NULL DEFAULT 0,
        opened_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'open',
        closed_at TEXT,
        actual_cash_count REAL,
        notes TEXT,
        total_sales REAL NOT NULL DEFAULT 0,
        cash_sales REAL NOT NULL DEFAULT 0,
        gcash_sales REAL NOT NULL DEFAULT 0,
        other_sales REAL NOT NULL DEFAULT 0,
        credit_given REAL NOT NULL DEFAULT 0,
        credits_paid REAL NOT NULL DEFAULT 0,
        expenses REAL NOT NULL DEFAULT 0
      )
    ''');

    // ── v6 tables ─────────────────────────────────────────────────────────────

    batch.execute('''
      CREATE TABLE void_order_items (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        unit_price REAL NOT NULL,
        quantity INTEGER NOT NULL,
        subtotal REAL NOT NULL,
        reason TEXT NOT NULL,
        voided_by_staff_id TEXT NOT NULL,
        voided_by_staff_name TEXT NOT NULL,
        voided_at TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (order_id) REFERENCES orders(id)
      )
    ''');

    // ── v9 tables ─────────────────────────────────────────────────────────────

    batch.execute('''
      CREATE TABLE parked_orders (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        label TEXT NOT NULL,
        items TEXT NOT NULL,
        order_discount_amount REAL NOT NULL DEFAULT 0,
        order_discount_type TEXT NOT NULL DEFAULT 'fixed',
        tip_amount REAL NOT NULL DEFAULT 0,
        parked_at TEXT NOT NULL
      )
    ''');

    // ── v10 tables ────────────────────────────────────────────────────────────

    batch.execute('''
      CREATE TABLE product_variants (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        name TEXT NOT NULL,
        option_type TEXT,
        price_delta REAL NOT NULL DEFAULT 0,
        sku TEXT,
        barcode TEXT,
        stock_quantity INTEGER NOT NULL DEFAULT 0,
        cost_price REAL NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        synced_at TEXT NOT NULL,
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');

    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_variants_product ON product_variants(product_id)',
    );

    // ── v11 tables ────────────────────────────────────────────────────────────

    batch.execute('''
      CREATE TABLE low_stock_alerts (
        product_id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        stock_quantity INTEGER NOT NULL,
        alerted_at TEXT NOT NULL
      )
    ''');

    await batch.commit(noResult: true);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS credit_customers (
          id TEXT PRIMARY KEY,
          business_id TEXT NOT NULL,
          name TEXT NOT NULL,
          phone TEXT NOT NULL,
          total_owed REAL NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS credit_transactions (
          id TEXT PRIMARY KEY,
          customer_id TEXT NOT NULL,
          business_id TEXT NOT NULL DEFAULT '',
          type TEXT NOT NULL,
          amount REAL NOT NULL,
          note TEXT,
          order_id TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (customer_id) REFERENCES credit_customers(id)
        )
      ''');
    }

    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cashier_shifts (
          id TEXT PRIMARY KEY,
          business_id TEXT NOT NULL,
          staff_id TEXT NOT NULL,
          staff_name TEXT NOT NULL,
          opening_cash REAL NOT NULL DEFAULT 0,
          opened_at TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'open',
          closed_at TEXT,
          actual_cash_count REAL,
          notes TEXT,
          total_sales REAL NOT NULL DEFAULT 0,
          cash_sales REAL NOT NULL DEFAULT 0,
          gcash_sales REAL NOT NULL DEFAULT 0,
          other_sales REAL NOT NULL DEFAULT 0,
          credit_given REAL NOT NULL DEFAULT 0,
          credits_paid REAL NOT NULL DEFAULT 0,
          expenses REAL NOT NULL DEFAULT 0
        )
      ''');
    }

    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE orders ADD COLUMN reference_number TEXT',
      );
    }

    if (oldVersion < 5) {
      await db.execute(
        'ALTER TABLE cashier_shifts ADD COLUMN device_id TEXT',
      );
    }

    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS void_order_items (
          id TEXT PRIMARY KEY,
          order_id TEXT NOT NULL,
          product_id TEXT NOT NULL,
          product_name TEXT NOT NULL,
          unit_price REAL NOT NULL,
          quantity INTEGER NOT NULL,
          subtotal REAL NOT NULL,
          reason TEXT NOT NULL,
          voided_by_staff_id TEXT NOT NULL,
          voided_by_staff_name TEXT NOT NULL,
          voided_at TEXT NOT NULL,
          synced INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (order_id) REFERENCES orders(id)
        )
      ''');
    }

    if (oldVersion < 7) {
      try {
        await db.execute(
          'ALTER TABLE credit_transactions ADD COLUMN business_id TEXT NOT NULL DEFAULT ""',
        );
      } catch (e) {
        debugPrint('[LocalDb] v7: business_id already exists ($e)');
      }
      try {
        await db.execute(
          'ALTER TABLE cashier_shifts ADD COLUMN credits_paid REAL NOT NULL DEFAULT 0',
        );
      } catch (e) {
        debugPrint('[LocalDb] v7: credits_paid already exists ($e)');
      }
    }

    if (oldVersion < 8) {
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode)',
        );
      } catch (e) {
        debugPrint('[LocalDb] v8: barcode index error ($e)');
      }
    }

    if (oldVersion < 9) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS parked_orders (
          id TEXT PRIMARY KEY,
          business_id TEXT NOT NULL,
          label TEXT NOT NULL,
          items TEXT NOT NULL,
          order_discount_amount REAL NOT NULL DEFAULT 0,
          order_discount_type TEXT NOT NULL DEFAULT 'fixed',
          tip_amount REAL NOT NULL DEFAULT 0,
          parked_at TEXT NOT NULL
        )
      ''');
    }

    if (oldVersion < 10) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS product_variants (
          id TEXT PRIMARY KEY,
          product_id TEXT NOT NULL,
          name TEXT NOT NULL,
          option_type TEXT,
          price_delta REAL NOT NULL DEFAULT 0,
          sku TEXT,
          barcode TEXT,
          stock_quantity INTEGER NOT NULL DEFAULT 0,
          is_active INTEGER NOT NULL DEFAULT 1,
          synced_at TEXT NOT NULL,
          FOREIGN KEY (product_id) REFERENCES products(id)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_variants_product ON product_variants(product_id)',
      );
      debugPrint('[LocalDb] v10: product_variants table created');
    }

    if (oldVersion < 11) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS low_stock_alerts (
          product_id TEXT PRIMARY KEY,
          business_id TEXT NOT NULL,
          product_name TEXT NOT NULL,
          stock_quantity INTEGER NOT NULL,
          alerted_at TEXT NOT NULL
        )
      ''');
      debugPrint('[LocalDb] v11: low_stock_alerts table created');
    }

    if (oldVersion < 12) {
      try {
        await db.execute(
          'ALTER TABLE order_items ADD COLUMN cost_at_sale REAL NOT NULL DEFAULT 0',
        );
        debugPrint('[LocalDb] v12: cost_at_sale added to order_items');
      } catch (e) {
        debugPrint('[LocalDb] v12: cost_at_sale already exists ($e)');
      }
    }

    if (oldVersion < 13) {
      try {
        await db.execute(
          'ALTER TABLE order_items ADD COLUMN notes TEXT',
        );
        debugPrint('[LocalDb] v13: notes added to order_items');
      } catch (e) {
        debugPrint('[LocalDb] v13: notes already exists ($e)');
      }
      try {
        await db.execute(
          'ALTER TABLE product_variants ADD COLUMN cost_price REAL NOT NULL DEFAULT 0',
        );
        debugPrint('[LocalDb] v13: cost_price added to product_variants');
      } catch (e) {
        debugPrint('[LocalDb] v13: cost_price already exists ($e)');
      }
    }

    if (oldVersion < 14) {
      try {
        await db.execute(
          'ALTER TABLE staff_members ADD COLUMN pin_salt TEXT',
        );
        debugPrint('[LocalDb] v14: pin_salt added to staff_members');
      } catch (e) {
        debugPrint('[LocalDb] v14: pin_salt already exists ($e)');
      }
    }
    if (oldVersion < 15) {
      try {
        await db.execute(
          'ALTER TABLE order_items ADD COLUMN variant_id TEXT',
        );
        debugPrint('[LocalDb] v15: variant_id added to order_items');
      } catch (e) {
        debugPrint('[LocalDb] v15: variant_id already exists ($e)');
      }
    }

    if (oldVersion < 16) {
      try {
        await db.execute(
          'ALTER TABLE orders ADD COLUMN tip_amount REAL NOT NULL DEFAULT 0',
        );
        debugPrint('[LocalDb] v16: tip_amount added to orders');
      } catch (e) {
        debugPrint('[LocalDb] v16: tip_amount already exists ($e)');
      }
    }

    if (oldVersion < 17) {
      try {
        await db.execute(
          'ALTER TABLE products ADD COLUMN local_image_path TEXT',
        );
        debugPrint('[LocalDb] v17: local_image_path added to products');
      } catch (e) {
        debugPrint('[LocalDb] v17: local_image_path already exists ($e)');
      }
    }

    if (oldVersion < 18) {
      try {
        await db.execute(
          "ALTER TABLE sync_queue ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'",
        );
        debugPrint('[LocalDb] v18: status added to sync_queue');
      } catch (e) {
        debugPrint('[LocalDb] v18: status already exists ($e)');
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // PRODUCTS
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> upsertProducts(List<Product> products) => _write((d) async {
        final batch = d.batch();
        final now = DateTime.now().toIso8601String();
        for (final p in products) {
          // Raw upsert (not a plain replace) so local_image_path survives a
          // cloud sync — Product.fromMap from Supabase never carries it, and
          // a blind replace would wipe the cached photo on every refresh.
          batch.rawInsert('''
            INSERT INTO products (
              id, business_id, category_id, name, description, price,
              image_url, local_image_path, barcode, sku, track_inventory,
              stock_quantity, is_available, is_active, category_name, synced_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              business_id = excluded.business_id,
              category_id = excluded.category_id,
              name = excluded.name,
              description = excluded.description,
              price = excluded.price,
              image_url = excluded.image_url,
              local_image_path = COALESCE(excluded.local_image_path, products.local_image_path),
              barcode = excluded.barcode,
              sku = excluded.sku,
              track_inventory = excluded.track_inventory,
              stock_quantity = excluded.stock_quantity,
              is_available = excluded.is_available,
              is_active = excluded.is_active,
              category_name = excluded.category_name,
              synced_at = excluded.synced_at
          ''', [
            p.id, p.businessId, p.categoryId, p.name, p.description, p.price,
            p.imageUrl, p.localImagePath, p.barcode, p.sku,
            p.trackInventory ? 1 : 0, p.stockQuantity, p.isAvailable ? 1 : 0,
            p.isActive ? 1 : 0, p.category, now,
          ]);
        }
        await batch.commit(noResult: true);
      });

  /// Fetches products and attaches their variants in one call.
  Future<List<Product>> getProducts(String businessId) async {
    final d = await db;
    final rows = await d.query(
      'products',
      where: 'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
      orderBy: 'name',
    );

    final variantRows = await d.query(
      'product_variants',
      where:
          'product_id IN (SELECT id FROM products WHERE business_id = ? AND is_active = 1)',
      whereArgs: [businessId],
    );

    // Group variants by product_id
    final variantMap = <String, List<ProductVariant>>{};
    for (final vr in variantRows) {
      final pid = vr['product_id'] as String;
      variantMap.putIfAbsent(pid, () => []);
      variantMap[pid]!.add(ProductVariant.fromLocalRow(vr));
    }

    return rows.map((row) {
      final product = _productFromRow(row);
      final variants = variantMap[product.id] ?? [];
      return product.copyWith(variants: variants);
    }).toList();
  }

  Future<void> updateProductStock(String productId, int newStock) async {
    final d = await db;
    await d.update(
      'products',
      {
        'stock_quantity': newStock,
        'is_available': newStock > 0 ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<Product?> findByBarcode(String barcode, String businessId) async {
    final d = await db;
    final rows = await d.query(
      'products',
      where: 'barcode = ? AND business_id = ? AND is_active = 1',
      whereArgs: [barcode, businessId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _productFromRow(rows.first);
  }

  Future<void> updateProductAvailability(
      String productId, bool isAvailable) async {
    final d = await db;
    await d.update(
      'products',
      {'is_available': isAvailable ? 1 : 0},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  /// Sets the local cached file path right after a capture is compressed
  /// and saved to disk. Pass null to clear it (photo removed).
  Future<void> updateProductLocalImage(
      String productId, String? localImagePath) async {
    final d = await db;
    await d.update(
      'products',
      {'local_image_path': localImagePath},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  /// Sets the cloud image_url once a queued upload completes.
  Future<void> updateProductImageUrl(
      String productId, String imageUrl) async {
    final d = await db;
    await d.update(
      'products',
      {'image_url': imageUrl},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Product _productFromRow(Map<String, dynamic> row) => Product(
        id: row['id'] as String,
        businessId: row['business_id'] as String,
        categoryId: row['category_id'] as String?,
        name: row['name'] as String,
        description: row['description'] as String?,
        price: (row['price'] as num).toDouble(),
        imageUrl: row['image_url'] as String?,
        localImagePath: row['local_image_path'] as String?,
        barcode: row['barcode'] as String?,
        sku: row['sku'] as String?,
        trackInventory: (row['track_inventory'] as int) == 1,
        stockQuantity: row['stock_quantity'] as int,
        isAvailable: (row['is_available'] as int) == 1,
        isActive: (row['is_active'] as int) == 1,
        category: row['category_name'] as String? ?? '',
        // variants attached by caller
      );

  // ─────────────────────────────────────────────────────────────────────────────
  // PRODUCT VARIANTS
  // ─────────────────────────────────────────────────────────────────────────────

  /// Replaces all variants for a product — used after a Supabase fetch.
  Future<void> upsertVariants(
          String productId, List<ProductVariant> variants) =>
      _write((d) async {
        final now = DateTime.now().toIso8601String();
        await d.transaction((txn) async {
          // Remove stale variants no longer returned by server
          await txn.delete(
            'product_variants',
            where: 'product_id = ?',
            whereArgs: [productId],
          );
          for (final v in variants) {
            await txn.insert(
              'product_variants',
              {
                'id': v.id,
                'product_id': v.productId,
                'name': v.name,
                'option_type': v.optionType,
                'price_delta': v.priceDelta,
                'sku': v.sku,
                'barcode': v.barcode,
                'stock_quantity': v.stockQuantity,
                'cost_price': v.costPrice,
                'is_active': v.isActive ? 1 : 0,
                'synced_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        });
      });

  /// Bulk upsert — used when syncing all variants for a business at once.
  Future<void> upsertAllVariants(List<ProductVariant> variants) =>
      _write((d) async {
        final now = DateTime.now().toIso8601String();
        final batch = d.batch();
        for (final v in variants) {
          batch.insert(
            'product_variants',
            {
              'id': v.id,
              'product_id': v.productId,
              'name': v.name,
              'option_type': v.optionType,
              'price_delta': v.priceDelta,
              'sku': v.sku,
              'barcode': v.barcode,
              'stock_quantity': v.stockQuantity,
              'cost_price': v.costPrice,
              'is_active': v.isActive ? 1 : 0,
              'synced_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });

  Future<List<ProductVariant>> getVariantsForProduct(
      String productId) async {
    final d = await db;
    final rows = await d.query(
      'product_variants',
      where: 'product_id = ? AND is_active = 1',
      whereArgs: [productId],
      orderBy: 'name',
    );
    return rows.map(ProductVariant.fromLocalRow).toList();
  }

  Future<void> updateVariantStock(String variantId, int newStock) =>
      _write((d) async {
        await d.update(
          'product_variants',
          {'stock_quantity': newStock},
          where: 'id = ?',
          whereArgs: [variantId],
        );
      });

  Future<void> deactivateVariant(String variantId) => _write((d) async {
        await d.update(
          'product_variants',
          {'is_active': 0},
          where: 'id = ?',
          whereArgs: [variantId],
        );
      });

  // ─────────────────────────────────────────────────────────────────────────────
  // ORDERS
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> insertOfflineOrder(Order order) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.insert(
        'orders',
        {
          'id': order.id,
          'business_id': order.businessId,
          'table_id': order.tableId,
          'cashier_id': order.cashierId,
          'order_number': order.orderNumber,
          'order_type': order.orderType.value,
          'status': order.status.value,
          'subtotal': order.subtotal,
          'tax_amount': order.taxAmount,
          'discount_amount': order.discountAmount,
          'total_amount': order.totalAmount,
          'payment_method': order.paymentMethod?.value,
          'amount_tendered': order.amountTendered,
          'change_amount': order.changeAmount,
          'reference_number': order.referenceNumber,
          'notes': order.notes,
          'tip_amount': order.tipAmount,
          'paid_at': order.paidAt?.toIso8601String(),
          'created_at': order.createdAt.toIso8601String(),
          'is_offline': 1,
          'synced_at': null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      for (int i = 0; i < order.items.length; i++) {
        final item = order.items[i];
        await txn.insert(
          'order_items',
          {
            'id': '${order.id}_${item.product.id}_$i',
            'order_id': order.id,
            'product_id': item.product.id,
            'product_name': item.product.name,
            'unit_price': item.product.price,
            'cost_at_sale': item.costAtSale,
            'quantity': item.quantity,
            'subtotal': item.total,
            'notes': item.notes,
            'variant_id': item.selectedVariant?.id,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  // (removed — replaced by markQueueDead below; dead entries are now kept
  // and surfaced instead of silently deleted)

  Future<void> upsertOrders(List<Order> orders) => _write((d) async {
        final now = DateTime.now().toIso8601String();
        await d.transaction((txn) async {
          for (final order in orders) {
            await txn.insert(
              'orders',
              {
                'id': order.id,
                'business_id': order.businessId,
                'table_id': order.tableId,
                'cashier_id': order.cashierId,
                'order_number': order.orderNumber,
                'order_type': order.orderType.value,
                'status': order.status.value,
                'subtotal': order.subtotal,
                'tax_amount': order.taxAmount,
                'discount_amount': order.discountAmount,
                'total_amount': order.totalAmount,
                'payment_method': order.paymentMethod?.value,
                'amount_tendered': order.amountTendered,
                'change_amount': order.changeAmount,
                'reference_number': order.referenceNumber,
                'notes': order.notes,
                'tip_amount': order.tipAmount,
                'paid_at': order.paidAt?.toIso8601String(),
                'created_at': order.createdAt.toIso8601String(),
                'is_offline': 0,
                'synced_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );

            await txn.delete(
              'order_items',
              where: 'order_id = ?',
              whereArgs: [order.id],
            );
            for (int i = 0; i < order.items.length; i++) {
              final item = order.items[i];
              await txn.insert(
                'order_items',
                {
                  'id': '${order.id}_${item.product.id}_$i',
                  'order_id': order.id,
                  'product_id': item.product.id,
                  'product_name': item.product.name,
                  'unit_price': item.product.price,
                  'cost_at_sale': item.costAtSale,
                  'quantity': item.quantity,
                  'subtotal': item.total,
                  'notes': item.notes,
                  'variant_id': item.selectedVariant?.id,
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
        });
      });

  Future<void> updateOrderPayment({
    required String orderId,
    required PaymentMethod method,
    required double amountTendered,
    required double changeAmount,
    String? referenceNumber,
  }) =>
      _write((d) async {
        await d.update(
          'orders',
          {
            'payment_method': method.value,
            'amount_tendered': amountTendered,
            'change_amount': changeAmount,
            'reference_number': referenceNumber,
            'paid_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [orderId],
        );
      });

  /// Deletes locally cached orders for [businessId] that are no longer in
  /// [keepIds] — used by the kitchen device to mirror the server's active-
  /// order snapshot so stale (completed/cancelled) orders don't resurface
  /// after a reboot.
  Future<void> pruneKitchenOrders(
      String businessId, List<String> keepIds) => _write((d) async {
        if (keepIds.isEmpty) {
          await d.delete(
            'order_items',
            where: 'order_id IN (SELECT id FROM orders WHERE business_id = ?)',
            whereArgs: [businessId],
          );
          await d.delete('orders', where: 'business_id = ?', whereArgs: [businessId]);
          return;
        }
        final placeholders = List.filled(keepIds.length, '?').join(',');
        await d.delete(
          'order_items',
          where:
              'order_id IN (SELECT id FROM orders WHERE business_id = ? AND id NOT IN ($placeholders))',
          whereArgs: [businessId, ...keepIds],
        );
        await d.delete(
          'orders',
          where: 'business_id = ? AND id NOT IN ($placeholders)',
          whereArgs: [businessId, ...keepIds],
        );
      });

  Future<List<Order>> getOrders(String businessId) async {
    final d = await db;
    final orderRows = await d.query(
      'orders',
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'created_at DESC',
    );

    return Future.wait(orderRows.map((row) async {
      final items = await _getOrderItems(d, row['id'] as String);
      return _orderFromRow(row, items);
    }));
  }

  Future<List<Order>> getPendingOfflineOrders() async {
    final d = await db;
    final rows = await d.query(
      'orders',
      where: 'is_offline = 1 AND synced_at IS NULL',
      orderBy: 'created_at ASC',
    );
    return Future.wait(rows.map((row) async {
      final items = await _getOrderItems(d, row['id'] as String);
      return _orderFromRow(row, items);
    }));
  }

  Future<void> markOrderSynced(String orderId) async {
    final d = await db;
    await d.update(
      'orders',
      {'is_offline': 0, 'synced_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  Future<List<CartItem>> _getOrderItems(Database d, String orderId) async {
    final rows = await d.query(
      'order_items',
      where: 'order_id = ?',
      whereArgs: [orderId],
    );
    return rows.map((r) {
      final product = Product(
        id: r['product_id'] as String,
        businessId: '',
        name: r['product_name'] as String,
        price: (r['unit_price'] as num).toDouble(),
      );
      final variantId = r['variant_id'] as String?;
      final selectedVariant = variantId != null
          ? ProductVariant(
              id: variantId,
              productId: r['product_id'] as String,
              name: '',
            )
          : null;
      return CartItem(
        product: product,
        quantity: r['quantity'] as int,
        costAtSale: (r['cost_at_sale'] as num?)?.toDouble() ?? 0,
        notes: r['notes'] as String?,
        selectedVariant: selectedVariant,
      );
    }).toList();
  }

  Order _orderFromRow(Map<String, dynamic> row, List<CartItem> items) =>
      Order(
        id: row['id'] as String,
        businessId: row['business_id'] as String,
        tableId: row['table_id'] as String?,
        cashierId: row['cashier_id'] as String?,
        orderNumber: row['order_number'] as int,
        orderType: OrderTypeX.fromString(row['order_type'] as String),
        status: OrderStatusX.fromString(row['status'] as String),
        subtotal: (row['subtotal'] as num).toDouble(),
        taxAmount: (row['tax_amount'] as num).toDouble(),
        discountAmount: (row['discount_amount'] as num).toDouble(),
        tipAmount: (row['tip_amount'] as num?)?.toDouble() ?? 0.0,
        totalAmount: (row['total_amount'] as num).toDouble(),
        paymentMethod: row['payment_method'] != null
            ? PaymentMethodX.fromString(row['payment_method'] as String)
            : null,
        amountTendered: (row['amount_tendered'] as num?)?.toDouble(),
        changeAmount: (row['change_amount'] as num?)?.toDouble(),
        referenceNumber: row['reference_number'] as String?,
        notes: row['notes'] as String?,
        paidAt: row['paid_at'] != null
            ? DateTime.parse(row['paid_at'] as String)
            : null,
        createdAt: DateTime.parse(row['created_at'] as String),
        items: items,
      );

  // ─────────────────────────────────────────────────────────────────────────────
  // VOID ITEMS
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> voidOrderItem({
    required String voidId,
    required String orderId,
    required String productId,
    required String productName,
    required double unitPrice,
    required int quantity,
    required double subtotal,
    required String reason,
    required String voidedByStaffId,
    required String voidedByStaffName,
  }) =>
      _write((d) async {
        final now = DateTime.now().toIso8601String();

        await d.transaction((txn) async {
          await txn.insert(
            'void_order_items',
            {
              'id': voidId,
              'order_id': orderId,
              'product_id': productId,
              'product_name': productName,
              'unit_price': unitPrice,
              'quantity': quantity,
              'subtotal': subtotal,
              'reason': reason,
              'voided_by_staff_id': voidedByStaffId,
              'voided_by_staff_name': voidedByStaffName,
              'voided_at': now,
              'synced': 0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          await txn.delete(
            'order_items',
            where: 'order_id = ? AND product_id = ?',
            whereArgs: [orderId, productId],
          );

          final remaining = await txn.query(
            'order_items',
            where: 'order_id = ?',
            whereArgs: [orderId],
          );

          if (remaining.isEmpty) {
            await txn.update(
              'orders',
              {'status': 'cancelled'},
              where: 'id = ?',
              whereArgs: [orderId],
            );
          } else {
            final newSubtotal = remaining.fold<double>(
              0,
              (s, r) => s + (r['subtotal'] as num).toDouble(),
            );

            final orderRows = await txn.query(
              'orders',
              where: 'id = ?',
              whereArgs: [orderId],
            );
            final existingTax =
                (orderRows.first['tax_amount'] as num).toDouble();
            final existingDiscount =
                (orderRows.first['discount_amount'] as num).toDouble();
            final oldSubtotal =
                (orderRows.first['subtotal'] as num).toDouble();

            final taxRate =
                oldSubtotal > 0 ? existingTax / oldSubtotal : 0.0;
            final newTax = newSubtotal * taxRate;
            final newDiscount =
                existingDiscount.clamp(0.0, newSubtotal);
            final newTotal = newSubtotal + newTax - newDiscount;

            await txn.update(
              'orders',
              {
                'subtotal': newSubtotal,
                'tax_amount': newTax,
                'discount_amount': newDiscount,
                'total_amount': newTotal,
              },
              where: 'id = ?',
              whereArgs: [orderId],
            );
          }
        });
      });

  Future<List<Map<String, dynamic>>> getVoidedItemsForOrder(
      String orderId) async {
    final d = await db;
    return d.query(
      'void_order_items',
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'voided_at DESC',
    );
  }

  Future<void> markVoidSynced(String voidId) => _write((d) async {
        await d.update(
          'void_order_items',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [voidId],
        );
      });

  Future<List<Map<String, dynamic>>> getUnsyncedVoids() async {
    final d = await db;
    return d.query(
      'void_order_items',
      where: 'synced = 0',
      orderBy: 'voided_at ASC',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // CREDIT TRANSACTIONS
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> insertCreditTransaction({
    required String id,
    required String customerId,
    required String businessId,
    required String type,
    required double amount,
    String? note,
    String? orderId,
    required String createdAt,
  }) =>
      _write((d) async {
        await d.insert(
          'credit_transactions',
          {
            'id': id,
            'customer_id': customerId,
            'business_id': businessId,
            'type': type,
            'amount': amount,
            'note': note,
            'order_id': orderId,
            'created_at': createdAt,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

  Future<void> updateCreditCustomerOwed({
    required String customerId,
    required double delta,
  }) =>
      _write((d) async {
        await d.rawUpdate(
          'UPDATE credit_customers '
          'SET total_owed = MAX(0, total_owed + ?), '
          '    updated_at = ? '
          'WHERE id = ?',
          [delta, DateTime.now().toIso8601String(), customerId],
        );
      });

  // ─────────────────────────────────────────────────────────────────────────────
  // STAFF
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> upsertStaff(List<StaffMember> members) => _write((d) async {
        final batch = d.batch();
        final now = DateTime.now().toIso8601String();
        for (final m in members) {
          batch.insert(
            'staff_members',
            {
              'id': m.id,
              'business_id': m.businessId,
              'name': m.name,
              'role': m.role.value,
              'pin_hash': m.pinHash,
              'pin_salt': m.pinSalt,
              'is_active': m.isActive ? 1 : 0,
              'synced_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });

  Future<List<StaffMember>> getStaff(String businessId) async {
    final d = await db;
    final rows = await d.query(
      'staff_members',
      where: 'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
    );
    return rows
        .map((r) => StaffMember(
              id: r['id'] as String,
              businessId: r['business_id'] as String,
              name: r['name'] as String,
              role: StaffRole.values.firstWhere(
                (e) => e.value == r['role'],
                orElse: () => StaffRole.cashier,
              ),
              pinHash: r['pin_hash'] as String,
              pinSalt: r['pin_salt'] as String?,
              isActive: (r['is_active'] as int) == 1,
            ))
        .toList();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // SYNC QUEUE
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> enqueue({
    required String operation,
    required String tableName,
    required String recordId,
    required Map<String, dynamic> payload,
  }) async {
    final d = await db;
    await d.insert('sync_queue', {
      'operation': operation,
      'table_name': tableName,
      'record_id': recordId,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
      'retries': 0,
      'status': 'pending',
    });
  }

  /// Only entries still being actively retried. Dead-lettered entries
  /// (status = 'failed') are excluded so they stop being replayed forever.
  Future<List<Map<String, dynamic>>> getPendingQueue() async {
    final d = await db;
    return d.query('sync_queue',
        where: "status = 'pending'", orderBy: 'id ASC');
  }

  Future<void> dequeue(int queueId) async {
    final d = await db;
    await d.delete('sync_queue', where: 'id = ?', whereArgs: [queueId]);
  }

  Future<void> incrementRetry(int queueId, String error) async {
    final d = await db;
    await d.rawUpdate(
      'UPDATE sync_queue SET retries = retries + 1, last_error = ? WHERE id = ?',
      [error, queueId],
    );
  }

  /// Moves an entry from 'pending' to 'failed' instead of deleting it —
  /// keeps the row (and its payload/error) visible in Settings.
  Future<void> markQueueDead(int queueId) async {
    final d = await db;
    await d.update(
      'sync_queue',
      {'status': 'failed'},
      where: 'id = ?',
      whereArgs: [queueId],
    );
  }

  /// Dead-lettered entries — surfaced in Settings so a failed payment/order
  /// sync doesn't vanish silently.
  Future<List<Map<String, dynamic>>> getFailedQueue() async {
    final d = await db;
    return d.query('sync_queue',
        where: "status = 'failed'", orderBy: 'id DESC');
  }

  /// Re-queues a dead-lettered entry for another attempt (e.g. user tapped
  /// "Retry" in Settings after fixing whatever caused it to fail).
  Future<void> retryQueueEntry(int queueId) async {
    final d = await db;
    await d.update(
      'sync_queue',
      {'status': 'pending', 'retries': 0},
      where: 'id = ?',
      whereArgs: [queueId],
    );
  }

  Future<int> failedQueueCount() async {
    final d = await db;
    final result = await d.rawQuery(
        "SELECT COUNT(*) as c FROM sync_queue WHERE status = 'failed'");
    return (result.first['c'] as int?) ?? 0;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // REPORTS CACHE
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> upsertReportDay({
    required String date,
    required String businessId,
    required double totalSales,
    required int orderCount,
    required double avgOrderValue,
    required List<Map<String, dynamic>> topProducts,
  }) async {
    final d = await db;
    await d.insert(
      'reports_cache',
      {
        'date': date,
        'business_id': businessId,
        'total_sales': totalSales,
        'order_count': orderCount,
        'avg_order_value': avgOrderValue,
        'top_products': jsonEncode(topProducts),
        'synced_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getReports(
    String businessId, {
    String? fromDate,
    String? toDate,
  }) async {
    final d = await db;
    String where = 'business_id = ?';
    final args = <dynamic>[businessId];
    if (fromDate != null) {
      where += ' AND date >= ?';
      args.add(fromDate);
    }
    if (toDate != null) {
      where += ' AND date <= ?';
      args.add(toDate);
    }
    final rows = await d.query(
      'reports_cache',
      where: where,
      whereArgs: args,
      orderBy: 'date DESC',
    );
    return rows
        .map((r) => {
              ...r,
              'top_products': jsonDecode(r['top_products'] as String),
            })
        .toList();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // UTILITIES
  // ─────────────────────────────────────────────────────────────────────────────

  Future<int> pendingQueueCount() async {
    final d = await db;
    final result = await d.rawQuery(
        "SELECT COUNT(*) as c FROM sync_queue WHERE status = 'pending'");
    return (result.first['c'] as int?) ?? 0;
  }

  Future<void> clearStaleData(String businessId) async {
    final d = await db;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 30))
        .toIso8601String();

    await d.rawDelete('''
      DELETE FROM order_items
      WHERE order_id IN (
        SELECT id FROM orders
        WHERE business_id = ?
          AND created_at < ?
          AND is_offline = 0
      )
    ''', [businessId, cutoff]);

    await d.delete(
      'orders',
      where: 'business_id = ? AND created_at < ? AND is_offline = 0',
      whereArgs: [businessId, cutoff],
    );

    await d.delete(
      'reports_cache',
      where: 'business_id = ? AND date < ?',
      whereArgs: [
        businessId,
        DateTime.now()
            .subtract(const Duration(days: 90))
            .toIso8601String()
            .substring(0, 10),
      ],
    );

    debugPrint('[LocalDb] Pruned stale data older than 30 days');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // PARKED ORDERS
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> insertParkedOrder(Map<String, dynamic> map) =>
      _write((d) async {
        await d.insert(
          'parked_orders',
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

  Future<List<Map<String, dynamic>>> getParkedOrders() async {
    final d = await db;
    return d.query('parked_orders', orderBy: 'parked_at ASC');
  }

  Future<void> deleteParkedOrder(String id) => _write((d) async {
        await d.delete(
          'parked_orders',
          where: 'id = ?',
          whereArgs: [id],
        );
      });

  // ─────────────────────────────────────────────────────────────────────────────
  // LOW STOCK ALERTS
  // ─────────────────────────────────────────────────────────────────────────────

  /// Returns product IDs that have already been alerted recently (within 24h).
  Future<Set<String>> getRecentlyAlertedProductIds(String businessId) async {
    final d = await db;
    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 24))
        .toIso8601String();
    final rows = await d.query(
      'low_stock_alerts',
      columns: ['product_id'],
      where: 'business_id = ? AND alerted_at > ?',
      whereArgs: [businessId, cutoff],
    );
    return rows.map((r) => r['product_id'] as String).toSet();
  }

  /// Marks a product as alerted. Call this after firing the notification.
  Future<void> markLowStockAlerted({
    required String productId,
    required String businessId,
    required String productName,
    required int stockQuantity,
  }) =>
      _write((d) async {
        await d.insert(
          'low_stock_alerts',
          {
            'product_id': productId,
            'business_id': businessId,
            'product_name': productName,
            'stock_quantity': stockQuantity,
            'alerted_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

  /// Clears stale alert records older than 24h — call on app start.
  Future<void> pruneStaleAlerts() async {
    final d = await db;
    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 24))
        .toIso8601String();
    await d.delete(
      'low_stock_alerts',
      where: 'alerted_at < ?',
      whereArgs: [cutoff],
    );
  }
}