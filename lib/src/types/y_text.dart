/**
 * @module YText
 */

// import {
//   YEvent,
//   AbstractType,
//   getItemCleanStart,
//   getState,
//   isVisible,
//   createID,
//   YTextRefID,
//   callTypeObservers,
//   transact,
//   ContentEmbed,
//   GC,
//   ContentFormat,
//   ContentString,
//   splitSnapshotAffectedStructs,
//   iterateDeletedStructs,
//   iterateStructs,
//   findMarker,
//   updateMarkerChanges,
//   ArraySearchMarker,
//   AbstractUpdateDecoder,
//   AbstractUpdateEncoder,
//   ID,
//   Doc,
//   Item,
//   Snapshot,
//   Transaction, // eslint-disable-line
// } from "../internals.js";

// import * as object from "lib0/object.js";
// import * as map from "lib0/map.js";
// import * as error from "lib0/error.js";

import 'package:y_crdt/src/structs/content_embed.dart';
import 'package:y_crdt/src/structs/content_format.dart';
import 'package:y_crdt/src/structs/content_string.dart';
import 'package:y_crdt/src/structs/content_type.dart';
import 'package:y_crdt/src/structs/gc.dart';
import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/types/abstract_type.dart';
import 'package:y_crdt/src/utils/delete_set.dart';
import 'package:y_crdt/src/utils/doc.dart';
import 'package:y_crdt/src/utils/id.dart';
import 'package:y_crdt/src/utils/snapshot.dart';
import 'package:y_crdt/src/utils/struct_store.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';
import 'package:y_crdt/src/utils/y_event.dart';
import 'package:y_crdt/src/y_crdt_base.dart';
import 'package:y_crdt/y_crdt.dart' show AbstractStruct;

import "package:dart_quill_delta/dart_quill_delta.dart" show Operation;

/**
 * @param {any} a
 * @param {any} b
 * @return {boolean}
 */
bool equalAttrs(dynamic a, dynamic b) =>
    a == b ||
    (a is Map &&
        b is Map &&
        a.length == b.length &&
        a.entries.every((entry) =>
            b.containsKey(entry.key) && b[entry.key] == entry.value));

class ItemTextListPosition {
  /**
   * @param {Item|null} left
   * @param {Item|null} right
   * @param {number} index
   * @param {Map<string,any>} currentAttributes
   */
  ItemTextListPosition(
      this.left, this.right, this.index, this.currentAttributes);
  Item? left;
  Item? right;
  int index;
  final Map<String, Object?> currentAttributes;

  /**
   * Only call this if you know that this.right is defined
   */
  void forward() {
    final right = this.right;
    if (right == null) {
      throw Exception('Unexpected case');
    }

    switch(right.content) {
      case ContentFormat content:
        if (!right.deleted) {
          updateCurrentAttributes(this.currentAttributes, content);
        }
      default:
        if (!right.deleted) {
          this.index += right.length;
        }
    }

    this.left = this.right;
    this.right = right.right;
  }
}

/**
 * @param {Transaction} transaction
 * @param {ItemTextListPosition} pos
 * @param {number} count steps to move forward
 * @return {ItemTextListPosition}
 *
 * @private
 * @function
 */
ItemTextListPosition findNextPosition(
    Transaction transaction, ItemTextListPosition pos, int count) {
  var right = pos.right;
  while (right != null && count > 0) {
    switch(right.content) {
      case ContentFormat content:
        if (!right.deleted) {
          updateCurrentAttributes(pos.currentAttributes,
            /** @type {ContentFormat} */ content);
        }
      default:
        if (!right.deleted) {
          if (count < right.length) {
            // split right
            getItemCleanStart(transaction, createID(right.id.client, right.id.clock + count));
          }
          pos.index += right.length;
          count -= right.length;
        }
    }
    pos.left = pos.right;
    pos.right = right.right;
    right = pos.right;
    // pos.forward() - we don't forward because that would halve the performance because we already do the checks above
  }
  return pos;
}

/**
 * @param {Transaction} transaction
 * @param {AbstractType<any>} parent
 * @param {number} index
 * @param {boolean} useSearchMarker
 * @return {ItemTextListPosition}
 *
 * @private
 * @function
 */
ItemTextListPosition findPosition(
    Transaction transaction, AbstractType parent, int index, bool useSearchMarker) {
  final currentAttributes = <String, Object?>{};
  final marker = useSearchMarker ? findMarker(parent, index): null;
  if (marker != null) {
    final pos = ItemTextListPosition(
        marker.p.left, marker.p, marker.index, currentAttributes);
    return findNextPosition(transaction, pos, index - marker.index);
  } else {
    final pos =
        ItemTextListPosition(null, parent.innerStart, 0, currentAttributes);
    return findNextPosition(transaction, pos, index);
  }
}

/**
 * Negate applied formats
 *
 * @param {Transaction} transaction
 * @param {AbstractType<any>} parent
 * @param {ItemTextListPosition} currPos
 * @param {Map<string,any>} negatedAttributes
 *
 * @private
 * @function
 */
void insertNegatedAttributes(
  Transaction transaction,
  AbstractType parent,
  ItemTextListPosition currPos,
  Map<String, Object?> negatedAttributes,
) {
  // check if we really need to remove attributes
  var _right = currPos.right,
    rContent = _right?.content;
  while (_right != null &&
      (_right.deleted ||
          (rContent is ContentFormat &&
              (equalAttrs(
                  negatedAttributes.get(
                      /** @type {ContentFormat} */ rContent.key),
                  /** @type {ContentFormat} */ rContent.value)
              && negatedAttributes.containsKey(rContent.key))))) {
    if (!_right.deleted) {
      negatedAttributes.remove(
          /** @type {ContentFormat} */ (_right.content as ContentFormat).key);
    }
    currPos.forward();
    _right = currPos.right;
    rContent = _right?.content;
  }
  final doc = transaction.doc;
  final ownClientId = doc.clientID;
  negatedAttributes.forEach((key, val) {
    final left = currPos.left;
    final right = currPos.right;
    final nextFormat = Item(
      createID(ownClientId, getState(doc.store, ownClientId)),
      left,
      left?.lastId,
      right,
      right?.id,
      parent,
      null,
      ContentFormat(key, val),
    );
    nextFormat.integrate(transaction, 0);
    currPos.right = nextFormat;
    currPos.forward();
  });
}

/**
 * @param {Map<string,any>} currentAttributes
 * @param {ContentFormat} format
 *
 * @private
 * @function
 */
void updateCurrentAttributes(
    Map<String, dynamic> currentAttributes, ContentFormat format) {
  final key = format.key;
  final value = format.value;
  if (value == null) {
    currentAttributes.remove(key);
  } else {
    currentAttributes.set(key, value);
  }
}

/**
 * @param {ItemTextListPosition} currPos
 * @param {Object<string,any>} attributes
 *
 * @private
 * @function
 */
void minimizeAttributeChanges(
    ItemTextListPosition currPos, Map<String, dynamic> attributes) {
  // go right while attributes[right.key] == right.value (or right is deleted)
  while (true) {
    final _right = currPos.right,
      rContent = _right?.content;
    if (_right == null) {
      break;
    } else if (_right.deleted ||
        (rContent is ContentFormat &&
            equalAttrs(attributes[rContent.key], rContent.value))) {
      //
    } else {
      break;
    }
    currPos.forward();
  }
}

/**
 * @param {Transaction} transaction
 * @param {AbstractType<any>} parent
 * @param {ItemTextListPosition} currPos
 * @param {Object<string,any>} attributes
 * @return {Map<string,any>}
 *
 * @private
 * @function
 **/
Map<String, Object?> insertAttributes(
    Transaction transaction,
    AbstractType parent,
    ItemTextListPosition currPos,
    Map<String, Object?> attributes) {
  final doc = transaction.doc;
  final ownClientId = doc.clientID;
  final negatedAttributes = <String, Object?>{};
  // insert format-start items
  for (final key in attributes.keys) {
    final val = attributes[key];
    final currentVal = currPos.currentAttributes.get(key);
    if (!equalAttrs(currentVal, val)) {
      // save negated attribute (set null if currentVal undefined)
      negatedAttributes.set(key, currentVal);
      final left = currPos.left;
      final right = currPos.right;
      currPos.right = Item(
        createID(ownClientId, getState(doc.store, ownClientId)),
        left,
        left?.lastId,
        right,
        right?.id,
        parent,
        null,
        ContentFormat(key, val),
      );
      currPos.right!.integrate(transaction, 0);
      currPos.forward();
    }
  }
  return negatedAttributes;
}

/**
 * @param {Transaction} transaction
 * @param {AbstractType<any>} parent
 * @param {ItemTextListPosition} currPos
 * @param {string|object} text
 * @param {Object<string,any>} attributes
 *
 * @private
 * @function
 **/
void _insertText(
  Transaction transaction,
  AbstractType parent,
  ItemTextListPosition currPos,
  Object text,
  Map<String, Object?> attributes,
) {
  currPos.currentAttributes.forEach((key, val) {
    if (!attributes.containsKey(key)) {
      attributes[key] = null;
      // attributes.remove(key);
    }
  });
  final doc = transaction.doc;
  final ownClientId = doc.clientID;
  minimizeAttributeChanges(currPos, attributes);
  final negatedAttributes =
      insertAttributes(transaction, parent, currPos, attributes);
  // insert content
  final content = switch(text) {
    String text => ContentString(/** @type {string} */ text),
    AbstractType _ => ContentType(text),
    _ => ContentEmbed((text as Map).cast<String, dynamic>())
  };
  final index = currPos.index;
  var right = currPos.right;
  final left = currPos.left;
  final searchMarker = parent.innerSearchMarker;
  if (searchMarker != null && searchMarker.isNotEmpty) {
    updateMarkerChanges(searchMarker, currPos.index, content.getLength());
  }
  right = Item(createID(ownClientId, getState(doc.store, ownClientId)), left,
      left?.lastId, right, right?.id, parent, null, content);
  right.integrate(transaction, 0);
  currPos.right = right;
  currPos.index = index;
  currPos.forward();
  insertNegatedAttributes(transaction, parent, currPos, negatedAttributes);
}

/**
 * @param {Transaction} transaction
 * @param {AbstractType<any>} parent
 * @param {ItemTextListPosition} currPos
 * @param {number} length
 * @param {Object<string,any>} attributes
 *
 * @private
 * @function
 */
void formatText(
  Transaction transaction,
  AbstractType parent,
  ItemTextListPosition currPos,
  int length,
  Map<String, Object?> attributes,
) {
  final doc = transaction.doc;
  final ownClientId = doc.clientID;
  minimizeAttributeChanges(currPos, attributes);
  final negatedAttributes =
      insertAttributes(transaction, parent, currPos, attributes);
  // iterate until first non-format or null is found
  // delete all formats with attributes[format.key] != null
  // also check the attributes after the first non-format as we do not want to insert redundant negated attributes there
  // eslint-disable-next-line no-labels
  while (currPos.right != null
    && (length > 0 || (negatedAttributes.isNotEmpty
      && (currPos.right!.deleted 
      || currPos.right!.content is ContentFormat)))) {
    final _right = currPos.right!;
    if (!_right.deleted) {
      final _content = _right.content;
      if (_content is ContentFormat) {
        final key = /** @type {ContentFormat} */ _content.key;
        final value = /** @type {ContentFormat} */ _content.value;
        final attr = attributes[key];
        if (attributes.containsKey(key)) {
          if (equalAttrs(attr, value)) {
            negatedAttributes.remove(key);
          } else {
            if (length == 0) {
              // no need to further extend negatedAttributes
              // eslint-disable-next-line no-labels
              break;
            }

            negatedAttributes.set(key, value);
          }
          _right.delete(transaction);
        } else {
          currPos.currentAttributes.set(key, value);
        }
      } else {
        if (length < _right.length) {
          getItemCleanStart(transaction,
              createID(_right.id.client, _right.id.clock + length));
        }
        length -= _right.length;
      }
    }
    currPos.forward();
  }
  // Quill just assumes that the editor starts with a newline and that it always
  // ends with a newline. We only insert that newline when a new newline is
  // inserted - i.e when length is bigger than type.length
  if (length > 0) {
    var newlines = "";
    for (; length > 0; length--) {
      newlines += "\n";
    }
    currPos.right = Item(
        createID(ownClientId, getState(doc.store, ownClientId)),
        currPos.left,
        currPos.left?.lastId,
        currPos.right,
        currPos.right?.id,
        parent,
        null,
        ContentString(newlines));
    currPos.right!.integrate(transaction, 0);
    currPos.forward();
  }
  insertNegatedAttributes(transaction, parent, currPos, negatedAttributes);
}

/**
 * Call this function after string content has been deleted in order to
 * clean up formatting Items.
 *
 * @param {Transaction} transaction
 * @param {Item} start
 * @param {Item|null} end exclusive end, automatically iterates to the next Content Item
 * @param {Map<string,any>} startAttributes
 * @param {Map<string,any>} endAttributes This attribute is modified!
 * @return {number} The amount of formatting Items deleted.
 *
 * @function
 */
int cleanupFormattingGap(Transaction transaction, Item _start, Item? curr,
    Map<String, dynamic> startAttributes, Map<String, dynamic> currAttributes) {
  Item? start = _start,
    end = start;
  final endFormats = <String, dynamic>{};
  while (end != null && (!end.countable || end.deleted)) {
    if (!end.deleted && end.content is ContentFormat) {
      final cf = /** @type {ContentFormat} */ (end.content as ContentFormat);
      endFormats.set(cf.key, cf);
    }
    end = end.right;
  }
  var cleanups = 0;
  var reachedCurr = false;
  while (start != end) {
    if (curr == start) {
      reachedCurr = true;
    }
    if (!start!.deleted) {
      switch(start.content) {
        case ContentFormat content:
          final key = content.key,
          value = content.value,
          startAttrValue = startAttributes.get(key);
        if (endFormats.get(key) != content || startAttrValue == value) {
          // Either this format is overwritten or it is not necessary because the attribute already existed.
          start.delete(transaction);
          cleanups++;
          if (!reachedCurr && currAttributes.get(key) == value && startAttrValue != value) {
            if (startAttrValue == null) {
              currAttributes.remove(key);
            } else {
              currAttributes.set(key, startAttrValue);
            }
          }
        }
        if (!reachedCurr && !start.deleted) {
          updateCurrentAttributes(currAttributes, content);
        }
        break;
      }
    }

    start = /** @type {Item} */ start.right;
  }
  return cleanups;
}

/**
 * @param {Transaction} transaction
 * @param {Item | null} item
 */
void cleanupContextlessFormattingGap(Transaction transaction, Item? item) {
  // iterate until item.right is null or content
  var _right = item?.right;
  while (_right != null &&
      (_right.deleted || !_right.countable)) {
    item = _right;
    _right = item.right;
  }
  final attrs = <String>{};
  // iterate back until a content item is found
  while (item != null && (item.deleted || !item.countable)) {
    if (!item.deleted && item.content is ContentFormat) {
      final key =
          /** @type {ContentFormat} */ (item.content as ContentFormat).key;
      if (attrs.contains(key)) {
        item.delete(transaction);
      } else {
        attrs.add(key);
      }
    }
    item = item.left;
  }
}

/**
 * This function is experimental and subject to change / be removed.
 *
 * Ideally, we don't need this function at all. Formatting attributes should be cleaned up
 * automatically after each change. This function iterates twice over the complete YText type
 * and removes unnecessary formatting attributes. This is also helpful for testing.
 *
 * This function won't be exported anymore as soon as there is confidence that the YText type works as intended.
 *
 * @param {YText} type
 * @return {number} How many formatting attributes have been cleaned up.
 */
int cleanupYTextFormatting(YText type) {
  var res = 0;
  transact(/** @type {Doc} */ type.doc!, (transaction) {
    var start = /** @type {Item} */ type.innerStart;
    var end = type.innerStart;
    var startAttributes = <String, dynamic>{};
    final currentAttributes = {...startAttributes};
    while (end != null) {
      if (!end.deleted) {
        if (end.content is ContentFormat) {
          updateCurrentAttributes(
              currentAttributes,
              /** @type {ContentFormat} */ end.content as ContentFormat);
        } else if (end.content is ContentEmbed ||
            end.content is ContentString) {
          res += cleanupFormattingGap(
              transaction, start!, end, startAttributes, currentAttributes);
          startAttributes = {...currentAttributes};
          start = end;
        }
      }
      end = end.right;
    }
  });
  return res;
}

/**
 * This will be called by the transaction once the event handlers are called to potentially cleanup
 * formatting attributes.
 *
 * @param {Transaction} transaction
 */
void cleanupYTextAfterTransaction(Transaction transaction) {
  /**
   * @type {Set<YText>}
   */
  final needFullCleanup = <YText>{};
  // check if another formatting item was inserted
  final doc = transaction.doc;
  for (final en in transaction.afterState.entries) {
    //client, afterClock
    final client = en.key,
      afterClock = en.value;
    final clock = transaction.beforeState.get(client) ?? 0;
    if (afterClock == clock) {
      continue;
    }
    iterateStructs(transaction, /** @type {Array<Item|GC>} */ (doc.store.clients.get(client) as List<AbstractStruct>), 
      clock, afterClock, (_item) {
      final item = _item as Item;
      if (
        !item.deleted && /** @type {Item} */ (item).content is ContentFormat && item is! GC
      ) {
        needFullCleanup.add(/** @type {any} */ (item).parent as YText);
      }
    });
  }
  // cleanup in a new transaction
  transact(doc, (t) {
    iterateDeletedStructs(transaction, transaction.deleteSet, (_item) {
      if (_item is GC || !(/** @type {YText} */ ((_item as YText).parent as YText).innerHasFormatting) 
          || needFullCleanup.contains(/** @type {YText} */ ((_item as YText).parent))) {
        return;
      }
      final item = _item as Item,
        parent = /** @type {YText} */ (item.parent as YText);
      if (item.content is ContentFormat) {
        needFullCleanup.add(parent);
      } else {
        // If no formatting attribute was inserted or deleted, we can make due with contextless
        // formatting cleanups.
        // Contextless: it is not necessary to compute currentAttributes for the affected position.
        cleanupContextlessFormattingGap(t, item);
      }
    });
    // If a formatting item was inserted, we simply clean the whole type.
    // We need to compute currentAttributes for the current position anyway.
    for (final yText in needFullCleanup) {
      cleanupYTextFormatting(yText);
    }
  });
}

/**
 * @param {Transaction} transaction
 * @param {ItemTextListPosition} currPos
 * @param {number} length
 * @return {ItemTextListPosition}
 *
 * @private
 * @function
 */
ItemTextListPosition deleteText(
    Transaction transaction, ItemTextListPosition currPos, int length) {
  final startLength = length;
  final startAttrs = {...currPos.currentAttributes};
  final start = currPos.right;
  Item? right;
  while (length > 0 && (right = currPos.right) != null) {
    if (right!.deleted == false) {
      switch (right.content) {
        case ContentType _:
        case ContentEmbed _:
        case ContentString _:
          if (length < right.length) {
            getItemCleanStart(transaction, createID(right.id.client, right.id.clock + length));
          }
          length -= right.length;
          right.delete(transaction);
          break;
      }
    }
    currPos.forward();
  }
  if (start != null) {
    cleanupFormattingGap(
      transaction,
      start,
      currPos.right,
      startAttrs,
      currPos.currentAttributes,
    );
  }
  final parent = /** @type {AbstractType<any>} */
      /** @type {Item} */ (currPos.left ?? currPos.right)?.parent
          as AbstractType?;
  final searchMarker = parent?.innerSearchMarker;
  if (searchMarker != null && searchMarker.isNotEmpty) {
    updateMarkerChanges(searchMarker, currPos.index, -startLength + length);
  }
  return currPos;
}

/**
 * The Quill Delta format represents changes on a text document with
 * formatting information. For mor information visit {@link https://quilljs.com/docs/delta/|Quill Delta}
 *
 * @example
 *   {
 *     ops: [
 *       { insert: 'Gandalf', attributes: { bold: true } },
 *       { insert: ' the ' },
 *       { insert: 'Grey', attributes: { color: '#cccccc' } }
 *     ]
 *   }
 *
 */

/**
 * Attributes that can be assigned to a selection of text.
 *
 * @example
 *   {
 *     bold: true,
 *     font-size: '40px'
 *   }
 *
 * @typedef {Object} TextAttributes
 */

/**
 * @typedef {Object} DeltaItem
 * @property {number|undefined} DeltaItem.delete
 * @property {number|undefined} DeltaItem.retain
 * @property {string|undefined} DeltaItem.insert
 * @property {Object<string,any>} DeltaItem.attributes
 */

/**
 * Event that describes the changes on a YText type.
 */
class YTextEvent extends YEvent {
  /**
   * @param {YText} ytext
   * @param {Transaction} transaction
   * @param {Set<any>} subs The keys that changed
   */
  YTextEvent(super.ytext, super.transaction, Set subs) {
    for (final sub in subs) {
      if (sub == null) {
        this.childListChanged = true;
      } else {
        this.keysChanged.add(sub);
      }
    }
  }

  /**
   * Whether the children changed.
   * @type {Boolean}
   * @private
   */
  bool childListChanged = false;

  /**
   * Set of all changed attributes.
   * @type {Set<string>}
   */
  final keysChanged = <String>{};

  YChanges? _changes;

  /**
   * @type {{added:Set<Item>,deleted:Set<Item>,keys:Map<string,{action:'add'|'update'|'delete',oldValue:any}>,delta:Array<{insert?:Array<any>|string, delete?:number, retain?:number}>}}
   */
  @override
  YChanges get changes {
    var changes = this._changes;
    if (changes == null) {
      /**
       * @type {{added:Set<Item>,deleted:Set<Item>,keys:Map<string,{action:'add'|'update'|'delete',oldValue:any}>,delta:Array<{insert?:Array<any>|string|AbstractType<any>|object, delete?:number, retain?:number}>}}
       */
      changes = YChanges(
        keys: this.keys,
        delta: this.delta,
        added: {},
        deleted: {},);
      this._changes = changes;
    }
    return changes;
  }

  /**
     * @type {List<DeltaItem>|null}
     */
  List<Operation>? _delta;

  /**
   * Compute the changes in the delta format.
   * A {@link https://quilljs.com/docs/delta/|Quill Delta}) that represents the changes on the document.
   *
   * @type {List<DeltaItem>}
   *
   * @public
   */
  @override
  List<Operation> get delta {
    var delta = this._delta;
    if (delta == null) {
      final y = /** @type {Doc} */ this.target.doc!;
      this._delta = delta = [];
      transact(y, (transaction) {
        final currentAttributes =
            <String, dynamic>{}; // saves all current attributes for insert
        final oldAttributes = <String, dynamic>{};
        var item = this.target.innerStart;
        /**
         * @type {string?}
         */
        String? action;
        /**
         * @type {Object<string,any>}
         */
        final attributes = <String,
            dynamic>{}; // counts added or removed new attributes for retain
        /**
         * @type {string|object}
         */
        Object insert = "";
        var retain = 0;
        var deleteLen = 0;
        void addOp() {
          if (action != null) {
            /**
             * @type {any}
             */
            Operation? op;
            switch (action) {
              case "delete":
              if (deleteLen > 0)
                  op = Operation.delete(deleteLen);
                deleteLen = 0;
                break;
              case "insert":
                if (insert is Map || insert is AbstractType
                    || (insert is String && (insert as String).isNotEmpty)) {
                  Map<String, dynamic>? _attr;
                  if (currentAttributes.length > 0) {
                    _attr = {};
                    currentAttributes.forEach((key, value) {
                      if (value != null) {
                        _attr![key] = value;
                      }
                    });
                  }
                  op = Operation.insert(switch(insert) {
                    AbstractType type => type.toJSON(),
                    _ => insert,
                  }, _attr);
                }
                insert = '';
                break;
              case "retain":
                if (retain > 0)
                  op = Operation.retain(retain,
                      attributes.length > 0 ? {...attributes} : null);
                retain = 0;
                break;
              default:
                throw Exception("Unexpected case");
            }
            if (op != null)
              delta!.add(op);
            action = null;
          }
        }

        while (item != null) {
          switch(item.content) {
            case ContentType _:
            case ContentEmbed _:
              if (this.adds(item)) {
                if (!this.deletes(item)) {
                  addOp();
                  action = 'insert';
                  insert = item.content.getContent()[0];
                  addOp();
                }
              } else if (this.deletes(item)) {
                if (action != 'delete') {
                  addOp();
                  action = 'delete';
                }
                deleteLen += 1;
              } else if (!item.deleted) {
                if (action != 'retain') {
                  addOp();
                  action = 'retain';
                }
                retain += 1;
              }
            case ContentString _:
              if (this.adds(item)) {
                if (!this.deletes(item)) {
                  if (action != 'insert') {
                    addOp();
                    action = 'insert';
                  }
                  //insert += /** @type {ContentString} */ (item.content as ContentString).str;
                  insert = '$insert${(item.content as ContentString).str}';
                }
              } else if (this.deletes(item)) {
                if (action != 'delete') {
                  addOp();
                  action = 'delete';
                }
                deleteLen += item.length;
              } else if (!item.deleted) {
                if (action != 'retain') {
                  addOp();
                  action = 'retain';
                }
                retain += item.length;
              }

            case ContentFormat _:
              final content = item.content as ContentFormat,
                key = content.key,
                value = content.value;
              if (this.adds(item)) {
                if (!this.deletes(item)) {
                  final curVal = currentAttributes.get(key) ?? null;
                  if (!equalAttrs(curVal, value)) {
                    if (action == 'retain') {
                      addOp();
                    }
                    if (equalAttrs(value, (oldAttributes.get(key) ?? null))) {
                      attributes.remove(key);
                    } else {
                      attributes[key] = value;
                    }
                  } else if (value != null) {
                    item.delete(transaction);
                  }
                }
              } else if (this.deletes(item)) {
                oldAttributes.set(key, value);
                final curVal = currentAttributes.get(key) ?? null;
                if (!equalAttrs(curVal, value)) {
                  if (action == 'retain') {
                    addOp();
                  }
                  attributes[key] = curVal;
                }
              } else if (!item.deleted) {
                oldAttributes.set(key, value);
                final attr = attributes[key];
                if (attributes.containsKey(key)) {
                  if (!equalAttrs(attr, value)) {
                    if (action == 'retain') {
                      addOp();
                    }
                    if (value == null) {
                      attributes.remove(key);
                    } else {
                      attributes[key] = value;
                    }
                  } else if (attr != null) { // this will be cleaned up automatically by the contextless cleanup function
                    item.delete(transaction);
                  }
                }
              }
              if (!item.deleted) {
                if (action == 'insert') {
                  addOp();
                }
                updateCurrentAttributes(currentAttributes, /** @type {ContentFormat} */ (item.content as ContentFormat));
              }
          }
          item = item.right;
        }
        addOp();
        while (delta!.isNotEmpty) {
          final lastOp = delta[delta.length - 1];
          if (lastOp.isRetain && lastOp.attributes == null) {
            // retain delta's if they don't assign attributes
            delta.removeLast();
          } else {
            break;
          }
        }
      });
    }
    return delta;
  }
}

/**
 * Type that represents text with formatting information.
 *
 * This type replaces y-richtext as this implementation is able to handle
 * block formats (format information on a paragraph), embeds (complex elements
 * like pictures and videos), and text formats (**bold**, *italic*).
 *
 * @extends AbstractType<YTextEvent>
 */
class YText extends AbstractType<YTextEvent> {
  /**
   * @param {String} [string] The initial value of the YText.
   */
  YText([String? string]) {
    /**
     * Array of pending operations on this type
     * @type {List<function():void>?}
     */
    this._pending = string != null ? [() => this.insert(0, string)] : [];
  }
  /**
     * @type {List<ArraySearchMarker>}
     */
  @override
  final List<ArraySearchMarker> innerSearchMarker = [];

  List<void Function()>? _pending;

  /**
   * Whether this YText contains formatting attributes.
   * This flag is updated when a formatting item is integrated (see ContentFormat.integrate)
   */
  bool innerHasFormatting = false;

  /**
   * Number of characters of this text type.
   *
   * @type {number}
   */
  int get length {
    return this.innerLength;
  }

  /**
   * @param {Doc} y
   * @param {Item} item
   */
  @override
  innerIntegrate(Doc y, Item? item) {
    super.innerIntegrate(y, item);
    try {
      /** @type {List<function>} */ (this._pending!).forEach((f) => f());
    } catch (e) {
      // logger.e(e);
    }
    this._pending = null;
  }

  @override
  innerCopy() {
    return YText();
  }

  /**
   * @return {YText}
   */
  @override
  clone() {
    final text = YText();
    text.applyDelta(this.toDelta());
    return text;
  }

  /**
   * Creates YTextEvent and calls observers.
   *
   * @param {Transaction} transaction
   * @param {Set<null|string>} parentSubs Keys changed on this type. `null` if list was modified.
   */
  @override
  void innerCallObserver(Transaction transaction, Set<String?> parentSubs) {
    super.innerCallObserver(transaction, parentSubs);
    final event = YTextEvent(this, transaction, parentSubs);
    callTypeObservers(this, transaction, event);
    // If a remote change happened, we try to cleanup potential formatting duplicates.
    if (!transaction.local && this.innerHasFormatting) {
      transaction.innerNeedFormattingCleanup = true;
    }
  }

  /**
   * Returns the unformatted string representation of this YText type.
   *
   * @public
   */
  @override
  String toString() {
    var str = "";
    /**
     * @type {Item|null}
     */
    var n = this.innerStart;
    while (n != null) {
      if (!n.deleted && n.countable && n.content is ContentString) {
        str += /** @type {ContentString} */ (n.content as ContentString).str;
      }
      n = n.right;
    }
    return str;
  }

  /**
   * Returns the unformatted string representation of this YText type.
   *
   * @return {string}
   * @public
   */
  @override
  String toJSON() {
    return this.toString();
  }

  /**
   * Apply a {@link Delta} on this shared YText type.
   *
   * @param {any} delta The changes to apply on this element.
   * @param {object}  [opts]
   * @param {boolean} [opts.sanitize] Sanitize input delta. Removes ending newlines if set to true.
   *
   *
   * @public
   */
  void applyDelta(Iterable<Map<String, dynamic>> delta, {bool sanitize = true}) {
    if (this.doc != null) {
      transact(this.doc!, (transaction) {
        final currPos = ItemTextListPosition(null, this.innerStart, 0, {});
        var i = 0;
        for (final op in delta) {
          if (op["insert"] != null) {
            // Quill assumes that the content starts with an empty paragraph.
            // Yjs/Y.Text assumes that it starts empty. We always hide that
            // there is a newline at the end of the content.
            // If we omit this step, clients will see a different number of
            // paragraphs, but nothing bad will happen.
            final _insert = op["insert"];
            final ins = (!sanitize && _insert is String && i == delta.length - 1 
              && currPos.right == null && _insert[_insert.length - 1] == "\n") ? 
                _insert.substring(0, _insert.length - 1)
                : _insert;
            if (ins is! String || ins.length > 0) {
              _insertText(
                transaction,
                this,
                currPos,
                ins!,
                (op["attributes"] as Map?)?.cast() ?? {},
              );
            }
          } else if (op["retain"] != null) {
            formatText(
              transaction,
              this,
              currPos,
              op["retain"] as int,
              (op["attributes"] as Map?)?.cast() ?? {},
            );
          } else if (op["delete"] != null) {
            deleteText(transaction, currPos, op["delete"] as int);
          }
          i++;
        }
      });
    } else {
      /** @type {List<function>} */ (this._pending!)
          .add(() => this.applyDelta(delta));
    }
  }

  /**
   * Returns the Delta representation of this YText type.
   *
   * @param {Snapshot} [snapshot]
   * @param {Snapshot} [prevSnapshot]
   * @param {function('removed' | 'added', ID):any} [computeYChange]
   * @return {any} The Delta representation of this type.
   *
   * @public
   */
  List<Map<String, Object?>> toDelta([
    Snapshot? snapshot,
    Snapshot? prevSnapshot,
    Map<String, dynamic> Function(String, ID)? computeYChange,
  ]) {
    /**
     * @type{List<any>}
     */
    final ops = <Map<String, Object?>>[];
    final currentAttributes = <String, Object?>{};
    final doc = /** @type {Doc} */ this.doc;
    var str = "";
    var n = this.innerStart;
    void packStr() {
      if (str.length > 0) {
        // pack str with attributes to ops
        /**
         * @type {Object<string,any>}
         */
        final attributes = <String, Object?>{};
        var addAttributes = false;
        currentAttributes.forEach((key, value) {
          addAttributes = true;
          attributes[key] = value;
        });
        /**
         * @type {Object<string,any>}
         */
        final op = <String, Object?>{"insert": str};
        if (addAttributes) {
          op["attributes"] = attributes;
        }
        ops.add(op);
        str = "";
      }
    }

    void computeDelta() {
      while (n != null) {
        final _n = n!;
        if (isVisible(_n, snapshot) ||
            (prevSnapshot != null && isVisible(_n, prevSnapshot))) {
          switch(_n.content) {
            case ContentString content:
              final cur = currentAttributes.get("ychange") as Map?;
              if (snapshot != null && !isVisible(_n, snapshot)) {
                if (cur == null ||
                    cur["user"] != _n.id.client ||
                    cur["type"] != "removed") {
                  packStr();
                  currentAttributes.set(
                      "ychange",
                      computeYChange != null
                          ? computeYChange("removed", _n.id)
                          : {"type": "removed"});
                }
              } else if (prevSnapshot != null && !isVisible(_n, prevSnapshot)) {
                if (cur == null ||
                    cur["user"] != _n.id.client ||
                    cur["type"] != "added") {
                  packStr();
                  currentAttributes.set(
                      "ychange",
                      computeYChange != null
                          ? computeYChange("added", _n.id)
                          : {"type": "added"});
                }
              } else if (cur != null) {
                packStr();
                currentAttributes.remove("ychange");
              }
              str +=
                  /** @type {ContentString} */ content.str;

            case ContentType _:
            case ContentEmbed _:
              packStr();
              /**
                   * @type {Object<string,any>}
                   */
              final op = <String, Object?>{
                "insert": /** @type {ContentEmbed} */ _n.content.getContent()[0],
              };
              if (currentAttributes.length > 0) {
                final attrs = /** @type {Object<string,any>} */ {};
                op["attributes"] = attrs;
                currentAttributes.forEach((key, value) {
                  attrs[key] = value;
                });
              }
              ops.add(op);

            case ContentFormat content:
              if (isVisible(_n, snapshot)) {
                packStr();
                updateCurrentAttributes(
                    currentAttributes, content);
              }

          }
        }
        n = _n.right;
      }
      packStr();
    }

    if (snapshot != null || prevSnapshot != null) {
      // snapshots are merged again after the transaction, so we need to keep the
      // transaction alive until we are done
      transact(doc!, (transaction) {
        if (snapshot != null) {
          splitSnapshotAffectedStructs(transaction, snapshot);
        }
        if (prevSnapshot != null) {
          splitSnapshotAffectedStructs(transaction, prevSnapshot);
        }
        computeDelta();
      }, 'cleanup');
    } else {
      computeDelta();
    }
    return ops;
  }

  /**
   * Insert text at a given index.
   *
   * @param {number} index The index at which to start inserting.
   * @param {String} text The text to insert at the specified position.
   * @param {TextAttributes} [attributes] Optionally define some formatting
   *                                    information to apply on the inserted
   *                                    Text.
   * @public
   */
  void insert(
    int index,
    String text, [
    Map<String, Object?>? _attributes,
  ]) {
    if (text.length <= 0) {
      return;
    }
    final y = this.doc;
    if (y != null) {
      transact(y, (transaction) {
        final pos = findPosition(transaction, this, index, _attributes == null);
        final Map<String, Object?> attributes;
        if (_attributes == null) {
          attributes = {};
          // @ts-ignore
          pos.currentAttributes.forEach((k, v) {
            attributes[k] = v;
          });
        } else {
          attributes = {..._attributes};
        }
        _insertText(transaction, this, pos, text, attributes);
      });
    } else {
      /** @type {List<function>} */ (this._pending!)
          .add(() => this.insert(index, text, _attributes));
    }
  }

  /**
   * Inserts an embed at a index.
   *
   * @param {number} index The index to insert the embed at.
   * @param {Object} embed The Object that represents the embed.
   * @param {TextAttributes} attributes Attribute information to apply on the
   *                                    embed
   *
   * @public
   */
  void insertEmbed(
    int index, Object embed, [
    Map<String, Object?>? attributes,
  ]) {
    // if (embed.constructor != Object) {
    //   throw  Exception("Embed must be an Object");
    // }
    final y = this.doc;
    if (y != null) {
      transact(y, (transaction) {
        final pos = findPosition(transaction, this, index, attributes == null);
        _insertText(transaction, this, pos, embed, attributes ?? {});
      });
    } else {
      /** @type {List<function>} */ (this._pending!)
          .add(() => this.insertEmbed(index, embed, attributes ?? {}));
    }
  }

  /**
   * Deletes text starting from an index.
   *
   * @param {number} index Index at which to start deleting.
   * @param {number} length The number of characters to remove. Defaults to 1.
   *
   * @public
   */
  void delete(int index, int length) {
    if (length == 0) {
      return;
    }
    final y = this.doc;
    if (y != null) {
      transact(y, (transaction) {
        deleteText(transaction, findPosition(transaction, this, index, true), length);
      });
    } else {
      /** @type {List<function>} */ (this._pending!)
          .add(() => this.delete(index, length));
    }
  }

  /**
   * Assigns properties to a range of text.
   *
   * @param {number} index The position where to start formatting.
   * @param {number} length The amount of characters to assign properties to.
   * @param {TextAttributes} attributes Attribute information to apply on the
   *                                    text.
   *
   * @public
   */
  void format(int index, int length, Map<String, Object?> attributes) {
    if (length == 0) {
      return;
    }
    final y = this.doc;
    if (y != null) {
      transact(y, (transaction) {
        final pos = findPosition(transaction, this, index, false);
        if (pos.right == null) {
          return;
        }
        formatText(transaction, this, pos, length, attributes);
      });
    } else {
      /** @type {List<function>} */ (this._pending!)
          .add(() => this.format(index, length, attributes));
    }
  }

  /**
   * @param {AbstractUpdateEncoder} encoder
   */
  @override
  void innerWrite(AbstractUpdateEncoder encoder) {
    encoder.writeTypeRef(YTextRefID);
  }
}

/**
 * @param {AbstractUpdateDecoder} decoder
 * @return {YText}
 *
 * @private
 * @function
 */
YText readYText(AbstractUpdateDecoder decoder) => YText();