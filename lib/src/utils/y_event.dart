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
  List<DeltaItem>? innerDelta;

  /**
   * @type {Array<string|number>|null}
   */
  List? _path;

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
    return _path ??= getPathTo(this.currentTarget, this.target);
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
  List<DeltaItem> get delta {
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
      final delta = <DeltaItem>[];
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
        DeltaItem? lastOp;
        void packOp() {
          if (lastOp != null) {
            delta.add(lastOp);
          }
        }

        for (var item = target.innerStart; item != null; item = item.right) {
          if (item.deleted) {
            if (this.deletes(item) && !this.adds(item)) {
              if (lastOp == null || lastOp is! _Delete) {
                packOp();
                lastOp = DeltaItem.delete(0);
              }
              (lastOp as _Delete).delete += item.length;
              deleted.add(item);
            } // else nop
          } else {
            if (this.adds(item)) {
              if (lastOp == null || lastOp is! _Insert) {
                packOp();
                lastOp = DeltaItem.insert([]);
              }
              (lastOp as _Insert).insert = [
                ...lastOp.insert as List,
                ...item.content.getContent(),
              ];
              //lastOp.insert = lastOp.insert.concat(item.content.getContent())
              added.add(item);
            } else {
              if (lastOp == null || lastOp is! _Retain) {
                packOp();
                lastOp = DeltaItem.retain(0);
              }
              (lastOp as _Retain).retain += item.length;
            }
          }
        }
        if (lastOp != null && lastOp is! _Retain) {
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
  final List<DeltaItem> delta;

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

abstract class DeltaItem {
  DeltaItem._({this.isRetain = false});

  final bool isRetain;

  static DeltaItem? fromMap(Map<String, Object?> map) {
    final _attr = (map["attributes"] as Map?)?.cast<String, dynamic>();

    if (map["retain"] is int) {
      DeltaItem.retain(map["retain"] as int, attributes: _attr);
    } else if (map["delete"] is int) {
      DeltaItem.delete(map["delete"] as int, attributes: _attr);
    } else if (map["insert"] is String || map["insert"] is Map) {
      DeltaItem.insert(map["insert"] as Object, attributes: _attr);
    } else {
      return null;
    }
  }

  Map<String, Object?> toMap() {
    return {
      "attributes": this.attributes,
      ...this.when<Map<String, Object?>>(
        delete: (d, _) => {"delete": d},
        retain: (d, _) => {"retain": d},
        insert: (d, _) => {"insert": d},
      )
    };
  }

  @override
  int get hashCode =>
      this.attributes.hashCode ^
      this
          .when<Object>(
            delete: (d, _) => d,
            retain: (d, _) => d,
            insert: (d, _) => d,
          )
          .hashCode;

  @override
  bool operator ==(Object other) {
    if (other is DeltaItem) {
      if (!mapsAreEqual(this.attributes, other.attributes)) {
        return false;
      }
      return this.when(
        delete: (d1, _) =>
            other.maybeWhen(delete: (d2, _) => d2 == d1) ?? false,
        retain: (d1, _) =>
            other.maybeWhen(retain: (d2, _) => d2 == d1) ?? false,
        insert: (d1, _) =>
            other.maybeWhen(insert: (d2, _) {
              if (d1 is Map && d2 is Map) {
                return mapsAreEqual(d1, d2);
              } else {
                return d2 == d1;
              }
            }) ??
            false,
      );
    }
    return false;
  }

  Map<String, dynamic>? get attributes => this.map(
        delete: (e) => e.attributes,
        retain: (e) => e.attributes,
        insert: (e) => e.attributes,
      );

  factory DeltaItem.delete(
    int delete, {
    Map<String, dynamic>? attributes,
  }) = _Delete;
  factory DeltaItem.retain(
    int retain, {
    Map<String, dynamic>? attributes,
  }) = _Retain;
  factory DeltaItem.insert(
    Object insert, {
    Map<String, dynamic>? attributes,
  }) = _Insert;

  T when<T>({
    required T Function(int delete, Map<String, dynamic>? attributes) delete,
    required T Function(int retain, Map<String, dynamic>? attributes) retain,
    required T Function(Object insert, Map<String, dynamic>? attributes) insert,
  }) {
    final v = this;
    if (v is _Delete) return delete(v.delete, v.attributes);
    if (v is _Retain) return retain(v.retain, v.attributes);
    if (v is _Insert) return insert(v.insert, v.attributes);
    throw "";
  }

  T? maybeWhen<T>({
    T Function()? orElse,
    T Function(int delete, Map<String, dynamic>? attributes)? delete,
    T Function(int retain, Map<String, dynamic>? attributes)? retain,
    T Function(Object insert, Map<String, dynamic>? attributes)? insert,
  }) {
    final v = this;
    if (v is _Delete) {
      return delete != null ? delete(v.delete, v.attributes) : orElse?.call();
    }
    if (v is _Retain) {
      return retain != null ? retain(v.retain, v.attributes) : orElse?.call();
    }
    if (v is _Insert) {
      return insert != null ? insert(v.insert, v.attributes) : orElse?.call();
    }
    throw "";
  }

  T map<T>({
    required T Function(_Delete value) delete,
    required T Function(_Retain value) retain,
    required T Function(_Insert value) insert,
  }) {
    final v = this;
    if (v is _Delete) return delete(v);
    if (v is _Retain) return retain(v);
    if (v is _Insert) return insert(v);
    throw "";
  }

  T? maybeMap<T>({
    T Function()? orElse,
    T Function(_Delete value)? delete,
    T Function(_Retain value)? retain,
    T Function(_Insert value)? insert,
  }) {
    final v = this;
    if (v is _Delete) return delete != null ? delete(v) : orElse?.call();
    if (v is _Retain) return retain != null ? retain(v) : orElse?.call();
    if (v is _Insert) return insert != null ? insert(v) : orElse?.call();
    throw "";
  }
}

class _Delete extends DeltaItem {
  int delete;
  @override
  final Map<String, dynamic>? attributes;

  _Delete(
    this.delete, {
    this.attributes,
  }) : super._();
}

class _Retain extends DeltaItem {
  int retain;
  @override
  final Map<String, dynamic>? attributes;

  _Retain(
    this.retain, {
    this.attributes,
  }) : super._(isRetain: true);
}

class _Insert extends DeltaItem {
  Object insert;
  @override
  final Map<String, dynamic>? attributes;

  _Insert(
    this.insert, {
    this.attributes,
  }) : super._();
}
