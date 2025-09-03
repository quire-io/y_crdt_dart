// import {
//   removeEventHandlerListener,
//   callEventHandlerListeners,
//   addEventHandlerListener,
//   createEventHandler,
//   getState,
//   isVisible,
//   ContentType,
//   createID,
//   ContentAny,
//   ContentBinary,
//   getItemCleanStart,
//   ContentDoc, YText, YArray, AbstractUpdateEncoder, Doc, Snapshot, Transaction, EventHandler, YEvent, Item, // eslint-disable-line
// } from '../internals.js'

// import * as map from 'lib0/map.js'
// import * as iterator from 'lib0/iterator.js'
// import * as error from 'lib0/error.js'
// import * as math from 'lib0/math.js'

import 'dart:typed_data';

import 'package:y_crdt/src/structs/content_any.dart';
import 'package:y_crdt/src/structs/content_binary.dart';
import 'package:y_crdt/src/structs/content_type.dart';
import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/utils/doc.dart';
import 'package:y_crdt/src/utils/event_handler.dart';
import 'package:y_crdt/src/utils/id.dart';
import 'package:y_crdt/src/utils/snapshot.dart';
import 'package:y_crdt/src/utils/struct_store.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';
import 'package:y_crdt/src/utils/y_event.dart';
import 'package:y_crdt/src/y_crdt_base.dart';

/**
 * Accumulate all (list) children of a type and return them as an Array.
 *
 * @param {AbstractType<any>} t
 * @return {List<Item>}
 */
List<Item> getTypeChildren(AbstractType t) {
  var s = t.innerStart;
  final arr = <Item>[];
  while (s != null) {
    arr.add(s);
    s = s.right;
  }
  return arr;
}

/**
 * Call event listeners with an event. This will also add an event to all
 * parents (for `.observeDeep` handlers).
 *
 * @template EventType
 * @param {AbstractType<EventType>} type
 * @param {Transaction} transaction
 * @param {EventType} event
 */
void callTypeObservers<EventType extends YEvent>(
    AbstractType<EventType> type, Transaction transaction, EventType event) {
  final changedType = type;
  final changedParentTypes = transaction.changedParentTypes;

  AbstractType<YEvent> _type = type;
  while (true) {
    // @ts-ignore
    changedParentTypes.putIfAbsent(_type, () => []).add(event);
    if (_type.innerItem == null) {
      break;
    }
    _type = /** @type {AbstractType<any>} */ _type.innerItem!.parent
        as AbstractType<YEvent>;
  }
  callEventHandlerListeners(changedType._eH, event, transaction);
}

/**
 * @template EventType
 * Abstract Yjs Type class
 */
class AbstractType<EventType> {
  static AbstractType<EventType> create<EventType>() =>
      AbstractType<EventType>();
  /**
     * @type {Item|null}
     */
  Item? innerItem;
  /**
     * @type {Map<string,Item>}
     */
  Map<String, Item> innerMap = {};
  /**
     * @type {Item|null}
     */
  Item? innerStart;
  /**
     * @type {Doc|null}
     */
  Doc? doc;
  int innerLength = 0;
  /**
     * Event handlers
     * @type {EventHandler<EventType,Transaction>}
     */
  final EventHandler<EventType, Transaction> _eH = createEventHandler();
  /**
     * Deep event handlers
     * @type {EventHandler<List<YEvent>,Transaction>}
     */
  final EventHandler<List<YEvent>, Transaction> innerdEH = createEventHandler();

  /**
   * Integrate this type into the Yjs instance.
   *
   * * Save this struct in the os
   * * This type is sent to other client
   * * Observer functions are fired
   *
   * @param {Doc} y The Yjs instance
   * @param {Item|null} item
   */
  void innerIntegrate(Doc y, Item? item) {
    this.doc = y;
    this.innerItem = item;
  }

  /**
   * @return {AbstractType<EventType>}
   */
  AbstractType<EventType> innerCopy() {
    throw UnimplementedError();
  }

  /**
   * @param {AbstractUpdateEncoder} encoder
   */
  void innerWrite(AbstractUpdateEncoder encoder) {
    throw UnimplementedError();
  }

  /**
   * The first non-deleted item
   */
  Item? get innerFirst {
    var n = this.innerStart;
    while (n != null && n.deleted) {
      n = n.right;
    }
    return n;
  }

  /**
   * Creates YEvent and calls all type observers.
   * Must be implemented by each type.
   *
   * @param {Transaction} transaction
   * @param {Set<null|string>} parentSubs Keys changed on this type. `null` if list was modified.
   */
  void innerCallObserver(Transaction transaction, Set<String?> parentSubs) {
    /* skip if no type is specified */
  }

  /**
   * Observe all events that are created on this type.
   *
   * @param {function(EventType, Transaction):void} f Observer function
   */
  void observe(void Function(EventType, Transaction) f) {
    addEventHandlerListener(this._eH, f);
  }

  /**
   * Observe all events that are created by this type and its children.
   *
   * @param {function(List<YEvent>,Transaction):void} f Observer function
   */
  void observeDeep(void Function(List<YEvent>, Transaction) f) {
    addEventHandlerListener(this.innerdEH, f);
  }

  /**
   * Unregister an observer function.
   *
   * @param {function(EventType,Transaction):void} f Observer function
   */
  void unobserve(void Function(EventType, Transaction) f) {
    removeEventHandlerListener(this._eH, f);
  }

  /**
   * Unregister an observer function.
   *
   * @param {function(List<YEvent>,Transaction):void} f Observer function
   */
  void unobserveDeep(void Function(List<YEvent>, Transaction) f) {
    removeEventHandlerListener(this.innerdEH, f);
  }

  /**
   * @abstract
   * @return {any}
   */
  Object toJSON() {
    throw UnimplementedError();
  }
}

/**
 * @param {AbstractType<any>} type
 * @return {List<any>}
 *
 * @private
 * @function
 */
List typeListToArray(AbstractType type) {
  final cs = <dynamic>[];
  var n = type.innerStart;
  while (n != null) {
    if (n.countable && !n.deleted) {
      final c = n.content.getContent();
      for (var i = 0; i < c.length; i++) {
        cs.add(c[i]);
      }
    }
    n = n.right;
  }
  return cs;
}

/**
 * @param {AbstractType<any>} type
 * @param {Snapshot} snapshot
 * @return {List<any>}
 *
 * @private
 * @function
 */
List typeListToArraySnapshot(AbstractType type, Snapshot snapshot) {
  final cs = <dynamic>[];
  var n = type.innerStart;
  while (n != null) {
    if (n.countable && isVisible(n, snapshot)) {
      final c = n.content.getContent();
      for (var i = 0; i < c.length; i++) {
        cs.add(c[i]);
      }
    }
    n = n.right;
  }
  return cs;
}

/**
 * Executes a provided function on once on overy element of this YArray.
 *
 * @param {AbstractType<any>} type
 * @param {function(any,number,any):void} f A function to execute on every element of this YArray.
 *
 * @private
 * @function
 */
void typeListForEach<L, R extends AbstractType<dynamic>>(
    R type, void Function(L, int, R) f) {
  var index = 0;
  var n = type.innerStart;
  while (n != null) {
    if (n.countable && !n.deleted) {
      final c = n.content.getContent();
      for (var i = 0; i < c.length; i++) {
        f(c[i] as L, index++, type);
      }
    }
    n = n.right;
  }
}

/**
 * @template C,R
 * @param {AbstractType<any>} type
 * @param {function(C,number,AbstractType<any>):R} f
 * @return {List<R>}
 *
 * @private
 * @function
 */
List<R> typeListMap<C, R, T extends AbstractType<dynamic>>(
    T type, R Function(C, int, T) f) {
  /**
   * @type {List<any>}
   */
  final result = <R>[];
  typeListForEach<C, T>(type, (c, i, _) {
    result.add(f(c, i, type));
  });
  return result;
}

/**
 * @param {AbstractType<any>} type
 * @return {IterableIterator<any>}
 *
 * @private
 * @function
 */
Iterator<T> typeListCreateIterator<T>(AbstractType type) {
  return TypeListIterator<T>(type.innerStart);
}

class TypeListIterator<T> implements Iterator<T> {
  TypeListIterator(this.n);
  Item? n;
  List<dynamic>? currentContent;
  int currentContentIndex = 0;
  T? _value;

  @override
  T get current => _value as T;

  @override
  bool moveNext() {
    // find some content
    if (currentContent == null) {
      while (n != null && n!.deleted) {
        n = n!.right;
      }
      // check if we reached the end, no need to check currentContent, because it does not exist
      if (n == null) {
        return false;
      }
      // we found n, so we can set currentContent
      currentContent = n!.content.getContent();
      currentContentIndex = 0;
      n = n!.right; // we used the content of n, now iterate to next
    }
    final _currentContent = currentContent!;
    _value = _currentContent[currentContentIndex++] as T;
    // check if we need to empty currentContent
    if (_currentContent.length <= currentContentIndex) {
      currentContent = null;
    }
    return true;
  }
}

/**
 * Executes a provided function on once on overy element of this YArray.
 * Operates on a snapshotted state of the document.
 *
 * @param {AbstractType<any>} type
 * @param {function(any,number,AbstractType<any>):void} f A function to execute on every element of this YArray.
 * @param {Snapshot} snapshot
 *
 * @private
 * @function
 */
void typeListForEachSnapshot(AbstractType type,
    void Function(dynamic, int, AbstractType) f, Snapshot snapshot) {
  var index = 0;
  var n = type.innerStart;
  while (n != null) {
    if (n.countable && isVisible(n, snapshot)) {
      final c = n.content.getContent();
      for (var i = 0; i < c.length; i++) {
        f(c[i], index++, type);
      }
    }
    n = n.right;
  }
}

/**
 * @param {AbstractType<any>} type
 * @param {number} index
 * @return {any}
 *
 * @private
 * @function
 */
dynamic typeListGet(AbstractType type, int index) {
  for (var n = type.innerStart; n != null; n = n.right) {
    if (!n.deleted && n.countable) {
      if (index < n.length) {
        return n.content.getContent()[index];
      }
      index -= n.length;
    }
  }
}

/**
 * @param {Transaction} transaction
 * @param {AbstractType<any>} parent
 * @param {Item?} referenceItem
 * @param {List<Object<string,any>|List<any>|boolean|number|string|Uint8Array>} content
 *
 * @private
 * @function
 */
void typeListInsertGenericsAfter(
  Transaction transaction,
  AbstractType parent,
  Item? referenceItem,
  List<dynamic> content,
) {
  var left = referenceItem;
  final doc = transaction.doc;
  final ownClientId = doc.clientID;
  final store = doc.store;
  final right = referenceItem == null ? parent.innerStart : referenceItem.right;
  /**
   * @type {List<Object|List<any>|number>}
   */
  var jsonContent = <Object>[];
  final packJsonContent = () {
    if (jsonContent.length > 0) {
      left = Item(
          createID(ownClientId, getState(store, ownClientId)),
          left,
          left?.lastId,
          right,
          right?.id,
          parent,
          null,
          ContentAny(jsonContent));
      left!.integrate(transaction, 0);
      jsonContent = [];
    }
  };
  content.forEach((dynamic c) {
    if (c is int ||
        c is double ||
        c is num ||
        c is Map ||
        c is bool ||
        (c is List && c is! Uint8List) ||
        c is String) {
      jsonContent.add(c as Object);
    } else {
      packJsonContent();
      // TODO: or ArrayBuffer
      if (c is Uint8List) {
        left = Item(
          createID(ownClientId, getState(store, ownClientId)),
          left,
          left?.lastId,
          right,
          right?.id,
          parent,
          null,
          ContentBinary(c),
        );
        left!.integrate(transaction, 0);
      } else if (c is AbstractType) {
        left = Item(createID(ownClientId, getState(store, ownClientId)), left,
            left?.lastId, right, right?.id, parent, null, ContentType(c));
        left!.integrate(transaction, 0);
      } else {
        throw Exception('Unexpected content type in insert operation');
      }
    }
  });
  packJsonContent();
}

/**
 * @param {Transaction} transaction
 * @param {AbstractType<any>} parent
 * @param {number} index
 * @param {List<Object<string,any>|List<any>|number|string|Uint8Array>} content
 *
 * @private
 * @function
 */
void typeListInsertGenerics(
  Transaction transaction,
  AbstractType parent,
  int index,
  List<dynamic> content,
) {
  if (index == 0) {
    return typeListInsertGenericsAfter(transaction, parent, null, content);
  }
  var n = parent.innerStart;
  for (; n != null; n = n.right) {
    if (!n.deleted && n.countable) {
      if (index <= n.length) {
        if (index < n.length) {
          // insert in-between
          getItemCleanStart(
              transaction, createID(n.id.client, n.id.clock + index));
        }
        break;
      }
      index -= n.length;
    }
  }
  return typeListInsertGenericsAfter(transaction, parent, n, content);
}

/**
 * @param {Transaction} transaction
 * @param {AbstractType<any>} parent
 * @param {number} index
 * @param {number} length
 *
 * @private
 * @function
 */
void typeListDelete(
    Transaction transaction, AbstractType parent, int index, int _length) {
  var length = _length;
  if (length == 0) {
    return;
  }
  var n = parent.innerStart;
  // compute the first item to be deleted
  for (; n != null && index > 0; n = n.right) {
    if (!n.deleted && n.countable) {
      if (index < n.length) {
        getItemCleanStart(
            transaction, createID(n.id.client, n.id.clock + index));
      }
      index -= n.length;
    }
  }
  // delete all items until done
  while (length > 0 && n != null) {
    if (!n.deleted) {
      if (length < n.length) {
        getItemCleanStart(
            transaction, createID(n.id.client, n.id.clock + length));
      }
      n.delete(transaction);
      length -= n.length;
    }
    n = n.right;
  }
  if (length > 0) {
    throw Exception('array length exceeded');
  }
}

/**
 * @param {Transaction} transaction
 * @param {AbstractType<any>} parent
 * @param {string} key
 *
 * @private
 * @function
 */
void typeMapDelete(Transaction transaction, AbstractType parent, String key) {
  final c = parent.innerMap.get(key);
  if (c != null) {
    c.delete(transaction);
  }
}

/**
 * @param {Transaction} transaction
 * @param {AbstractType<any>} parent
 * @param {string} key
 * @param {Object|number|List<any>|string|Uint8Array|AbstractType<any>} value
 *
 * @private
 * @function
 */
void typeMapSet(
  Transaction transaction,
  AbstractType parent,
  String key,
  Object? value,
) {
  final left = parent.innerMap.get(key);
  final doc = transaction.doc;
  final ownClientId = doc.clientID;
  final AbstractContent content;
  if (value == null) {
    content = ContentAny(<dynamic>[value]);
  } else {
    if (value is int ||
        value is num ||
        value is double ||
        value is Map ||
        value is bool ||
        value is List ||
        value is String) {
      content = ContentAny(<dynamic>[value]);
    } else if (value is Uint8List) {
      content = ContentBinary(/** @type {Uint8Array} */ value);
    } else {
      if (value is AbstractType) {
        content = ContentType(value);
      } else {
        throw Exception('Unexpected content type');
      }
    }
  }
  Item(
    createID(ownClientId, getState(doc.store, ownClientId)),
    left,
    left?.lastId,
    null,
    null,
    parent,
    key,
    content,
  ).integrate(transaction, 0);
}

/**
 * @param {AbstractType<any>} parent
 * @param {string} key
 * @return {Object<string,any>|number|List<any>|string|Uint8Array|AbstractType<any>|undefined}
 *
 * @private
 * @function
 */
dynamic typeMapGet(AbstractType parent, String key) {
  final val = parent.innerMap.get(key);
  return val != null && !val.deleted
      ? val.content.getContent()[val.length - 1]
      : null;
}

/**
 * @param {AbstractType<any>} parent
 * @return {Object<string,Object<string,any>|number|List<any>|string|Uint8Array|AbstractType<any>|undefined>}
 *
 * @private
 * @function
 */
dynamic typeMapGetAll(AbstractType parent) {
  /**
   * @type {Object<string,any>}
   */
  final res = <String, dynamic>{};
  parent.innerMap.forEach((key, value) {
    if (!value.deleted) {
      res[key] = value.content.getContent()[value.length - 1];
    }
  });
  return res;
}

/**
 * @param {AbstractType<any>} parent
 * @param {string} key
 * @return {boolean}
 *
 * @private
 * @function
 */
bool typeMapHas(AbstractType parent, String key) {
  final val = parent.innerMap.get(key);
  return val != null && !val.deleted;
}

/**
 * @param {AbstractType<any>} parent
 * @param {string} key
 * @param {Snapshot} snapshot
 * @return {Object<string,any>|number|List<any>|string|Uint8Array|AbstractType<any>|undefined}
 *
 * @private
 * @function
 */
dynamic typeMapGetSnapshot(AbstractType parent, String key, Snapshot snapshot) {
  var v = parent.innerMap.get(key);
  while (v != null &&
      (!snapshot.sv.containsKey(v.id.client) ||
          v.id.clock >= (snapshot.sv.get(v.id.client) ?? 0))) {
    v = v.left;
  }
  return v != null && isVisible(v, snapshot)
      ? v.content.getContent()[v.length - 1]
      : null;
}

/**
 * @param {Map<string,Item>} map
 * @return {IterableIterator<List<any>>}
 *
 * @private
 * @function
 */
Iterable<MapEntry<String, Item>> createMapIterator(Map<String, Item> map) =>
    map.entries.where((entry) => !entry.value.deleted);
