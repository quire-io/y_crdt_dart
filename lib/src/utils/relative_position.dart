// import {
//   writeID,
//   readID,
//   compareIDs,
//   getState,
//   findRootTypeKey,
//   Item,
//   createID,
//   ContentType,
//   followRedone,
//   ID,
//   Doc,
//   AbstractType, // eslint-disable-line
// } from "../internals.js";

// import * as encoding from "lib0/encoding.js";
// import * as decoding from "lib0/decoding.js";
// import * as error from "lib0/error.js";

import 'dart:typed_data';

import 'package:y_crdt/src/lib0/decoding.dart' as decoding;
import 'package:y_crdt/src/lib0/encoding.dart' as encoding;
import 'package:y_crdt/src/structs/content_type.dart';
import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/types/abstract_type.dart';
import 'package:y_crdt/src/utils/doc.dart';
import 'package:y_crdt/src/utils/id.dart';
import 'package:y_crdt/src/utils/struct_store.dart';

/**
 * A relative position is based on the Yjs model and is not affected by document changes.
 * E.g. If you place a relative position before a certain character, it will always point to this character.
 * If you place a relative position at the end of a type, it will always point to the end of the type.
 *
 * A numeric position is often unsuited for user selections, because it does not change when content is inserted
 * before or after.
 *
 * Insert(0, 'x')('a|bc') = 'xa|bc' Where | is the relative position.
 *
 * One of the properties must be defined.
 *
 * @example
 *   // Current cursor position is at position 10
 *   const relativePosition = createRelativePositionFromIndex(yText, 10)
 *   // modify yText
 *   yText.insert(0, 'abc')
 *   yText.delete(3, 10)
 *   // Compute the cursor position
 *   const absolutePosition = createAbsolutePositionFromRelativePosition(y, relativePosition)
 *   absolutePosition.type == yText // => true
 *   console.log('cursor location is ' + absolutePosition.index) // => cursor location is 3
 *
 */

class RelativePosition {
  /**
   * @param {ID|null} type
   * @param {string|null} tname
   * @param {ID|null} item
   */
  RelativePosition(this.type, this.tname, this.item, [this.assoc = 0]);
  /**
     * @type {ID|null}
     */
  ID? type;
  /**
     * @type {string|null}
     */
  String? tname;
  /**
     * @type {ID | null}
     */
  ID? item;

  /**
   * A relative position is associated to a specific character. By default
   * assoc >= 0, the relative position is associated to the character
   * after the meant position.
   * I.e. position 1 in 'ab' is associated to character 'b'.
   *
   * If assoc < 0, then the relative position is associated to the character
   * before the meant position.
   *
   * @type {number}
   */
  int assoc;
}

/**
 * @param {RelativePosition} rpos
 * @return {any}
 */
Map<String, Object?> relativePositionToJSON(RelativePosition rpos) {
  final json = <String, Object?>{};
  if (rpos.type case ID id) {
    json['type'] = {'client': id.client, 'clock': id.clock};
  }
  if (rpos.tname case String tname) {
    json['tname'] = tname;
  }
  if (rpos.item case ID id) {
    json['innerItem'] = {'client': id.client, 'clock': id.clock};
  }
  if (rpos.assoc != 0) {
    json['assoc'] = rpos.assoc;
  }
  return json;
}

/**
 * @param {any} json
 * @return {RelativePosition}
 *
 * @function
 */
RelativePosition createRelativePositionFromJSON(Map<String, Object?> json) {
  final type = json["type"] as Map<String, Object?>?;
  // TODO: innerItem?
  final innerItem = json["innerItem"] as Map<String, Object?>?;
  return RelativePosition(
    type == null
        ? null
        : createID(
            type["client"] as int,
            type["clock"] as int,
          ),
    json["tname"] as String?,
    innerItem == null
        ? null
        : createID(
            innerItem["client"] as int,
            innerItem["clock"] as int,
          ),
    json['assoc'] as int? ?? 0
  );
}

class AbsolutePosition {
  /**
   * @param {AbstractType<any>} type
   * @param {number} index
   */
  AbsolutePosition(this.type, this.index, [this.assoc = 0]);
  /**
     * @type {AbstractType<any>}
     */
  final AbstractType type;
  /**
     * @type {number}
     */
  final int index;

  final int assoc;
}

/**
 * @param {AbstractType<any>} type
 * @param {number} index
 *
 * @function
 */
AbsolutePosition createAbsolutePosition(AbstractType type, int index, [int assoc = 0]) =>
    AbsolutePosition(type, index, assoc);

/**
 * @param {AbstractType<any>} type
 * @param {ID|null} item
 *
 * @function
 */
RelativePosition createRelativePosition(AbstractType type, ID? item, [int assoc = 0]) {
  ID? typeid;
  String? tname;
  final typeItem = type.innerItem;
  if (typeItem == null) {
    tname = findRootTypeKey(type);
  } else {
    typeid = createID(typeItem.id.client, typeItem.id.clock);
  }
  return RelativePosition(typeid, tname, item, assoc);
}

/**
 * Create a relativePosition based on a absolute position.
 *
 * @param {AbstractType<any>} type The base type (e.g. YText or YArray).
 * @param {number} index The absolute position.
 * @return {RelativePosition}
 *
 * @function
 */
RelativePosition createRelativePositionFromTypeIndex(
    AbstractType type, int index, [int assoc = 0]) {
  Item? t = type.innerStart;
  if (assoc < 0) {
    // associated to the left character or the beginning of a type, increment index if possible.
    if (index == 0) {
      return createRelativePosition(type, null, assoc);
    }
    index--;
  }
  while (t != null) {
    if (!t.deleted && t.countable) {
      if (t.length > index) {
        // case 1: found position somewhere in the linked list
        return createRelativePosition(
            type, createID(t.id.client, t.id.clock + index), assoc);
      }
      index -= t.length;
    }
    if (t.right == null && assoc < 0) {
      // left-associated position, return last available id
      return createRelativePosition(type, t.lastId, assoc);
    }
    t = t.right;
  }
  return createRelativePosition(type, null, assoc);
}

/**
 * @param {encoding.Encoder} encoder
 * @param {RelativePosition} rpos
 *
 * @function
 */
encoding.Encoder writeRelativePosition(
    encoding.Encoder encoder, RelativePosition rpos) {
  final type = rpos.type;
  final tname = rpos.tname;
  final item = rpos.item;
  final assoc = rpos.assoc;
  if (item != null) {
    encoding.writeVarUint(encoder, 0);
    writeID(encoder, item);
  } else if (tname != null) {
    // case 2: found position at the end of the list and type is stored in y.share
    encoding.writeUint8(encoder, 1);
    encoding.writeVarString(encoder, tname);
  } else if (type != null) {
    // case 3: found position at the end of the list and type is attached to an item
    encoding.writeUint8(encoder, 2);
    writeID(encoder, type);
  } else {
    throw Exception('Unexpected case');
  }
  encoding.writeVarInt(encoder, assoc);
  return encoder;
}

/**
 * @param {RelativePosition} rpos
 * @return {Uint8Array}
 */
Uint8List encodeRelativePosition(RelativePosition rpos) {
  final encoder = encoding.createEncoder();
  writeRelativePosition(encoder, rpos);
  return encoding.toUint8Array(encoder);
}

/**
 * @param {decoding.Decoder} decoder
 * @return {RelativePosition|null}
 *
 * @function
 */
RelativePosition readRelativePosition(decoding.Decoder decoder) {
  ID? type;
  String? tname;
  ID? itemID;
  switch (decoding.readVarUint(decoder)) {
    case 0:
      // case 1: found position somewhere in the linked list
      itemID = readID(decoder);
      break;
    case 1:
      // case 2: found position at the end of the list and type is stored in y.share
      tname = decoding.readVarString(decoder);
      break;
    case 2:
      // case 3: found position at the end of the list and type is attached to an item
      type = readID(decoder);
  }
  final assoc = decoding.hasContent(decoder) ? decoding.readVarInt(decoder).toInt() : 0;
  return RelativePosition(type, tname, itemID, assoc);
}

/**
 * @param {Uint8Array} uint8Array
 * @return {RelativePosition|null}
 */
RelativePosition decodeRelativePosition(Uint8List uint8Array) =>
    readRelativePosition(decoding.createDecoder(uint8Array));

/**
 * @param {StructStore} store
 * @param {ID} id
 */
(AbstractType<T>, int) getItemWithOffset<T>(StructStore store, ID id) {
  final item = getItem(store, id);
  final diff = id.clock - item.id.clock;
  return (item as AbstractType<T>, diff);
}

/**
 * @param {RelativePosition} rpos
 * @param {Doc} doc
 * @param {boolean} followUndoneDeletions - whether to follow undone deletions - see https://github.com/yjs/yjs/issues/638
 * @return {AbsolutePosition|null}
 *
 * @function
 */
AbsolutePosition? createAbsolutePositionFromRelativePosition(
    RelativePosition rpos, Doc doc, [bool followUndoneDeletions = true]) {
  final store = doc.store;
  final rightID = rpos.item;
  final typeID = rpos.type;
  final tname = rpos.tname;
  final assoc = rpos.assoc;
  AbstractType type;
  var index = 0;
  if (rightID != null) {
    if (getState(store, rightID.client) <= rightID.clock) {
      return null;
    }
    final res = followUndoneDeletions ? followRedone(store, rightID) : getItemWithOffset(store, rightID);
    final right = res.$1;
    if (right is! Item) {
      return null;
    }
    type = /** @type {AbstractType<any>} */ right.parent as AbstractType;
    if (type.innerItem == null || !type.innerItem!.deleted) {
      index = right.deleted || !right.countable ? 0 : (res.$2 + (assoc >= 0 ? 0 : 1)); // adjust position based on left association if necessary;
      var n = right.left;
      while (n != null) {
        if (!n.deleted && n.countable) {
          index += n.length;
        }
        n = n.left;
      }
    }
  } else {
    if (tname != null) {
      type = doc.get(tname);
    } else if (typeID != null) {
      if (getState(store, typeID.client) <= typeID.clock) {
        // type does not exist yet
        return null;
      }
      final item = followUndoneDeletions ? followRedone(store, typeID).$1 : getItem(store, typeID);
      if (item is Item && item.content is ContentType) {
        type = (item.content as ContentType).type;
      } else {
        // struct is garbage collected
        return null;
      }
    } else {
      throw Exception('Unexpected case');
    }
    if (assoc >= 0) {
      index = type.innerLength;
    } else {
      index = 0;
    }
  }
  return createAbsolutePosition(type, index, rpos.assoc);
}

/**
 * @param {RelativePosition|null} a
 * @param {RelativePosition|null} b
 *
 * @function
 */
bool compareRelativePositions(RelativePosition? a, RelativePosition? b) =>
    a == b ||
    (a != null &&
        b != null &&
        a.tname == b.tname &&
        compareIDs(a.item, b.item) &&
        compareIDs(a.type, b.type)) && a.assoc == b.assoc;
