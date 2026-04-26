// lib/core/services/local_db_service.dart

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
import '../models/staff.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final localDbServiceProvider = Provider<LocalDbService>((ref) {
  return LocalDbService();
});

// ── Database schema version ───────────────────────────────────────────────────

const _kDbVersion = 3;
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
        notes TEXT,
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
        quantity INTEGER NOT NULL,
        subtotal REAL NOT NULL,
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
        last_error TEXT
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
        expenses REAL NOT NULL DEFAULT 0
      )
    ''');

    await batch.commit(noResult: true);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Each block is additive — a fresh install at v1 upgrading to v3
    // will run all blocks in sequence.

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
          expenses REAL NOT NULL DEFAULT 0
        )
      ''');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // PRODUCTS
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> upsertProducts(List<Product> products) async {
    final d = await db;
    final batch = d.batch();
    final now = DateTime.now().toIso8601String();
    for (final p in products) {
      batch.insert(
        'products',
        {
          'id': p.id,
          'business_id': p.businessId,
          'category_id': p.categoryId,
          'name': p.name,
          'description': p.description,
          'price': p.price,
          'image_url': p.imageUrl,
          'barcode': p.barcode,
          'sku': p.sku,
          'track_inventory': p.trackInventory ? 1 : 0,
          'stock_quantity': p.stockQuantity,
          'is_available': p.isAvailable ? 1 : 0,
          'is_active': p.isActive ? 1 : 0,
          'category_name': p.category,
          'synced_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Product>> getProducts(String businessId) async {
    final d = await db;
    final rows = await d.query(
      'products',
      where: 'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
      orderBy: 'name',
    );
    return rows.map(_productFromRow).toList();
  }

  Future<void> updateProductStock(String productId, int newStock) async {
    final d = await db;
    await d.update(
      'products',
      {'stock_quantity': newStock},
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
        barcode: row['barcode'] as String?,
        sku: row['sku'] as String?,
        trackInventory: (row['track_inventory'] as int) == 1,
        stockQuantity: row['stock_quantity'] as int,
        isAvailable: (row['is_available'] as int) == 1,
        isActive: (row['is_active'] as int) == 1,
        category: row['category_name'] as String? ?? '',
      );

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
          'notes': order.notes,
          'paid_at': order.paidAt?.toIso8601String(),
          'created_at': order.createdAt.toIso8601String(),
          'is_offline': 1,
          'synced_at': null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      for (final item in order.items) {
        await txn.insert(
          'order_items',
          {
            'id': '${order.id}_${item.product.id}',
            'order_id': order.id,
            'product_id': item.product.id,
            'product_name': item.product.name,
            'unit_price': item.product.price,
            'quantity': item.quantity,
            'subtotal': item.total,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> upsertOrders(List<Order> orders) async {
    final d = await db;
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
            'notes': order.notes,
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
        for (final item in order.items) {
          await txn.insert(
            'order_items',
            {
              'id': '${order.id}_${item.product.id}',
              'order_id': order.id,
              'product_id': item.product.id,
              'product_name': item.product.name,
              'unit_price': item.product.price,
              'quantity': item.quantity,
              'subtotal': item.total,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

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
      return CartItem(product: product, quantity: r['quantity'] as int);
    }).toList();
  }

  Order _orderFromRow(Map<String, dynamic> row, List<CartItem> items) => Order(
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
        totalAmount: (row['total_amount'] as num).toDouble(),
        paymentMethod: row['payment_method'] != null
            ? PaymentMethodX.fromString(row['payment_method'] as String)
            : null,
        amountTendered: (row['amount_tendered'] as num?)?.toDouble(),
        changeAmount: (row['change_amount'] as num?)?.toDouble(),
        notes: row['notes'] as String?,
        paidAt: row['paid_at'] != null
            ? DateTime.parse(row['paid_at'] as String)
            : null,
        createdAt: DateTime.parse(row['created_at'] as String),
        items: items,
      );

  // ─────────────────────────────────────────────────────────────────────────────
  // STAFF
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> upsertStaff(List<StaffMember> members) async {
    final d = await db;
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
          'is_active': m.isActive ? 1 : 0,
          'synced_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

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
    });
  }

  Future<List<Map<String, dynamic>>> getPendingQueue() async {
    final d = await db;
    return d.query('sync_queue', orderBy: 'id ASC');
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
    return rows.map((r) => {
          ...r,
          'top_products': jsonDecode(r['top_products'] as String),
        }).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // UTILITIES
  // ─────────────────────────────────────────────────────────────────────────────

  Future<int> pendingQueueCount() async {
    final d = await db;
    final result = await d.rawQuery('SELECT COUNT(*) as c FROM sync_queue');
    return (result.first['c'] as int?) ?? 0;
  }

  Future<void> clearStaleData(String businessId) async {
    final d = await db;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 30))
        .toIso8601String();
    await d.delete(
      'orders',
      where: 'business_id = ? AND created_at < ? AND is_offline = 0',
      whereArgs: [businessId, cutoff],
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}