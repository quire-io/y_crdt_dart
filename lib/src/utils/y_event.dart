// import {
//   isDeleted,
//   Item,
//   AbstractType,
//   Transaction,
//   AbstractStruct, // eslint-disable-line
// } from "../internals.js";

// import * as set from "lib0/set.js";
// import * as array from "lib0/array.js";

import 'package:y_crdt/src/structs/abstract_struct.dart';
import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/types/abstract_type.dart';
import 'package:y_crdt/src/utils/delete_set.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/y_crdt_base.dart';

import "package:dart_quill_delta/dart_quill_delta.dart" show Operation;

const errorComputeChanges = 'You must not compute changes after the event-handler fired.';

/**
 * YEvent describes the changes on a YType.
 */
class YEvent {
  /**
   * @param {AbstractType<any>} target The changed type.
   * @param {Transaction} transaction
   */
  YEvent(this.target, this.transaction) : currentTarget = target;
  /**
     * The type on which this event was created on.
     * @type {AbstractType<any>}
     */
  final AbstractType<YEvent> target;
  /**
     * The current target on which the observe callback is called.
     * @type {AbstractType<any>}
     */
  AbstractType currentTarget;
  /**
     * The transaction that triggered this event.
     * @type {Transaction}
     */
  Transaction transaction;
  /**
     * @type {Object|null}
     */
  YChanges? _changes;

  /**
     * @type {null | Map<string, { action: 'add' | 'update' | 'delete', oldValue: any, newValue: any }>}
     */
  Map<String, YChange>? _keys;

  /**
   * @type {null | Array<{ insert?: string | Array<any> | object | AbstractType<any>, retain?: number, delete?: number, attributes?: Object<string, any> }>}
   */
  List<Operation>? innerDelta;

  /**
   * @type {Array<string|number>|null}
   */
  List? innerPath;

  /**
   * Computes the path from `y` to the changed type.
   *
   * The following property holds:
   * @example
   *   var type = y
   *   event.path.forEach(dir => {
   *     type = type.get(dir)
   *   })
   *   type == event.target // => true
   */
  List get path {
    return innerPath ??= getPathTo(this.currentTarget, this.target);
  }

  /**
   * Check if a struct is deleted by this event.
   *
   * In contrast to change.deleted, this method also returns true if the struct was added and then deleted.
   *
   * @param {AbstractStruct} struct
   * @return {boolean}
   */
  bool deletes(AbstractStruct struct) {
    return isDeleted(this.transaction.deleteSet, struct.id);
  }

  Map<String, YChange> get keys {
    var _keys = this._keys;
    if (_keys == null) {
      if (this.transaction.doc.transactionCleanups.isEmpty) {
        throw Exception(errorComputeChanges);
      }
      final keys = <String, YChange>{};
      final target = this.target;
      final changed = /** @type Set<string|null> */ (this.transaction.changed.get(target) as Set);
      changed.forEach((key) {
        if (key != null) {
          final item = /** @type {Item} */ ((target as AbstractType).innerMap.get(key) as Item);
          /**
           * @type {'delete' | 'add' | 'update'}
           */
          YChangeType? action;
          var oldValue;
          if (this.adds(item)) {
            var prev = item.left;
            while (prev != null && this.adds(prev)) {
              prev = prev.left;
            }
            if (this.deletes(item)) {
              if (prev != null && this.deletes(prev)) {
                action = YChangeType.delete;
                oldValue = prev.content.getContent().lastOrNull;
              } else {
                return;
              }
            } else {
              if (prev != null && this.deletes(prev)) {
                action = YChangeType.update;
                oldValue = prev.content.getContent().lastOrNull;
              } else {
                action = YChangeType.add;
                oldValue = null;
              }
            }
          } else {
            if (this.deletes(item)) {
              action = YChangeType.delete;
              oldValue = /** @type {Item} */ item.content.getContent().lastOrNull;
            } else {
              return; // nop
            }
          }
          keys.set(key, YChange(action, oldValue, null));
        }
      });
      this._keys = _keys = keys;
    }
    return _keys;
  }

  /**
   * This is a computed property. Note that this can only be safely computed during the
   * event call. Computing this property after other changes happened might result in
   * unexpected behavior (incorrect computation of deltas). A safe way to collect changes
   * is to store the `changes` or the `delta` object. Avoid storing the `transaction` object.
   *
   * @type {Array<{insert?: string | Array<any> | object | AbstractType<any>, retain?: number, delete?: number, attributes?: Object<string, any>}>}
   */
  List<Operation> get delta {
    return this.changes.delta;
  }

  /**
   * Check if a struct is added by this event.
   *
   * In contrast to change.deleted, this method also returns true if the struct was added and then deleted.
   *
   * @param {AbstractStruct} struct
   * @return {boolean}
   */
  bool adds(AbstractStruct struct) {
    return struct.id.clock >=
        (this.transaction.beforeState.get(struct.id.client) ?? 0);
  }

  /**
   * @return {{added:Set<Item>,deleted:Set<Item>,keys:Map<string,{action:'add'|'update'|'delete',oldValue:any}>,delta:List<{insert:List<any>}|{delete:number}|{retain:number}>}}
   */
  YChanges get changes {
    var changes = this._changes;
    if (changes == null) {
      if (this.transaction.doc.transactionCleanups.isEmpty) {
        throw Exception(errorComputeChanges);
      }

      final target = this.target;
      final added = <Item>{};
      final deleted = <Item>{};
      /**
       * @type {List<{insert:List<any>}|{delete:number}|{retain:number}>}
       */
      final delta = <Operation>[];
      /**
       * @type {Map<string,{ action: 'add' | 'update' | 'delete', oldValue: any}>}
       */
      final keys = <String, YChange>{};
      changes = YChanges(
        added: added,
        deleted: deleted,
        delta: delta,
        keys: keys,
      );
      final changed =
          /** @type Set<string|null> */ this.transaction.changed.get(target);
      if (changed!.contains(null)) {
        /**
         * @type {any}
         */
        Operation? lastOp;
        void packOp() {
          if (lastOp != null) {
            delta.add(lastOp);
          }
        }

        for (var item = target.innerStart; item != null; item = item.right) {
          if (item.deleted) {
            if (this.deletes(item) && !this.adds(item)) {
              if (lastOp == null || lastOp.key != Operation.deleteKey) {
                packOp();
                lastOp = Operation.delete(0);
              }
              lastOp = Operation.delete(lastOp.length! + item.length);
              deleted.add(item);
            } // else nop
          } else {
            if (this.adds(item)) {
              if (lastOp == null || lastOp.key != Operation.insertKey) {
                packOp();
                lastOp = Operation.insert([]);
              }
              lastOp = Operation.insert([
                ...lastOp.data as List,
                ...item.content.getContent(),
              ]);
              //lastOp.insert = lastOp.insert.concat(item.content.getContent())
              added.add(item);
            } else {
              if (lastOp == null || lastOp.key != Operation.retainKey) {
                packOp();
                lastOp = Operation.retain(0);
              }
              lastOp = Operation.retain(lastOp.length! + item.length);
            }
          }
        }
        if (lastOp != null && lastOp.key != Operation.retainKey) {
          packOp();
        }
      }
      this._changes = changes;
    }
    return /** @type {any} */ changes;
  }
}

class YChanges {
  final Set<Item> added;
  final Set<Item> deleted;
  final Map<String, YChange> keys;
  final List<Operation> delta;

  YChanges({
    required this.added,
    required this.deleted,
    required this.keys,
    required this.delta,
  });

  @override
  String toString() {
    return 'YChanges(added: $added, deleted: $deleted,'
        ' keys: $keys, delta: $delta)';
  }
}

enum YChangeType { add, update, delete }

class YChange {
  final YChangeType action;
  final Object? oldValue, newValue;

  YChange(this.action, this.oldValue, this.newValue);
}

/**
 * Compute the path from this type to the specified target.
 *
 * @example
 *   // `child` should be accessible via `type.get(path[0]).get(path[1])..`
 *   const path = type.getPathTo(child)
 *   // assuming `type is YArray`
 *   console.log(path) // might look like => [2, 'key1']
 *   child == type.get(path[0]).get(path[1])
 *
 * @param {AbstractType<any>} parent
 * @param {AbstractType<any>} child target
 * @return {List<string|number>} Path to the target
 *
 * @private
 * @function
 */
List getPathTo(AbstractType parent, AbstractType child) {
  final path = [];
  var childItem = child.innerItem;
  while (childItem != null && child != parent) {
    if (childItem.parentSub != null) {
      // parent is map-ish
      path.insert(0, childItem.parentSub);
    } else {
      // parent is array-ish
      var i = 0;
      var c =
          /** @type {AbstractType<any>} */ (childItem.parent as AbstractType)
              .innerStart;
      while (c != childItem && c != null) {
        if (!c.deleted) {
          i++;
        }
        c = c.right;
      }
      path.insert(0, i);
    }
    child = /** @type {AbstractType<any>} */ childItem.parent as AbstractType;
    childItem = child.innerItem;
  }
  return path;
}
