import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'supabase_client.dart';

/// A single receipt attached to an expense.
///
/// [storagePath] is the path inside the `receipts` bucket — needed for
/// deletion.  [signedUrl] is a short-lived URL valid for ~1 hour — used
/// for display only; never persist it.
class Receipt {
  const Receipt({
    required this.id,
    required this.storagePath,
    required this.signedUrl,
  });

  final String id;
  final String storagePath;
  final String signedUrl;
}

class ReceiptsRepository {
  ReceiptsRepository(this._client);

  final SupabaseClient _client;

  static const _bucket = 'receipts';

  /// Maximum photos per expense — enforced here before the upload so we
  /// don't reach a state where the file is in Storage but the limit was
  /// exceeded.
  static const maxPerExpense = 5;

  /// Signed URL TTL: 1 hour. Long enough for a detail-screen session;
  /// short enough that a leaked URL is low-value.
  static const _signedUrlTtl = 3600;

  /// Upload [bytes] as a receipt for [expenseId] and record the metadata row.
  ///
  /// Returns the new [Receipt] with a signed URL so the UI can display the
  /// thumbnail immediately without re-fetching.
  Future<Receipt> upload({
    required String expenseId,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    // Pre-flight count check — avoids a partial-upload state where the
    // Storage object exists but the metadata insert would exceed the limit.
    final existing = await _client
        .from('expense_receipts')
        .select('id')
        .eq('expense_id', expenseId);
    if ((existing as List).length >= maxPerExpense) {
      throw Exception(
        'This expense already has $maxPerExpense receipts — the maximum.',
      );
    }

    final ext = _ext(mimeType);
    final filename = '${const Uuid().v4()}.$ext';
    final path = '$expenseId/$filename';

    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );

    // Write the metadata row. created_by is constrained to auth.uid() by RLS
    // so passing the client's current user ID is both correct and enforced.
    final row = await _client
        .from('expense_receipts')
        .insert({
          'expense_id': expenseId,
          'storage_path': path,
          'created_by': _client.auth.currentUser!.id,
        })
        .select()
        .single();

    final signedUrl = await _client.storage
        .from(_bucket)
        .createSignedUrl(path, _signedUrlTtl);

    return Receipt(
      id: row['id'] as String,
      storagePath: path,
      signedUrl: signedUrl,
    );
  }

  /// Fetch all receipts for [expenseId] with fresh signed URLs.
  ///
  /// Returns an empty list when there are none. Skips any receipts whose
  /// signed-URL generation fails (rare, but guards against partial failures
  /// in the batch call leaving the whole list broken).
  Future<List<Receipt>> listForExpense(String expenseId) async {
    final rows = await _client
        .from('expense_receipts')
        .select('id, storage_path')
        .eq('expense_id', expenseId)
        .order('created_at');

    if ((rows as List).isEmpty) return const [];

    final paths = rows.map((r) => r['storage_path'] as String).toList();

    // Batch signed-URL generation — one round trip for all receipts.
    final signed = await _client.storage
        .from(_bucket)
        .createSignedUrls(paths, _signedUrlTtl);

    // createSignedUrls returns results in the same order as [paths].
    final result = <Receipt>[];
    for (var i = 0; i < rows.length && i < signed.length; i++) {
      final url = signed[i].signedUrl;
      if (url == null || url.isEmpty) continue;
      result.add(Receipt(
        id: rows[i]['id'] as String,
        storagePath: paths[i],
        signedUrl: url,
      ));
    }
    return result;
  }

  /// Delete a receipt: removes the Storage object and the metadata row.
  ///
  /// The Storage delete is attempted first; if it fails (e.g. the object was
  /// already removed), we still clean up the metadata row so the UI doesn't
  /// show a phantom thumbnail.
  Future<void> delete(String storagePath) async {
    try {
      await _client.storage.from(_bucket).remove([storagePath]);
    } catch (_) {
      // Object already gone or RLS rejected — proceed to metadata cleanup.
    }

    // RLS-silent-success guard: if the caller isn't the creator, the delete
    // will affect zero rows and we raise rather than silently succeeding.
    final res = await _client
        .from('expense_receipts')
        .delete()
        .eq('storage_path', storagePath)
        .select();
    if (res is! List || res.isEmpty) {
      throw Exception('Could not remove this receipt.');
    }
  }

  String _ext(String mimeType) => switch (mimeType) {
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/heic' => 'heic',
        'image/webp' => 'webp',
        _ => 'jpg',
      };
}

final receiptsRepositoryProvider = Provider<ReceiptsRepository>((ref) {
  return ReceiptsRepository(ref.watch(supabaseClientProvider));
});

/// Receipts for one expense, with signed URLs. Invalidated after upload/delete.
///
/// Watches authStateProvider so the signed-URL cache is dropped on sign-out —
/// a signed URL from the previous session would still work (it's a Supabase
/// token with its own expiry), but showing it to the wrong user feels wrong.
final expenseReceiptsProvider =
    FutureProvider.family<List<Receipt>, String>((ref, expenseId) async {
  ref.watch(authStateProvider);
  return ref.watch(receiptsRepositoryProvider).listForExpense(expenseId);
});
