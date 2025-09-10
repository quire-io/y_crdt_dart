// import {
//   Doc,
//   AbstractUpdateDecoder,
//   AbstractUpdateEncoder,
//   StructStore,
//   Transaction,
//   Item, // eslint-disable-line
// } from "../internals.js";

// import * as error from "lib0/error.js";

import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/utils/doc.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';

class Opts {
  bool? gc;
  bool? autoLoad, shouldLoad;
  dynamic meta;

  Map<String, dynamic> toMap() {
    return {
      "gc": gc,
      "autoLoad": autoLoad,
      "meta": meta,
      "shouldLoad": shouldLoad,
    };
  }
}

/**
 * @param {string} guid
 * @param {Object<string, any>} opts
 */
Doc createDocFromOpts(String guid, Opts opts) 
  => Doc(guid: guid, gc: opts.gc ?? true, 
      autoLoad: opts.autoLoad ?? false, meta: opts.meta,
      shouldLoad: (opts.shouldLoad ?? false) || (opts.autoLoad ?? false) || false );

/**
 * @private
 */
class ContentDoc implements AbstractContent {
  /**
   * @param {Doc} doc
   */
  ContentDoc(this.doc) {
    final doc = this.doc;
    if (doc != null) {
      if (doc.item != null) {
        // logger.e("This document was already integrated as a sub-document. "
        //     "You should create a second instance instead with the same guid.");
      }
      if (!doc.gc) {
        opts.gc = false;
      }
      if (doc.autoLoad) {
        opts.autoLoad = true;
      }
      if (doc.meta != null) {
        opts.meta = doc.meta;
      }
    }
  }
  /**
     * @type {Doc}
     */
  Doc? doc;
  /**
     * @type {any}
     */

  Opts opts = Opts();

  /**
   * @return {number}
   */
  @override
  getLength() {
    return 1;
  }

  /**
   * @return {List<any>}
   */
  @override
  getContent() {
    return [this.doc];
  }

  /**
   * @return {boolean}
   */
  @override
  isCountable() {
    return true;
  }

  /**
   * @return {ContentDoc}
   */
  @override
  copy() {
    return ContentDoc(createDocFromOpts(this.doc!.guid, this.opts));
  }

  /**
   * @param {number} offset
   * @return {ContentDoc}
   */
  @override
  splice(offset) {
    throw UnimplementedError();
  }

  /**
   * @param {ContentDoc} right
   * @return {boolean}
   */
  @override
  mergeWith(right) {
    return false;
  }

  /**
   * @param {Transaction} transaction
   * @param {Item} item
   */
  @override
  integrate(transaction, item) {
    // this needs to be reflected in doc.destroy as well
    final doc = this.doc;
    if (doc != null) {
      doc.item = item;
      transaction.subdocsAdded.add(doc);
      if (doc.shouldLoad) {
        transaction.subdocsLoaded.add(doc);
      }
    }
  }

  /**
   * @param {Transaction} transaction
   */
  @override
  delete(transaction) {
    if (transaction.subdocsAdded.contains(this.doc)) {
      transaction.subdocsAdded.remove(this.doc);
    } else {
      transaction.subdocsRemoved.add(this.doc!);
    }
  }

  /**
   * @param {StructStore} store
   */
  @override
  gc(store) {}

  /**
   * @param {AbstractUpdateEncoder} encoder
   * @param {number} offset
   */
  @override
  write(encoder, offset) {
    encoder.writeString(this.doc!.guid);
    encoder.writeAny(this.opts.toMap());
  }

  /**
   * @return {number}
   */
  @override
  getRef() {
    return 9;
  }
}

/**
 * @private
 *
 * @param {AbstractUpdateDecoder} decoder
 * @return {ContentDoc}
 */
ContentDoc readContentDoc(AbstractUpdateDecoder decoder) {
  final guid = decoder.readString();
  final params = decoder.readAny();
  // return ContentDoc(createDocFromOpts(decoder.readString(), decoder.readAny()));
  return ContentDoc(
    Doc(
      guid: guid,
      autoLoad: params["autoLoad"] as bool? ?? false,
      gc: params["gc"] as bool? ?? true,
      gcFilter:
          (params["gcFilter"] ?? Doc.defaultGcFilter) as bool Function(Item),
      meta: params["meta"],
    ),
  );
}
