import 'dart:async';
import 'dart:math' as math;

import 'package:uuid/uuid.dart';
import 'package:y_crdt/src/structs/content_doc.dart';
import 'package:y_crdt/src/structs/content_deleted.dart';
import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/types/abstract_type.dart';
import 'package:y_crdt/src/types/y_array.dart';
import 'package:y_crdt/src/types/y_xml_fragment.dart';
import 'package:y_crdt/src/types/y_map.dart';
import 'package:y_crdt/src/types/y_text.dart';
import 'package:y_crdt/src/utils/observable.dart';
import 'package:y_crdt/src/utils/struct_store.dart';
import 'package:y_crdt/src/utils/transaction.dart' show Transaction, transact;
import 'package:y_crdt/src/utils/undo_manager.dart';
import 'package:y_crdt/src/utils/y_event.dart';
import 'package:y_crdt/src/y_crdt_base.dart';

const globalTransact = transact;
/**
 * @module Y
 */

// import {
//   StructStore,
//   AbstractType,
//   YArray,
//   YText,
//   YMap,
//   YXmlFragment,
//   transact,
//   ContentDoc,
//   Item,
//   Transaction,
//   YEvent, // eslint-disable-line
// } from "../internals.js";

// import { Observable } from "lib0/observable.js";
// import * as random from "lib0/random.js";
// import * as map from "lib0/map.js";
// import * as array from "lib0/array.js";

final _random = math.Random();
final _uuid = Uuid();
int generateNewClientId() => _random.nextInt(4294967295);

/**
 * @typedef {Object} DocOpts
 * @property {boolean} [DocOpts.gc=true] Disable garbage collection (default: gc=true)
 * @property {function(Item):boolean} [DocOpts.gcFilter] Will be called before an Item is garbage collected. Return false to keep the Item.
 * @property {string} [DocOpts.guid] Define a globally unique identifier for this document
 * @property {any} [DocOpts.meta] Any kind of meta information you want to associate with this document. If this is a subdocument, remote peers will store the meta information as well.
 * @property {boolean} [DocOpts.autoLoad] If a subdocument, automatically load document. If this is a subdocument, remote peers will load the document as well automatically.
 */

/**
 * A Yjs instance handles the state of shared data.
 * @extends Observable<string>
 */
class Doc extends Observable<String> {
  static bool defaultGcFilter(Item _) => true;
  /**
   * @param {DocOpts} [opts] configuration
   */
  Doc({String? guid, this.gc = true, this.gcFilter = Doc.defaultGcFilter,
    this.meta, this.autoLoad = false, this.shouldLoad = true, this.collectionid}): 
      this.guid = guid ?? _uuid.v4() {
    this.clientID = generateNewClientId();

    final completer = Completer();
    this.on('load', (_) {
      this.isLoaded = true;
      completer.complete();
    });
    whenLoaded = completer.future;

    Future provideSyncedPromise() {
      final completer = Completer();
      late EventHandler eventHandler;
      eventHandler = (List args) {
        final isSynced = args.firstOrNull;
        if (isSynced == null || isSynced == true) {
          this.off('sync', eventHandler);
          completer.complete();
        }
      };

      this.on('sync', eventHandler);
      
      return completer.future;
    }

    this.on('sync', (args) {
      final isSynced = args.firstOrNull;
      if (isSynced == false && this.isSynced) {
        this.whenSynced = provideSyncedPromise();
      }
      this.isSynced = isSynced == null || isSynced == true;
      if (this.isSynced && !this.isLoaded) {
        this.emit('load', [this]);
      }
    });

    this.whenSynced = provideSyncedPromise();
  }


  bool gc;
  final bool Function(Item) gcFilter;
  int clientID = generateNewClientId();
  late String guid;
  String? collectionid;
  /**
     * @type {Map<string, AbstractType<YEvent>>}
     */
  final share = <String, AbstractType<YEvent>>{};
  final StructStore store = StructStore();
  /**
     * @type {Transaction | null}
     */
  Transaction? transaction;
  /**
     * @type {List<Transaction>}
     */
  List<Transaction> transactionCleanups = [];
  /**
     * @type {Set<Doc>}
     */
  final subdocs = <Doc>{};
  /**
     * If this document is a subdocument - a document integrated into another document - then _item is defined.
     * @type {Item?}
     */
  Item? item;
  bool shouldLoad;
  final bool autoLoad;
  final dynamic meta;

  /**
   * This is set to true when the persistence provider loaded the document from the database or when the `sync` event fires.
   * Note that not all providers implement this feature. Provider authors are encouraged to fire the `load` event when the doc content is loaded from the database.
   *
   * @type {boolean}
   */
  bool isLoaded = false;

  /**
   * This is set to true when the connection provider has successfully synced with a backend.
   * Note that when using peer-to-peer providers this event may not provide very useful.
   * Also note that not all providers implement this feature. Provider authors are encouraged to fire
   * the `sync` event when the doc has been synced (with `true` as a parameter) or if connection is
   * lost (with false as a parameter).
   */
  bool isSynced = false;
  bool isDestroyed = false;

  /**
   * Promise that resolves once the document has been loaded from a persistence provider.
   */
  late Future whenLoaded;
  
  /**
   * Promise that resolves once the document has been synced with a backend.
   * This promise is recreated when the connection is lost.
   * Note the documentation about the `isSynced` property.
   */  
  late Future whenSynced;

  /**
   * Notify the parent document that you request to load data into this subdocument (if it is a subdocument).
   *
   * `load()` might be used in the future to request any provider to load the most current data.
   *
   * It is safe to call `load()` multiple times.
   */
  void load() {
    final item = this.item;
    if (item != null && !this.shouldLoad) {
      globalTransact(
          /** @type {any} */ (item.parent as dynamic).doc as Doc,
          (transaction) {
        transaction.subdocsLoaded.add(this);
      }, null, true);
    }
    this.shouldLoad = true;
  }

  Set<Doc> getSubdocs() {
    return this.subdocs;
  }

  Set<dynamic> getSubdocGuids() {
    return this.subdocs.map((doc) => doc.guid).toSet();
  }

  /**
   * Changes that happen inside of a transaction are bundled. This means that
   * the observer fires _after_ the transaction is finished and that all changes
   * that happened inside of the transaction are sent as one message to the
   * other peers.
   *
   * @param {function(Transaction):void} f The function that should be executed as a transaction
   * @param {any} [origin] Origin of who started the transaction. Will be stored on transaction.origin
   *
   * @public
   */
  void transact(void Function(Transaction) f, [dynamic origin]) {
    globalTransact(this, f, origin);
  }

  /**
   * Define a shared data type.
   *
   * Multiple calls of `y.get(name, TypeConstructor)` yield the same result
   * and do not overwrite each other. I.e.
   * `y.define(name, Y.Array) == y.define(name, Y.Array)`
   *
   * After this method is called, the type is also available on `y.share.get(name)`.
   *
   * *Best Practices:*
   * Define all types right after the Yjs instance is created and store them in a separate object.
   * Also use the typed methods `getText(name)`, `getArray(name)`, ..
   *
   * @example
   *   const y = new Y(..)
   *   const appState = {
   *     document: y.getText('document')
   *     comments: y.getArray('comments')
   *   }
   *
   * @param {string} name
   * @param {Function} TypeConstructor The constructor of the type definition. E.g. Y.Text, Y.Array, Y.Map, ...
   * @return {AbstractType<any>} The created type. Constructed with TypeConstructor
   *
   * @public
   */
  T get<T extends AbstractType<YEvent>>(
    String name, [
    T Function()? typeConstructor,
  ]) {
    if (typeConstructor == null) {
      //Type name is wrong when compile to js
      // if (T.toString() == "AbstractType<YEvent>") {
        typeConstructor = () => AbstractType.create<YEvent>() as T;
      // } else {
      //   throw Exception();
      // }
    }
    final type = this.share.putIfAbsent(name, () {
      // @ts-ignore
      final t = typeConstructor!();
      t.innerIntegrate(this, null);
      return t;
    });
    //Type name is wrong when compile to js
    // if (T.toString() != "AbstractType<YEvent>" && type is! T) {
    if (type is! T) {
      // if (type.runtimeType.toString() == "AbstractType<YEvent>") {
        // @ts-ignore
        final t = typeConstructor();
        t.innerMap = type.innerMap;
        type.innerMap.forEach(
            /** @param {Item?} n */ (_, n) {
          Item? item = n;
          for (; item != null; item = item.left) {
            // @ts-ignore
            item.parent = t;
          }
        });
        t.innerStart = type.innerStart;
        for (var n = t.innerStart; n != null; n = n.right) {
          n.parent = t;
        }
        t.innerLength = type.innerLength;
        this.share.set(name, t);
        t.innerIntegrate(this, null);
        return t;
      // } else {
      //   throw Exception(
      //       "Type with the name ${name} has already been defined with a different constructor");
      // }
    }
    return type;
    // return type as T;
  }

  /**
   * @template T
   * @param {string} [name]
   * @return {YList<T>}
   *
   * @public
   */
  YArray<T> getArray<T>([String name = ""]) {
    // @ts-ignore
    return this.get<YArray<T>>(name, YArray.new);
  }

  /**
   * @param {string} [name]
   * @return {YText}
   *
   * @public
   */
  YText getText([String name = ""]) {
    // @ts-ignore
    return this.get<YText>(name, YText.new);
  }

  /**
   * @param {string} [name]
   * @return {YMap<any>}
   *
   * @public
   */
  YMap<T> getMap<T>([String name = ""]) {
    // @ts-ignore
    return this.get<YMap<T>>(name, YMap.new);
  }

  /**
   * @param {string} [name]
   * @return {YXmlFragment}
   *
   * @public
   */
  YXmlFragment getXmlFragment([String name = ""]) {
    // @ts-ignore
    return this.get(name, YXmlFragment.new);
  }

  /**
   * Converts the entire document into a js object, recursively traversing each yjs type
   * Doesn't log types that have not been defined (using ydoc.getType(..)).
   *
   * @deprecated Do not use this method and rather call toJSON directly on the shared types.
   *
   * @return {Object<string, any>}
   */
  @Deprecated('Do not use this method and rather call toJSON directly on the shared types.')
  Map<String, dynamic> toJSON() {
    /**
     * @type {Object<string, any>}
     */
    final doc = <String, dynamic>{};

    // TODO: use Map.map
    this.share.forEach((key, value) {
      doc[key] = value.toJSON();
    });

    return doc;
  }

  /**
   * Emit `destroy` event and unregister all event handlers.
   */
  @override
  void destroy() {
    this.isDestroyed = true;
    this.subdocs.toList().forEach((subdoc) => subdoc.destroy());
    final item = this.item;
    if (item != null) {
      this.item = null;
      late Doc doc;
      
      if (item.content case ContentDeleted content) {
        content.doc = doc = Doc( guid: this.guid, 
          shouldLoad: false);
      } else {
        final content = item.content as ContentDoc;
        content.doc = doc = Doc(
          guid: this.guid,
          gc: content.opts.gc ?? true, 
          autoLoad: content.opts.autoLoad ?? false,
          meta: content.opts.meta,
          shouldLoad: false
        );
      }
      
      doc.item = item;
      globalTransact(
          /** @type {any} */ (item.parent as AbstractType).doc!, (transaction) {
        if (!item.deleted) {
          transaction.subdocsAdded.add(doc);
        }
        transaction.subdocsRemoved.add(this);
      }, null, true);
    }
    this.emit("destroyed", [true]);
    this.emit("destroy", [this]);
    super.destroy();
  }

  @override
  String toString() {
    return 'Doc(guid: $guid)';
  }
}

Map<String, dynamic> toSubdocsEventData({
    required Set<Doc> subdocsLoaded,
    required Set<Doc> subdocsRemoved, 
    required Set<Doc> subdocsAdded}) {
  return {
    'loaded': subdocsLoaded, 
    'added': subdocsAdded, 
    'removed': subdocsRemoved 
  };
}

({Set<Doc> loaded, Set<Doc> added, Set<Doc> removed}) fromSubdocsEventData(List args) {
  final data = args[0] as Map<String, dynamic>;
  return (
    loaded: (data['loaded'] as Set<Doc>?) ?? <Doc>{}, 
    added: (data['added'] as Set<Doc>?) ?? <Doc>{}, 
    removed: (data['removed'] as Set<Doc>?) ?? <Doc>{}
  );
}

Map<String, dynamic> toUndoEventData({
    required StackItem stackItem,
    required String? type, 
    required Map<AbstractType<YEvent>, List<YEvent>>? changedParentTypes,
    origin}) {
  return {
    'stackItem': stackItem, 
      'origin': origin, 
      'type': type, 
      'changedParentTypes': changedParentTypes
  };
}

({StackItem stackItem, String? type, dynamic origin, 
    Map<AbstractType<YEvent>, List<YEvent>>? changedParentTypes}) fromUndoEventData(List args) {
  final data = args[0] as Map<String, dynamic>;
  return (
    stackItem: data['stackItem'] as StackItem,
    type: data['type'] as String?,
    origin: data['origin'],
    changedParentTypes: (data['changedParentTypes'] as Map<AbstractType<YEvent>, List<YEvent>>?)
  );
}
