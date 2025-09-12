// import {
//   mergeDeleteSets,
//   iterateDeletedStructs,
//   keepItem,
//   transact,
//   createID,
//   redoItem,
//   iterateStructs,
//   isParentOf,
//   followRedone,
//   getItemCleanStart,
//   getState,
//   ID,
//   Transaction,
//   Doc,
//   Item,
//   GC,
//   DeleteSet,
//   AbstractType, // eslint-disable-line
// } from "../internals.js";

// import * as time from "lib0/time.js";
// import { Observable } from "lib0/observable.js";

import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/types/abstract_type.dart';
import 'package:y_crdt/src/utils/delete_set.dart';
import 'package:y_crdt/src/utils/doc.dart';
import 'package:y_crdt/src/utils/id.dart';
import 'package:y_crdt/src/utils/is_parent_of.dart';
import 'package:y_crdt/src/utils/observable.dart';
import 'package:y_crdt/src/utils/struct_store.dart';
import 'package:y_crdt/src/utils/transaction.dart';

class StackItem {
  /**
   * @param {DeleteSet} deletions
   * @param {DeleteSet} insertions
   */
  StackItem(this.deletions, this.insertions);
  DeleteSet deletions;
  DeleteSet insertions;
  /**
     * Use this to save and restore metadata like selection range
     */
  final Map meta = {};
}

/**
 * @param {Transaction} tr
 * @param {UndoManager} um
 * @param {StackItem} stackItem
 */
void clearUndoManagerStackItem(Transaction tr, UndoManager um, StackItem stackItem) {
  iterateDeletedStructs(tr, stackItem.deletions, (item) {
    if (item is Item && um.scope.any((type) => type == tr.doc || isParentOf(type as AbstractType, item))) {
      keepItem(item, false);
    }
  });
}

/**
 * @param {UndoManager} undoManager
 * @param {List<StackItem>} stack
 * @param {string} eventType
 * @return {StackItem?}
 */
StackItem? popStackItem(
    UndoManager undoManager, List<StackItem> stack, String eventType) {
  /**
   * Keep a reference to the transaction so we can fire the event with the changedParentTypes
   * @type {any}
   */
  late Transaction _tr;
  final doc = undoManager.doc;
  final scope = undoManager.scope;
  transact(doc, (transaction) {
    while (stack.length > 0 && undoManager.currStackItem == null) {
      final store = doc.store;
      final stackItem = /** @type {StackItem} */ stack.removeLast();
      /**
         * @type {Set<Item>}
         */
      final itemsToRedo = <Item>{};
      /**
         * @type {List<Item>}
         */
      final itemsToDelete = <Item>[];
      var performedChange = false;
      
      iterateDeletedStructs(transaction, stackItem.insertions, (struct) {
        if (struct is Item) {
          if (struct.redone != null) {
            var (item, diff) = followRedone(store, struct.id);
            if (diff > 0) {
              item = getItemCleanStart(transaction, createID(item.id.client, item.id.clock + diff));
            }
            struct = item;
          }
          if (!struct.deleted && scope.any((type) => type == transaction.doc 
              || isParentOf(/** @type {AbstractType<any>} */ (type), /** @type {Item} */ (struct as Item)))) {
            itemsToDelete.add(struct);
          }
        }
      });
      iterateDeletedStructs(transaction, stackItem.deletions, (struct) {
        if (
          struct is Item &&
          scope.any((type) => type == transaction.doc || isParentOf(/** @type {AbstractType<any>} */ (type), struct)) &&
          // Never redo structs in stackItem.insertions because they were created and deleted in the same capture interval.
          !isDeleted(stackItem.insertions, struct.id)
        ) {
          itemsToRedo.add(struct);
        }
      });
      itemsToRedo.forEach((struct) {
        performedChange = redoItem(transaction, struct, itemsToRedo, 
            stackItem.insertions, undoManager.ignoreRemoteMapChanges, undoManager) != null 
          || performedChange;
      });
      // We want to delete in reverse order so that children are deleted before
      // parents, so we have more information available when items are filtered.
      for (var i = itemsToDelete.length - 1; i >= 0; i--) {
        final item = itemsToDelete[i];
        if (undoManager.deleteFilter(item)) {
          item.delete(transaction);
          performedChange = true;
        }
      }
      undoManager.currStackItem = performedChange ? stackItem : null;
    }
    transaction.changed.forEach((type, subProps) {
      // destroy search marker if necessary
      if (subProps.contains(null) && type.innerSearchMarker != null) {
        type.innerSearchMarker!.length = 0;
      }
    });
    _tr = transaction;
  }, undoManager);

  final res = undoManager.currStackItem;
  if (res != null) {
    final changedParentTypes = _tr.changedParentTypes;
    undoManager.emit('stack-item-popped', [{ 
      'stackItem': res, 'type': eventType, 
      'changedParentTypes': changedParentTypes, 
      'origin': undoManager }, undoManager]);
    undoManager.currStackItem = null;
  }
  return res;
}

/**
 * @typedef {Object} UndoManagerOptions
 * @property {number} [UndoManagerOptions.captureTimeout=500]
 * @property {function(Item):boolean} [UndoManagerOptions.deleteFilter=()=>true] Sometimes
 * it is necessary to filter whan an Undo/Redo operation can delete. If this
 * filter returns false, the type/item won't be deleted even it is in the
 * undo/redo scope.
 * @property {Set<any>} [UndoManagerOptions.trackedOrigins=new Set([null])]
 */

bool _asTrue<T>(T _) => true;

/**
 * @typedef {Object} UndoManagerOptions
 * @property {number} [UndoManagerOptions.captureTimeout=500]
 * @property {function(Transaction):boolean} [UndoManagerOptions.captureTransaction] Do not capture changes of a Transaction if result false.
 * @property {function(Item):boolean} [UndoManagerOptions.deleteFilter=()=>true] Sometimes
 * it is necessary to filter what an Undo/Redo operation can delete. If this
 * filter returns false, the type/item won't be deleted even it is in the
 * undo/redo scope.
 * @property {Set<any>} [UndoManagerOptions.trackedOrigins=new Set([null])]
 * @property {boolean} [ignoreRemoteMapChanges] Experimental. By default, the UndoManager will never overwrite remote changes. Enable this property to enable overwriting remote changes on key-value changes (Y.Map, properties on Y.Xml, etc..).
 * @property {Doc} [doc] The document that this UndoManager operates on. Only needed if typeScope is empty.
 */

/**
 * @typedef {Object} StackItemEvent
 * @property {StackItem} StackItemEvent.stackItem
 * @property {any} StackItemEvent.origin
 * @property {'undo'|'redo'} StackItemEvent.type
 * @property {Map<AbstractType<YEvent<any>>,Array<YEvent<any>>>} StackItemEvent.changedParentTypes
 */

/**
 * Fires 'stack-item-added' event when a stack item was added to either the undo- or
 * the redo-stack. You may store additional stack information via the
 * metadata property on `event.stackItem.meta` (it is a `Map` of metadata properties).
 * Fires 'stack-item-popped' event when a stack item was popped from either the
 * undo- or the redo-stack. You may restore the saved stack information from `event.stackItem.meta`.
 *
 * @extends {ObservableV2<{'stack-item-added':function(StackItemEvent, UndoManager):void, 'stack-item-popped': function(StackItemEvent, UndoManager):void, 'stack-cleared': function({ undoStackCleared: boolean, redoStackCleared: boolean }):void, 'stack-item-updated': function(StackItemEvent, UndoManager):void }>}
 */
class UndoManager extends Observable {
  /**
   * @param {Doc|AbstractType<any>|Array<AbstractType<any>>} typeScope Limits the scope of the UndoManager. If this is set to a ydoc instance, all changes on that ydoc will be undone. If set to a specific type, only changes on that type or its children will be undone. Also accepts an array of types.
   * @param {UndoManagerOptions} options
   */
  UndoManager(
    typeScope, {
    this.captureTimeout = 500,
    this.captureTransaction = _asTrue,
    this.deleteFilter = _asTrue,
    Set<dynamic>? trackedOrigins,
    this.ignoreRemoteMapChanges = false
  }):
    this.trackedOrigins = trackedOrigins ?? {[null]},
    this.doc = typeScope is List ? (typeScope[0] as AbstractType).doc!:
      typeScope is Doc ? typeScope: (typeScope as AbstractType).doc! {

    this.addToScope(typeScope);
    this.trackedOrigins.add(this);
    
    this.doc.on('afterTransaction', afterTransactionHandler);
    this.doc.on('destroy', (_) {
      this.destroy();
    });
  }

  /**
   * @type {Array<AbstractType<any> | Doc>}
   */
  late final List scope = [];

  late final Doc doc;
  
  final bool Function(Item) deleteFilter;

  late final Set<dynamic> trackedOrigins;

  final bool Function(Transaction) captureTransaction;

  
  /**
     * @type {List<StackItem>}
     */
  List<StackItem> undoStack = [];
  /**
     * @type {List<StackItem>}
     */
  List<StackItem> redoStack = [];
  /**
     * Whether the client is currently undoing (calling UndoManager.undo)
     *
     * @type {boolean}
     */
  bool undoing = false;
  bool redoing = false;

  /**
   * The currently popped stack item if UndoManager.undoing or UndoManager.redoing
   *
   * @type {StackItem|null}
   */
  StackItem? currStackItem;
  
  int lastChange = 0;

  final bool ignoreRemoteMapChanges;

  final int captureTimeout;

  /**
   * @param {Transaction} transaction
   */
  void afterTransactionHandler(List args) {
    final transaction = args[0] as Transaction;
    // Only track certain transactions
    if (
      !this.captureTransaction(transaction) ||
      !this.scope.any((type) => transaction.changedParentTypes.containsKey(/** @type {AbstractType<any>} */ (type)) || type == this.doc) ||
      (!this.trackedOrigins.contains(transaction.origin) && (transaction.origin == null || !this.trackedOrigins.contains(transaction.origin.runtimeType)))
    ) {
      return;
    }
    final undoing = this.undoing;
    final redoing = this.redoing;
    final stack = undoing ? this.redoStack : this.undoStack;
    if (undoing) {
      this.stopCapturing(); // next undo should not be appended to last stack item
    } else if (!redoing) {
      // neither undoing nor redoing: delete redoStack
      this.clear(false, true);
    }
    final insertions = DeleteSet();
    transaction.afterState.forEach((endClock, client) {
      final startClock = transaction.beforeState[client] ?? 0;
      final len = endClock - startClock;
      if (len > 0) {
        addToDeleteSet(insertions, client, startClock, len);
      }
    });
    // TODO: is milliseconds?
    final now = DateTime.now().millisecondsSinceEpoch;
    bool didAdd = false;
    if (this.lastChange > 0 && now - this.lastChange < this.captureTimeout && stack.length > 0 && !undoing && !redoing) {
      // append change to last stack op
      final lastOp = stack[stack.length - 1];
      lastOp.deletions = mergeDeleteSets([lastOp.deletions, transaction.deleteSet]);
      lastOp.insertions = mergeDeleteSets([lastOp.insertions, insertions]);
    } else {
      // create a new stack op
      stack.add(StackItem(transaction.deleteSet, insertions));
      didAdd = true;
    }
    if (!undoing && !redoing) {
      this.lastChange = now;
    }
    // make sure that deleted structs are not gc'd
    iterateDeletedStructs(transaction, transaction.deleteSet, /** @param {Item|GC} item */ (item) {
      if (item is Item && this.scope.any((type) => type == transaction.doc || isParentOf(type, item))) {
        keepItem(item, true);
      }
    });
    /**
     * @type {[StackItemEvent, UndoManager]}
     */
    final changeEvent = [{ 'stackItem': stack[stack.length - 1], 
      'origin': transaction.origin, 'type': undoing ? 'redo' : 'undo', 
      'changedParentTypes': transaction.changedParentTypes }, this];
    if (didAdd) {
      this.emit('stack-item-added', changeEvent);
    } else {
      this.emit('stack-item-updated', changeEvent);
    }
  }

  /**
   * Extend the scope.
   *
   * @param {Array<AbstractType<any> | Doc> | AbstractType<any> | Doc} ytypes
   */
  void addToScope(ytypes) {
    final tmpSet = this.scope.toSet();
    ytypes = ytypes is List ? ytypes : [ytypes];
    ytypes.forEach((ytype) {
      if (!tmpSet.contains(ytype)) {
        tmpSet.add(ytype);
        // if (ytype is AbstractType ? ytype.doc != this.doc : ytype != this.doc) 
        //   logging.warn('[yjs#509] Not same Y.Doc'); // use MultiDocUndoManager instead. also see https://github.com/yjs/yjs/issues/509
        this.scope.add(ytype);
      }
    });
  }

  /**
   * @param {any} origin
   */
  void addTrackedOrigin(origin) {
    this.trackedOrigins.add(origin);
  }

  /**
   * @param {any} origin
   */
  void removeTrackedOrigin(origin) {
    this.trackedOrigins.remove(origin);
  }

  void clear([bool clearUndoStack = true, bool clearRedoStack = true]) {
    if ((clearUndoStack && this.canUndo()) || (clearRedoStack && this.canRedo())) {
      this.doc.transact((tr) {
        if (clearUndoStack) {
          this.undoStack.forEach((item) => clearUndoManagerStackItem(tr, this, item));
          this.undoStack = [];
        }
        if (clearRedoStack) {
          this.redoStack.forEach((item) => clearUndoManagerStackItem(tr, this, item));
          this.redoStack = [];
        }
        this.emit('stack-cleared', [{ 
          'undoStackCleared': clearUndoStack, 
          'redoStackCleared': clearRedoStack }]);
      });
    }
  }

  /**
   * UndoManager merges Undo-StackItem if they are created within time-gap
   * smaller than `options.captureTimeout`. Call `um.stopCapturing()` so that the next
   * StackItem won't be merged.
   *
   *
   * @example
   *     // without stopCapturing
   *     ytext.insert(0, 'a')
   *     ytext.insert(1, 'b')
   *     um.undo()
   *     ytext.toString() // => '' (note that 'ab' was removed)
   *     // with stopCapturing
   *     ytext.insert(0, 'a')
   *     um.stopCapturing()
   *     ytext.insert(0, 'b')
   *     um.undo()
   *     ytext.toString() // => 'a' (note that only 'b' was removed)
   *
   */
  void stopCapturing() {
    this.lastChange = 0;
  }

  /**
   * Undo last changes on type.
   *
   * @return {StackItem?} Returns StackItem if a change was applied
   */
  StackItem? undo() {
    this.undoing = true;
    StackItem? res;
    try {
      res = popStackItem(this, this.undoStack, "undo");
    } finally {
      this.undoing = false;
    }
    return res;
  }

  /**
   * Redo last undo operation.
   *
   * @return {StackItem?} Returns StackItem if a change was applied
   */
  StackItem? redo() {
    this.redoing = true;
    StackItem? res;
    try {
      res = popStackItem(this, this.redoStack, "redo");
    } finally {
      this.redoing = false;
    }
    return res;
  }

  /**
   * Are undo steps available?
   *
   * @return {boolean} `true` if undo is possible
   */
  bool canUndo () {
    return this.undoStack.length > 0;
  }

  /**
   * Are redo steps available?
   *
   * @return {boolean} `true` if redo is possible
   */
  bool canRedo () {
    return this.redoStack.length > 0;
  }

  @override
  void destroy () {
    this.trackedOrigins.remove(this);
    this.doc.off('afterTransaction', this.afterTransactionHandler);
    super.destroy();
  }
}
